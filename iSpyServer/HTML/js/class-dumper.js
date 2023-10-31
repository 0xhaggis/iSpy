function ClassDumper(options) {
	this.DOMElement = options["DOMElement"];
	$(this.DOMElement).addClass("hidden");
	
	this.methodData = [];
	this.options = options;
	this.className = undefined;
	this.propertiesHTML = "";

	this.propertiesDOMElement = this.DOMElement + "-properties-element";
	this.methodListDOMElement = this.DOMElement + "-methods-element";
	var tmp = "" + this.propertiesDOMElement;
	this.cleanPropertiesDOMElement = tmp.replace("#", "");
	tmp = "" + this.methodListDOMElement;
	this.cleanMethodListDOMElement = tmp.replace("#", "");
	
	var mustacheJSON = {
		propertiesDOMElement: this.propertiesDOMElement,
		methodListDOMElement: this.methodListDOMElement
	};

	/*
	1. generate element names
	2. generate json for those
	3. generate html based on json
	4. create methods DataTable
	*/
	//console.log("[ClassDump init] this: ", this);
	
	var pre = document.createElement("pre");
	var code1 = document.createElement("code");
	var code2 = document.createElement("code");
	var table = document.createElement("table");
	var thead = document.createElement("thead");
	var tr = document.createElement("tr");
	var th = document.createElement("th");
	var tbody = document.createElement("tbody");

	$(code1).attr("id", this.cleanPropertiesDOMElement);
	$(table).attr("id", this.cleanMethodListDOMElement);
	$(table).addClass("table table-condensed table-hover hover method-list-table");
	$(th).html("Methods");
	$(tr).append(th)
	$(thead).append(tr);
	$(table).append(thead);
	$(table).append(tbody);
	$(code2).append(table);
	$(pre).append(code1);
	$(pre).append(code2);

	$(this.DOMElement).html(pre);

	this.methodSelector = new TableSelect({
		selector: this.methodListDOMElement,
		onSingleSelect: function () {},
		onShiftSelect: function () {},
		onMetaSelect: function () {},
		onChange: function () {}
	});

	/*
		Create the method list DataTable
	*/

	var that = this;
	this.methodListDataTable = $(this.methodListDOMElement).DataTable({
		dom: "t",
		select: {
			style: "os"
		},
		bootstrap: true,
		serverSide: true,
		paging: false,
		info: false,
		order: false,
		bAutoWidth: true,
		deferRender: true,
		ajax: function ( data, callback, settings ) {
			if(!that.methodData || !that.methodData[0] || !that.methodData[0][0])
				that.methodData = [];

            callback({
            	data: that.methodData,
            });
        }
	});

	var methodContextMenu = [{
		text: 'Add <span id="spanMethodAdd"></span> to watchlist',
		action: function(e){
			if(that.methodSelector.count() == 0) {
				var selectedRow = context.lastEvent().currentTarget._DT_RowIndex;
				that.methodSelector.selectRow(selectedRow);
			}
			that.addSelectedMethodsToWhitelist();
			e.preventDefault();
		}
	}, {
		text: 'Remove <span id="spanMethodRemove"></span> from watchlist',
		action: function(e){
			if(that.methodSelector.count() == 0) {
				var selectedRow = context.lastEvent().currentTarget._DT_RowIndex;
				that.methodSelector.selectRow(selectedRow);
			}
			that.removeSelectedMethodsFromWhitelist();
			e.preventDefault();
		}
	}, {
		text: 'Remove <span id="spanMethodRemoveAndClear"></span> from watchlist and clear from log',
		action: function(e){
			if(that.methodSelector.count() == 0) {
				var selectedRow = context.lastEvent().currentTarget._DT_RowIndex;
				that.methodSelector.selectRow(selectedRow);
			}
			that.removeSelectedMethodsFromWhitelist(CLEAR_FROM_LOG);
			e.preventDefault();
		}
	}];

	context.attach(this.methodListDOMElement + " tr", methodContextMenu);

	this.renderClass = ClassDumper.prototype.renderClass;
	this.renderClass("NSString");		
}

