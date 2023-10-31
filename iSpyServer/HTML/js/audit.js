function Audit(initOptions) {
    var that = this;
    this.auditDataTable = undefined;
    this.auditSelector = undefined;
    this.classCol = 1;

    this.auditDumpRegions = [{
        name: "search", 
        element: "#searchBox",
        callback: function () {
            console.log("[keyboard callback audit] class search");
        }
    }, {
        name: "list",
        element: "#audit-table-outer",
        callback: function () {
            console.log("[keyboard callback audit] audit event list");
        }
    }];

    keyboard.registerForTabKey({
        view: "audit",
        regions: this.auditDumpRegions      
    });

    $(document).on("KEYDOWN", function () {
        if(__currentView == "audit")
            that.auditSelector.nextRow();
    });
    $(document).on("KEYUP", function () {
        if(__currentView == "audit")
            that.auditSelector.prevRow();
    });

    $.ajax({
        type: "GET",
        url: "/audit.json",
        success: function (data) {
            var json = JSON.parse(data);
            console.log("[audit] Got JSON: ", json);
            that.insecureFrameworks = json;
            that.initialize();
        }
    });
}
Audit.prototype.getDataForCurrentRow = function () {
    var rowObj = this.auditDataTable.row(this.auditSelector.lastSelectedRow);
    return rowObj.data();
}

Audit.prototype.getEventDataForCurrentRow = function () {
    var data = this.getDataForCurrentRow();
    var eventID = data[0] || undefined;
    if(eventID === undefined)
        return undefined;

    __datasourceWorker.postMessage({
        messageType: "getEventDetailForEventID",
        callbackName: "eventDataForCurrentRow",
        eventID: eventID
    });
}

Audit.prototype.initialize = function () {
    
    /*
        Handle row selection for the audit list DataTable
    */
    var that = this;
    this.auditSelector = new TableSelect({
        selector: "#auditTable",
        onSingleSelect: function (selSelf) {
            that.getEventDataForCurrentRow();
            /*var className = getClassNameFromCurrentRow();
            _instanceListDataTable.clear();
            //console.log("[ObjectDumper] Getting instances for " + className + " (" + _objectList[className].length + ")");

            for(var i = 0; i< _objectList[className].length; i++) {
                //console.log("[ObjectDumper] Adding ",_objectList[className][i]);
                _instanceListDataTable.row.add([_objectList[className][i]]).draw();
            }

            _instanceSelector.selectRow(0);
            _instanceSelector.onSingleSelectCallback();
            */
        },
        onMultiSelect: function (selSelf) {
            //if(selSelf.count() > 1)
            //    $("#object-details-outer").addClass("dimmed");
        },
        onChange: function (selSelf) {
            /*var len = selSelf.count();
            var classStr = "" + len;
            classStr += ((len > 1)?" classes":" class");
            $("#spanClassAdd").html(classStr);
            $("#spanClassRemove").html(classStr);
            $("#spanClassRemoveAndClear").html(classStr);
            */
        },
        onDblClick: function (objSelf) {
            /*var className = getClassNameFromCurrentRow();
            if(className == null)
                return;

            __classDumpPopup.renderClass({
                className: className,
                callback: function (objSelf) {
                    $(objSelf.DOMElement).removeClass("hidden");
                    $("#class-dump-popup-modal").modal('show');
                }
            });
            */
        }
    });

    /*
        Create the class list DataTable
    */
    this.auditDataTable = $('#auditTable').DataTable({
        dom: "t",
        select: {
            style: "os"
        },
        bootstrap: true,
        serverSide: false,
        paging: false,
        info: false,
        order: false,
        bAutoWidth: true,
        deferRender: true
    });

    // Set the Web Worker looking for these call events
    __datasourceWorker.postMessage({
        messageType: "setCallWatchList",
        watchList: this.insecureFrameworks
    });

    // register a callback to render a new row in the UI for each captured audit event
    var that = this;
    __datasourceRegisterCallback(function(event) {
        if(event === undefined || event.data === undefined || event.data['messageType'] === undefined)
            return;

        switch(event.data["messageType"]) {

            case "auditCallEvent":
                var eventData = event.data["eventData"];
                var className = eventData["class"];
                var selector = eventData["selector"];
                var classification = eventData["classification"];
                var description = eventData["description"];
                var callbackFunctionName = eventData["callback"] || undefined;
                var eventJSONString = JSON.stringify(eventData["JSON"]) || undefined;

                //console.log("that datatable] eventData", eventData);
                if(eventJSONString === undefined) {
                    console.log("[audit]] eventJSONString was undefined, abandon ship");
                    break;
                }

                var eventID = eventData["JSON"]["count"];
                //console.log("[audit] count (eventID) = ", eventID);

                that.auditDataTable.row.add([
                    eventID,
                    classification,
                    className,
                    selector,
                    description
                ]).draw();

                var retVal = undefined;
                if(callbackFunctionName !== undefined && eventJSONString !== undefined) {
                    retVal = eval("that." + callbackFunctionName + "(" + eventJSONString + ")");
                }

                break;

            case "eventDataForCurrentRow":

                console.log("[audit] datasourceHandler got some eventDataForCurrentRow data:", event.data);               

                //var json = event.data["json"];
                var renderedHTML = event.data["renderedHTML"] || "WTF";

                $("#auditDataSection").html(renderedHTML);

                break;
        }
    });
}


