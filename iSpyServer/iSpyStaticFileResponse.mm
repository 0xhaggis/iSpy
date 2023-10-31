#import "iSpyStaticFileResponse.h"


@implementation iSpyStaticFileResponse

- (NSDictionary *) httpHeaders
{

    NSDictionary *contentTypes = @{
        @"html": @"text/html; charset=UTF-8",
        @"js": @"text/javascript",
        @"css": @"text/css",
        @"png": @"image/png",
        @"jpg": @"image/jpeg",
        @"jpeg": @"image/jpeg",
        @"ico": @"image/ico",
        @"gif": @"image/gif",
        @"svg": @"image/svg+xml",
        @"tff": @"application/x-font-ttf",
        @"eot": @"application/vnd.ms-fontobject",
        @"woff": @"application/x-font-woff",
        @"otf": @"application/x-font-otf"
    };

    /* If we don't know the mime-type we serve the file as binary data */
    NSString *contentType = [contentTypes valueForKey:[filePath pathExtension]];
    if (!contentType || [contentType length] == 0)
    {
        contentType = @"application/octet-stream";
    }

    NSString *contentDisposition = nil;
    if([[filePath pathExtension] isEqualToString:@"ipa"]) {
        contentDisposition = @"attachment; filename=\"decrypted-app.ipa\"";
    }

    NSDictionary *headers = [[NSDictionary alloc] initWithObjectsAndKeys:
        contentType, @"Content-type",
        @"nosniff", @"X-Content-Type-Options",
        @"SAMEORIGIN", @"X-Frame-Options",
        @"1; mode=block", @"X-XSS-Protection",
        (contentDisposition)?contentDisposition:@"Bar", (contentDisposition)?@"Content-Disposition":@"Foo",
    nil];

    return headers;
}

@end