ClassDumper.prototype.startClassDump = function() {
	var that = this;
	var className = this.className;
	var DOMElement = this.DOMElement;

	return $.ajax({
		type: "POST",
		url: "/rpc",
		dataType: "text",
		processData: false,
		data: '{"messageType": "classDumpClassFull", "messageData": {"class":"' + className + '"}}',
		success: function (data) {
			//console.log("[startClassDump] Got AJAX data: ", data);
			var DOMElement = (data["DOMElement"]) ? data["DOMElement"] : "#classDumpCode";
			var json = JSON.parse(data);
			if(!json)
				return;
			
			json = json["JSON"];
			if(!json)
				return;
			
			json = json["classDump"];
			if(!json)
				return;
			
			// Fix up the formatting of pointers in ivars
			//console.log("[ClassDump] Length: ", json["ivars"].length, json);
			for(var i = 0; i < json["ivars"].length; i++) {
				if(json["ivars"][i]["type"].indexOf(" *") == -1)
					json["ivars"][i]["type"] += " ";
			}

			// Cache this class
			//__iSpyClassList[className] = json;

			// Fix up the formatting of Methods
			var methodDeclaration = "";
			that.methodData = [];
			for(i = 0; i < json["methods"].length; i++) {
				if(json["methods"][i]["isInstanceMethod"] == 1)
					json["methods"][i]["methodType"] = "-";
				else
					json["methods"][i]["methodType"] = "+";

				methodDeclaration = "";

				if(watchlist.watchlist()[className] && watchlist.watchlist()[className]["methodCountForWhitelist"] !== undefined) {
					var found;
					found = false;
					for(var m = 0; found === false, m < watchlist.watchlist()[className]["methodCountForWhitelist"]; m++) {
						if(!watchlist.watchlist()[className]["methods"][m] || !json["methods"][i]["selector"])
							continue;

						if(watchlist.watchlist()[className]["methods"][m] === json["methods"][i]["selector"]) {
							found = true;
						}
					}
					if(found === true)
						methodDeclaration += '<span class="glyphicon glyphicon-eye-open watchlist-enabled"></span>&nbsp;';
					else {
						methodDeclaration += '<span class="glyphicon glyphicon-eye-open watchlist-disabled"></span>&nbsp;';
					}
				} else {
					methodDeclaration += '<span class="glyphicon glyphicon-eye-open watchlist-disabled"></span>&nbsp;';
				}

				methodDeclaration += json["methods"][i]["methodType"];
				methodDeclaration += '(<span class="objcType class-link">' + json["methods"][i]["returnType"] + '</span>)';

				if(json["methods"][i]["parameters"].length > 0) {
					for(j = 0; j < json["methods"][i]["parameters"].length; j++) {
						var name = json["methods"][i]["parameters"][j]["name"];
						var type = json["methods"][i]["parameters"][j]["type"];

						methodDeclaration += '<span class="objcMethod">' + name + '</span>:';
						methodDeclaration += '(<span class="objcType class-link">' + type + '</span>)';
					 	methodDeclaration += 'arg' + (j+1);
						if(j < json["methods"][i]["parameters"].length - 1)
							methodDeclaration += ' ';
						else
							methodDeclaration += ';'
					}

					json["methods"][i]["methodDeclaration"] = methodDeclaration;
				} else {
					methodDeclaration += '<span class="objcMethod">' + json["methods"][i]["name"] + '</span>;';
					json["methods"][i]["methodDeclaration"] = methodDeclaration;
				}

				that.methodData.push([methodDeclaration]);
			} 

			if(that.methodData.length < 1)
				that.methodData.push([]);

			that.options["methodData"] = that.methodData;

			// Apply the JSON to the template and write to the UI
			//console.log("[class dump] Rendering JSON: ", json);
			that.propertiesHTML = Handlebars.compile(__mustacheTemplates["classDumpForm"])(json);				
		}
	});
}

ClassDumper.prototype.startObjectDump = function() {
	var that = this;
	var objectAddress = this.objectAddress;
	var DOMElement = this.DOMElement;

	return $.ajax({
		type: "POST",
		url: "/rpc",
		dataType: "text",
		processData: false,
		data: '{ "messageType": "instanceAtAddress", "messageData": { "address":"' + objectAddress + '" } }',
		success: function (data) {
			var json = JSON.parse(data);
			if(json === undefined || json["JSON"] == undefined) {
				return;
			}
			json = json["JSON"];
			//console.log("[ObjectDumper] Response: ", json);
			var renderedHTML = Handlebars.compile(__mustacheTemplates["objectDetailsForm"])(json);
			//$("#object-details-outer").html(renderedHTML);
			that.renderedHTML = renderedHTML;
		}
	});
}

ClassDumper.prototype.renderClass = function(options) {
	if(!options)
		options = {};
	var className = this.className = options["className"];
	var DOMElement = this.DOMElement;
	var callback = options["callback"];
	var that = this;
	
	//console.log("[render] Starting dump. Options: ", options);
	$.when(this.startClassDump()).done(function () {
		//console.log("[renderClass] Setting HTML for props: ", that.propertiesHTML);
		$(document).on("draw.dt", function () {
			$(document).off("draw.dt");
			search.highlightSearchTextInDOMElement(that.propertiesDOMElement);
			search.highlightSearchTextInDOMElement(that.methodListDOMElement);		
		});

		$(that.propertiesDOMElement).html(that.propertiesHTML);
		$(that.methodListDOMElement).DataTable().ajax.reload();
		$(that.methodListDOMElement).removeClass("hidden");
		that.methodSelector.deselectAllRows();	
		//$("#classDumpSection").removeClass("dimmed");
		
		if(callback)
			callback(that);
	});
}

