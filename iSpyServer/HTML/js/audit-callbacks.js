/*
    Callback functions for events described in audit.json
*/

/*
    This example just shows data in/out, you get the idea:
    Receives JSON "args" representing the objc_msgSend event that triggered this callback.

    var args = {
        argArray: [ ],
        args: { },
        callTypeSymbol: "-",
        class: "NSUserDefaults",        //  << Class
        count: 5156,
        depth: 4,
        indentMarkup: "",
        isInstanceMethod: 1,
        messageType: "objc_msgSend",
        method: "synchronize",          // << Method
        numArgs: 0,
        objectAddr: "0x1859f830",       // << Address of this object
        renderedMethod: "<span class=\"objcMethod\">synchronize</span>",
        returnTypeCode: "c",
        returnValue: {
            objectAddr: "0x1",
            type: "char",
            value: "0x1 (1) (' ')"
        },
        thread: 974323712
    };
*/
Audit.prototype.audit_synchronize = function (args) {
    //console.log("[audit_synchronize] this = ", this);
    //console.log("[audit_synchronize] args = ", args["JSON"]);
    
    return "0xdeadbeef";
}
