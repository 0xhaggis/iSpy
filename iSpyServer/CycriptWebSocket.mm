#import <Foundation/Foundation.h>
#import "../iSpy.class.h"
#import "CycriptWebSocket.h"
#include <spawn.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/select.h>
#include <dlfcn.h>

#define BUFSIZE 65536
#define MAX_READ_FAILURES 3

static int connect_socket(const char *address, const int connect_port);

@implementation CycriptWebSocket

// callback for CocoaHTTPServer WebSocket class
- (void)didOpen {
    [super didOpen];
    
    ispy_log("Opened new Cycript WebSocket connection. Connecting to Cycript...");
    if([self connectToCycript] == false) {
        ispy_log("[CycriptWebSocket didOpen] Failed to connect to Cycript on 127.0.0.1:%d", [[iSpy sharedInstance] cycriptPort]);
    }
}

// callback for CocoaHTTPServer WebSocket class
- (void)didReceiveMessage:(NSString *)msg {
    //ispy_log("WebSocket Cycript message: %s", [msg UTF8String]);
    char *data = (char *) [msg UTF8String];
    size_t len = (size_t)[msg length];
    size_t bufLen = len + 5;
    
    // if we get an "S" message from term.js, it's data. Send to cycript.
    if(data[0] == 'S') {
        ispy_log("[CycriptWebSocket didReceiveMessage] Got %s (%d) from WebSocket, relaying to cycriptSocket...", data, (int)len);

        char *buf = (char *)malloc((size_t)bufLen); // length word + null
        if(!buf) {
            ispy_log("[CycriptWebSocket didReceiveMessage] malloc faield. Wat.");
            return;
        }

        memset(buf, (char)0, bufLen);
        /*snprintf(buf, bufLen, "%c%c%c%c",   (unsigned char)(messageLen & 0xff),
                                            (unsigned char)(messageLen >>  8 & 0xff),
                                            (unsigned char)(messageLen >> 16 & 0xff),
                                            (unsigned char)(messageLen >> 24 & 0xff));
        */
        /*write([self cycriptSocket], buf, (size_t)4);
        write([self cycriptSocket], buf, (size_t)bufLen);*/
    
        write(self->_cycriptPipe[1], &data[1], (size_t)len - 1);
        ispy_log("[CycriptWebSocket didReceiveMessage] Relaying %s (%d) from WebSocket to cycriptSocket", &data[1], (int)len - 1);
    } 

    /*
        This is legacy code for jailbroken devices that relies on having some form of execve(2)-like mechanism
        to run Cycript.

    // if we get an "R" message from term.js, it means the screen size changed. Adjust our master PTY accordingly.
    // Note: we can only do this in the small time window between allocating a PTY and spawning a new process.
    else if(data[0] == 'R') {
        struct winsize ws;

        sscanf(&data[1], "%hd,%hd", &ws.ws_col, &ws.ws_row);
        ispy_log("Received resize request. rows: %hd, cols: %hd", ws.ws_row, ws.ws_col);

        ioctl([self masterPTY], TIOCSWINSZ, &ws);
    }
    */
}

// callback for CocoaHTTPServer WebSocket class
-(void)didClose {
    ispy_log("WebSocket Cycript connection closed");
 
    // Session over.
    [super didClose];
}