ClassDumper.prototype.renderObject = function(options) {
	if(!options)
		options = {};
	var objectAddress = this.objectAddress = options["objectAddress"];
	var DOMElement = this.DOMElement;
	var callback = options["callback"];
	var that = this;
	//console.log("[renderObject] options = ", options);
	
	//console.log("[render] Starting dump. Options: ", options);
	$.when(this.startObjectDump()).done(function () {
		//console.log("[renderObject] Setting HTML for obj: ", that);
		$(DOMElement).html("&nbsp;"); // force removal of all HTML
		$(DOMElement).html(that.renderedHTML);
		if(callback)
			callback(that);
	});
}

ClassDumper.prototype.getSelectedMethods = function () {
	var len = this.methodSelector.count();
	var methods = [];

	if(__iSpyClassList[this.className] === undefined) {
		console.log("[ClassDumper] Non-app classes are not supported at this time.");
		alert("Whitelisting non-app classes is not a supported feature at this time, sorry.");
		return methods;
	}
	console.log("[classdumper] getSelectedMethods len = " + len + " this:", this);
	for(var m = 0; m < len; m++) {
		var classData = __iSpyClassList[this.className];
		var classMethods = classData["methods"];
		var methodIndex = [this.methodSelector.selectedRows[m]];
		var methodName = classMethods[methodIndex];

		console.log("m: ", m);
		console.log("className: ", this.className);
		console.log("classData: ", classData);
		console.log("classMethods: ", classMethods);
		console.log("methodIndex: ", methodIndex);
		console.log("methodName: ", methodName);
		methods.push(__iSpyClassList[this.className]["methods"][this.methodSelector.selectedRows[m]]);
	}

	//console.log("[classdumper] selected methods after refresh: ", methods);
	return methods;
}

ClassDumper.prototype.refreshMethodListTable = function () {
	var that = this;
	var wl = watchlist.watchlist();
	var methods = __iSpyClassList[that.className]["methods"] || undefined;
	var rowNum = 0;

	that.methodListDataTable.rows().every(function () {
		var d = this.data();
		if(methods === undefined || wl[that.className] === undefined) {
			d[0] = d[0].replace("glyphicon-eye-open watchlist-enabled", "glyphicon-eye-open watchlist-disabled");
		} else {
			var methodName = methods[rowNum];
			
			if(wl[that.className]["methods"].indexOf(methodName) != -1) {
				d[0] = d[0].replace("glyphicon-eye-open watchlist-disabled", "glyphicon-eye-open watchlist-enabled");
			} else {
				d[0] = d[0].replace("glyphicon-eye-open watchlist-enabled", "glyphicon-eye-open watchlist-disabled");
			}
		}

		this.data(d);
		this.invalidate();
		rowNum++;
	});

	that.methodListDataTable.draw();
	that.methodSelector.highlightSelectedRows();
	classBrowser.refreshWhitelistIconForClass(that.className);
}

// This uses cascading promises to synchronize multiple nested ajax requests.
ClassDumper.prototype.removeSelectedMethodsFromWhitelist = function (clearLogs) {	
	var that = this;
	var selectedMethods = this.getSelectedMethods();
	var entries = {
		"classes": [
			{
				"class": this.className, 
				"methods": selectedMethods
			}
		]
	};

	$.when(watchlist.removeEntries(entries)).done(function () {
		$.when(watchlist.refresh()).done(function () {
			if(clearLogs) {
				var message = {
					messageType: "removeEntriesFromObjCLogForMethods",
						searchText: search.text(),
						methods: that.getSelectedMethods(),
						operation: "removeMethod",
						clearLogs: clearLogs,
						class: that.className
				};
				__datasourceWorker.postMessage(message);
			}

			that.refreshMethodListTable();
			classBrowser.refreshWhitelistIconForClass(that.className);
		});
	});
}

// This uses cascading promises to synchronize multiple nested ajax requests.
ClassDumper.prototype.addSelectedMethodsToWhitelist = function () {
	var that = this;
	var selectedMethods = this.getSelectedMethods();
	var entries = {
		"classes": [
			{
				"class": this.className, 
				"methods": selectedMethods
			}
		]
	};

	// send to idevice to be added to watchlist
	$.when(watchlist.addEntries(entries)).done(function () {
		// get new watchlist from device
		$.when(watchlist.refresh()).done(function () {
			that.refreshMethodListTable();
			classBrowser.refreshWhitelistIconForClass(that.className);
		});
	});	

}