-(BOOL) connectToCycript {
    int pipefd[2];

    NSString *appPath = [[iSpy sharedInstance] appPath];
    const char *cyDylibPath = [[NSString stringWithFormat:@"%@/Frameworks/cycript", appPath] UTF8String];
    
    void *handle = dlopen(cyDylibPath, RTLD_NOW | RTLD_LOCAL);
    ispy_log("[connectToCycript] cy.dylib handle @ %p", handle);
    if(!handle) {
        ispy_log("[connectToCycript] Failed to get handle to Frameworks/cy.dylib");
    }
    
    void (*CYHandleClient)(int) = (void (*)(int))dlsym(handle, "CYHandleClient");
    void (*_main)() = (void (*)())dlsym(handle, "_main");

    ispy_log("[connectToCycript] CYHandleClient @ %p // _main @ %p", CYHandleClient, _main);
    _main = (void (*)())dlsym(handle, "main");
    ispy_log("[connectToCycript] CYHandleClient @ %p // main @ %p", CYHandleClient, _main);
    
    if(!CYHandleClient) {
        ispy_log("[connectToCycript] Failed to get CYHandleClient symbol address from cy.dylib");
    }

    ispy_log("[connectToCycript bg] Connecting to localhost...");
    //int sock = connect_socket("127.0.0.1", [[iSpy sharedInstance] cycriptPort]);
    int sock = connect_socket("192.168.1.88", 31339);

    if(sock == -1) {
        ispy_log("[connectToCycript] Failed to connect to Cycript on 127.0.0.1:%d", [[iSpy sharedInstance] cycriptPort]);
    } else {
        ispy_log("[connectToCycript] Connected to Cycript with socket fd # %d", sock);
    }

    [self setCycriptSocket:sock];

    if(pipe(pipefd) != 0) {
        ispy_log("[connectToCycript] First (stdin) pipe() failed: %s", strerror(errno));
        return false;
    }
    self->_cycriptPipe[0] = pipefd[0];  // this will be used to replace stdin
    self->_cycriptPipe[1] = pipefd[1];  // this will be used in [self didReceiveData]

    // replace stdin with the read end of the pipe
    dup2(pipefd[0], 0);

    if(pipe(pipefd) != 0) {
        ispy_log("[connectToCycript] Second (stdout) pipe() failed: %s", strerror(errno));
        return false;
    } 
    self->_stdoutPipe[0] = pipefd[0];  // this will be used to pass data from cycript to websocket
    self->_stdoutPipe[1] = pipefd[1];  // this will be used to replace stdout

    // replace stdout with the write end of the pipe
    dup2(pipefd[1], 1);

    ispy_log("[connectToCycript bg] Calling CYHandleClient()");
    //CYInitializeDynamic();
    write(sock, "\x05\x00\x00\x00", 4);
    write(sock, "UIApp", 5);
    //CYHandleClient(sock);

    // start a background thread to shovel data from the Cycript socket to the WebSocket
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        ispy_log("[connectToCycript bg] Setting up pipe");
        [self pipeCycriptSocketToWebSocket];
        ispy_log("[connectToCycript bg] Done.");
    });

    return true;
}

-(void) pipeCycriptSocketToWebSocket {
    fd_set readSet;
    char buf[BUFSIZE];
    int numBytes, numFileDescriptors;
    static int failCount = 0;

    ispy_log("[CycriptWebSocket pipeCycriptSocketToWebSocket] Piping Cycript socket %d to WebSocket %@", self->_stdoutPipe[0], self);

    // Loop forever.
    while(1) {
        // ensure things are sane each time around
        numFileDescriptors = 0;
        FD_ZERO(&readSet);
        FD_SET(self->_stdoutPipe[0], &readSet);
        numFileDescriptors = max(numFileDescriptors, self->_stdoutPipe[0]);

        // wait for something interesting to happen on a socket, or abort in case of error
        if(select(numFileDescriptors + 1, &readSet, NULL, NULL, NULL) == -1) {
            ispy_log("DISCONNECT by select");
            close(self->_stdoutPipe[0]);
            [self stop];
            return;
        }
        
        // Data ready to read from socket(s)
        if(FD_ISSET(self->_stdoutPipe[0], &readSet)) {
            // clear the read buffer
            memset(buf, 0, BUFSIZE);

            // read the contents of the Cycript socket buffer, or BUFSIZE-1, whichever is smaller
            if((numBytes = read(self->_stdoutPipe[0], buf, BUFSIZE-1)) < 1) {
                // Ok, crap. A read(2) error occured. 
                // Maybe the child process hasn't started yet.
                // Maybe the child process terminated.
                // Let's handle this a little gracefully.
                ispy_log("READ failure (%d of %d)", ++failCount, MAX_READ_FAILURES);
                
                // retry the read(2) operation 3 times before giving up
                if(failCount == MAX_READ_FAILURES) {
                    ispy_log("Three consecutive read(2) failures. Abandon ship.");
                    
                    close(self->_stdoutPipe[0]);

                    // if we haven't aready done so, shutdown this websocket
                    if(self->isStarted)
                        [self stop];

                    return;
                }

                sleep(1); // pause to let things settle before retrying
            } // if 

            // Ok, we got some data!
            else {
                // reset the failure counter. 
                failCount=0; 

                // pass the data from the child process to the websocket, where it's passed to the browser.
                [self sendMessage:[NSString stringWithUTF8String:buf]];
                ispy_log("msg from cycript: %s", buf);
            }
        }
    } 
}



-(int) forkNewPTY {
    /*self.masterPTY = connect_socket(31338, "127.0.0.1");
    NSLog(@"Cycript socket number is %d", self.masterPTY);
    self.slavePTY = self.masterPTY;
    return self.masterPTY;
    */
    return -1;
/*
    // open a handle to a master PTY 
    if((self.masterPTY = open("/dev/ptmx", O_RDWR | O_NOCTTY | O_NONBLOCK)) == -1) {
        ispy_log("ERROR could not open /dev/ptmx");
        return -1;
    }

    // establish proper ownership of PTY device
    if(grantpt(self.masterPTY) == -1) {
        ispy_log("ERROR could not grantpt()");
        return -1;    
    }

    // unlock slave PTY device associated with master PTY device
    if(unlockpt(self.masterPTY) == -1) {
        ispy_log("ERROR could not unlockpt()");
        return -1;
    }

    // child
    if((self.sshPID = fork()) == 0) {
        if((self.slavePTY = open(ptsname(self.masterPTY), O_RDWR | O_NOCTTY)) == -1) {
            ispy_log("ERROR could not open ptsname(%s)", ptsname(self.masterPTY));
            return -1;
        }
        // setup PTY and redirect stdin, stdout, stderr to it
        setsid();
        ioctl(self.slavePTY, TIOCSCTTY, 0);
        dup2(self.slavePTY, 0);
        dup2(self.slavePTY, 1);
        dup2(self.slavePTY, 2);
        close(self.masterPTY);
        return 0;
    } 
    // parent
    else {
        return self.sshPID;
    }
*/
}

-(void) doexec {
    // Setup the command and environment
    const char *prog[] = { "/usr/bin/cycript", "-r", "127.0.0.1:12345", NULL };
    const char *envp[] = { "TERM=xterm-256color", NULL };

    // replace current process with cycript
    execve((const char *)prog[0], (char **)prog, (char **)envp);
    
    // never returns
}

@end

/*****************
 * connect_socket()
 *
 * Connects to a remote host:port and returns a valid socket if successful.
 * Returns -1 on failure.
 */
static int connect_socket(const char *address, const int connect_port) {
    struct sockaddr_in a;
    struct hostent *ha;
    int s;
    
    // get a fresh juicy socket
    if((s = socket(PF_INET, SOCK_STREAM, 0)) < 0) {
        perror("ERROR: socket()");
        close(s);
        return -1;
    }

    // clear the sockaddr_in structure
    memset(&a, 0, sizeof(a));
    a.sin_port = htons(connect_port);
    a.sin_family = AF_INET;
    
    // get IP from host name, if appropriate
    if((ha = gethostbyname(address)) == NULL) {
        perror("ERROR: gethostbyname()");
        return -1;
    }
    if(ha->h_length == 0) {
        printf("ERROR: No addresses for %s. Aborting.\n", address);
        return -1;
    }
    memcpy(&a.sin_addr, ha->h_addr_list[0], ha->h_length);

    // connect to the remote host
    if(connect(s, (struct sockaddr *) &a, sizeof(a)) < 0) {
        perror("ERROR: connect()");
        shutdown(s, SHUT_RDWR);
        close(s);
        return -1;
    }

    // w00t, it worked.
    return s;
}
