importScripts("handlebars-v4.0.2.js");
importScripts("audit.js");

var _callWatchList = {};
var _holdoffLock = false;
var _iSpySock = undefined;
var _initialized = false;
var _newDataLock = false;
var _numComparisons = 0;

var _fullEventData = [];
var _filteredData = [];
var _mustacheTemplates = {};
var _searchParameters = undefined;
var _previousSearchParameters = undefined;
var _isConnectedToISpy = false;

var _watchlist = { /*
	classes: [
		{
			className: "FoobarClass",
			methods: [
				"barMethod",
				"bozMethod:withFoo:forThing"
			]
		}
	] */			
}

var _dataSource = { // this will all be updated in initializeWorker()
	data: _filteredData,
	filter: "",
	recordsTotal: 0,
	recordsFiltered: 0
}

function isConnectedToISpy() {
	return _isConnectedToISpy;
}

function htmlEntities(str) {
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function jsonMeetsFilterCriteria(jsonObj) {
	// always return true if searching hasn't been initialized (can this happen?)
	if(_searchParameters === undefined) {
		console.log("[datasource] Error, _searchParameters not found");
		return true;
	}

	if(_searchParameters["text"] == "")
		return true;

	// Class
	var isCaseSens = _searchParameters["isCaseSensitive"];
	
	// regex support
	var caseSenseOptionStr = (isCaseSens === true) ? "" : "i";
	var re = new RegExp(_searchParameters["text"], caseSenseOptionStr);

	// debug
	console.log(jsonObj);
	
	if(_searchParameters["isClass"] === true) {
		if(re.test(jsonObj["class"]))
			return true;
	}

	if(_searchParameters["isMethod"] === true) {
		console.log('METHOD search');
		if(re.test(jsonObj["method"])) {
			console.log('METHOD true');
			return true;
		}
	}

	if(_searchParameters["isData"] === true) {
		if(jsonObj["returnTypeCode"] != 'v' && jsonObj["returnValue"] !== undefined)
			if(re.test(jsonObj["returnValue"]["value"]))
				return true;			

		for(var key in jsonObj["args"]) {
			var paramData = jsonObj["args"][key];
			if(re.test(paramData["value"]))
				return true;
		}
	}

	return false;
}

function handle_objc_event_data(jsonStr, json) {
	// Unescape the arguments
	json['argArray'] = [];
	var tmpObj = {};
	for(var k in json['args']) {
		json['args'][k]['value'] = unescape(json['args'][k]['value']);
		tmpObj = {};
		tmpObj['name'] = k;
		tmpObj['type'] = json['args'][k]['type'];
		tmpObj['value'] = json['args'][k]['value'];
		var val = tmpObj['value'];
		var match = val.match(/(^<.*: )(.*?)([>;].*$)/);
		if(match !== null) {
			tmpObj['argAddress'] = match[2];
		}
		json['argArray'].push(tmpObj);
	}

	// Unescape the return value, if present
	if(json['returnValue'])
		json['returnValue']['value'] = unescape(json['returnValue']['value']);

	// prepare some additional fields in the JSON blob
	json['JSONString'] = unescape(jsonStr);
	json['callTypeSymbol'] = (json['isInstanceMethod']) ? '-' : '+';
	json['indentMarkup'] = "";

	var renderableNumericTypes = [
		"char", "int", "double", "float", "long", "short", "unsigned"
	];

	var renderableStringTypes = [
		"__NSCFConstantString", "__NSCFString", "__NSDate", "__NSNumber"
	];

	var renderedMethod = "";
	if(json["numArgs"] == 0)
		renderedMethod = '<span class="objcMethod">' + json["method"] + '</span>';

	for(var key in json["args"]) {
		var paramData = json["args"][key];
		var renderedArgValue = "";
		var renderedArgType = "";
		var value = htmlEntities(paramData["value"]);

		renderedArgType = '<span class="objcMethod">' + key + ":</span>";
		renderedArgType = renderedArgType + '<span class="objcType">(' + paramData["type"] + ')</span>';
		
		// is this a numeric type
		if(renderableNumericTypes.indexOf(paramData["type"]) != -1)
			renderedArgValue = renderedArgValue + '<span class="objcValue">' + value + '</span> ';

		// Is this a string(ish) type?
		else if(renderableStringTypes.indexOf(paramData["type"]) != -1)
			renderedArgValue = renderedArgValue + '<span class="objcValue">@"' + value + '"</span> ';

		// Fall-back to not rendering stuff
		else {
			var val = "";
			if(paramData["value"].length < 128)
				val = paramData["value"];
			else {
				val += paramData["value"];
				val = val.substring(0,125);
				val += "...";
			}
			renderedArgValue = renderedArgValue + '<span class="objcValue">' + htmlEntities(val) + '</span> ';
		}

		renderedMethod += renderedArgType;
		renderedMethod += renderedArgValue;
		renderedMethod += " ";
	}

	json["renderedMethod"] = renderedMethod;

	// Add this event to the master list
	_fullEventData.push(json);
	_dataSource["recordsTotal"]++;

	// If we're filtering results, make sure to add it to the result set where applicable
	if(_dataSource["filter"] != "") {
		if(jsonMeetsFilterCriteria(json)) {
			_dataSource["data"].push(json);
			_dataSource["recordsFiltered"]++;
		}
	} else {
		_dataSource["recordsFiltered"]++;		
	}

	/*
		Check the call watch list to see if we caught an event of interest.
	*/
	var className = json["class"];
	var selector = json["method"]; /// ugh, must fix this naming

	if(_callWatchList[className] !== undefined) {
		console.log("[datasource comparison] Found class " + className);
		if(_callWatchList[className][selector] !== undefined) {
			console.log("[datasource comparison] Found selector " + selector);
			var e = _callWatchList[className][selector];
			e["JSON"] = json;

			self.postMessage({
				messageType: "auditCallEvent",
				eventData: e
			});
		}
	}

	if(_newDataLock === false) {
		_newDataLock = true;
		self.postMessage({
			messageType: "newData",
			recordsTotal: _dataSource["recordsTotal"],
			recordsFiltered: _dataSource["recordsFiltered"],
			maintainSelectedItems: true
		});
		setTimeout(function () {
			_newDataLock = false;
		}, 1000);
	}
}

function connectWorker() {
	console.log("[datasource] Entered connectWorker");
	if(_initialized === false) {
		console.log("[datasource] initialized = false. Initializing.");
		_initialized = true;

		_iSpySock = new WebSocket("ws://127.0.0.1:31337/jsonrpc");

		_iSpySock.onopen = function(event) {
			console.log('[datasource] Web Worker connected to iSpy JSON RPC endpoint: ' + event.currentTarget.url);
			_isConnectedToISpy = true;
			self.postMessage({
				messageType: "connected"
			});
		}

		//
		// Handle incoming messages on the WebSocket
		//
		_iSpySock.onmessage = function(event) {
			// Convert the payload back to a JSON object
			var jsonStr = "" + event.data;
			var theJson = JSON.parse(jsonStr);

			try {
				switch(theJson["messageType"]) {

					case "objc_msgSend":
						handle_objc_event_data(jsonStr, theJson);	
						break;

					case "addObject":
						//console.log("[datasource] Adding object: ", event.data);
						break;

					case "removeObject":
						//console.log("[datasource] Removing object: ", event.data);
						break;

					default:
						//console.log("Message not handled, passing to main thread: ", theJson);
						self.postMessage(theJson);
						break;
				}
			} catch(e) {
				console.log("[datasource] event: ", e);
				console.log("[datasource] JSON: >" + jsonStr + "<");
				console.log(hexdump(jsonStr));
			}

			return;
		} // _iSpySock.onmessage

		_iSpySock.onclose = function() {
			//console.log("[datasource] Web Worker WebSocket was closed. Reconnecting in 1 second.");
			_isConnectedToISpy = false;
			self.postMessage({
				messageType: "close"
			});
			setTimeout(function () {
				_initialized = false;
				//console.log("[datasource] Web Worker Restarting WebSocket now!");
				initializeWorker();
			}, 1000);
		}

		_iSpySock.onerror = function() {
			_isConnectedToISpy = false;
			console.log("[datasource] WebSocket startup barfed while connecting.");
			self.postMessage("error");
			// control will be passed to .onclose next
		}
	} else {
		console.log("[datasource] Already initialized");
	}
} 

function initializeWorker() {
	console.log("[datasource] initializeWorker()");
	_dataSource["filter"] = "0xdeadbeef";
	_dataSource["data"] = _fullEventData;
	_dataSource["recordsTotal"] = 0;
	_dataSource["recordsFiltered"] = 0;
	connectWorker();
}

function makeRequest (url, params) {
	var xhr = new XMLHttpRequest();
	xhr.open("POST", url, false);
	xhr.send(params);

	if(xhr.status >= 200 && xhr.status < 300) {
		//console.log("[datasource] ajax success");
		return xhr.responseText;
	} else {
		//console.log("[datasource] ajax fail - not 200", xhr.status, xhr.statusText);
		return null;
	}
}

function removeEntriesFromDataSet(e) {
	var rows = e.data["rows"] || undefined;
	var searchText = e.data["searchText"] || undefined;
	var ignoreMethods = (e.data["operation"] && e.data["operation"] == "removeClass") ? true : false;
	var deletionMap = {};
	var dataSource;
	var shouldProcessFilteredResults = (searchText !== undefined && searchText.length > 0) ? true : false;
	
	console.log("[datasource] entered removeEntriesFromObjCLog, search = '", searchText, "',' filtered? ", shouldProcessFilteredResults, ", rows = ", rows);
	if(rows === undefined) {
		console.log("[datasource] undefined things. See previous log entry.");
		return;
	}

	if(shouldProcessFilteredResults)
		dataSource = _filteredData;
	else
		dataSource = _fullEventData;

	for(var i = 0; i < rows.length; i++) {
		var data = dataSource[rows[i]];
		var className = data["class"];
		var methodName = data["method"];
		
		if(deletionMap[className] === undefined) { // we haven't seen this class yet
			deletionMap[className] = {};
			deletionMap[className]["methods"] = [];
		}
		
		if(ignoreMethods)
			continue;

		if(deletionMap[className]["methods"].indexOf(data["method"]) == -1)
			deletionMap[className]["methods"].push(data["method"]);
	}
	

	if(e.data["clearLogs"] === true) {
		console.log("deletionMap = ", deletionMap);

		//console.log("[datasource] in len = ", _fullEventData.length, " // e.data.options: ", e.data["options"]);
		var found;
		var fullCounter = 0;
		var filtCounter = 0;
		while(_fullEventData[fullCounter] !== undefined) {
			found = false;
			
			var className = _fullEventData[fullCounter]["class"];
			if(deletionMap[className] !== undefined) {
				// ok, this class is on the deletion list. What about methods?
				if(ignoreMethods) {
					console.log("(full) Found at " + fullCounter + " " + className);
					// no methods on the list, just remove all occurrences of this class
					found = true;
				} else {
					var methodName = _fullEventData[fullCounter]["method"];
					if(deletionMap[className]["methods"].indexOf(methodName) != -1) {
						// method was found, remove it
						console.log("(full) Found at " + fullCounter + " " + className + "::" + methodName);
						found = true;
					}
				}

				if(found) {
					//console.log("[datasource] Removing ", e.data["options"]["class"], " :: ", e.data["options"]["method"]);
					_fullEventData.splice(fullCounter, 1);
				} else {
					fullCounter++;
				}
			} else {
				fullCounter++;
			}
		}
		_dataSource["data"] = _fullEventData;
		_dataSource["recordsTotal"] = _fullEventData.length;

		if(shouldProcessFilteredResults === true) {
			while(_filteredData[filtCounter] !== undefined) {
				found = false;

				var className = _filteredData[filtCounter]["class"];
				if(deletionMap[className] !== undefined) {
					// ok, this class is on the deletion list. What about methods?
					if(ignoreMethods) {
						//console.log("(filt) Found at " + fullCounter + " " + className);
						found = true;
					} else {
						var methodName = _filteredData[filtCounter]["method"];
						if(deletionMap[className]["methods"].indexOf(methodName) != -1) {
							// method was found, remove it
							//console.log("(filt) Found at " + fullCounter + " " + className + "::" + methodName);
							found = true;
						}
					}

					if(found) {
						//console.log("[datasource] Removing ", e.data["options"]["class"], " :: ", e.data["options"]["method"]);
						_filteredData.splice(filtCounter, 1);
					} else {
						filtCounter++;
					}
				} else {
					filtCounter++;
				}
			}
			_dataSource["data"] = _filteredData;
			//_dataSource["recordsTotal"] = _filteredData.length;
		}
			
		_dataSource["filter"] = "allyourbasearebelongtous"; // force refresh by changing the filter text.
	}

	console.log("posting message finishedRemovingObjcEvents");
    self.postMessage({
    	messageType: "finishedRemovingObjcEvents",
    	operation: e.data["operation"],
    	deletionMap: deletionMap
    });
}

//
// Handle incoming messages from the main iSpy UI thread
//
self.addEventListener('message', function(e) {

	switch(e.data["messageType"]) {

		case "init":

			initializeWorker();
			break;

		case "connect":

			connectWorker();
			break;

		case "batchImport":
			//console.log("[datasource] Batch Import: making AJAX call for event data.");

			self.postMessage({
				messageType: "batch-progress",
				progress: 1,
				text: "Waiting for iSpy, this may take a few seconds... <i class='fa fa-circle-o-notch fa-spin'></i>"
			});

			var params = JSON.stringify({
				messageType: "getNumberOfObjcEvents", 
				messageData: {}
			});

			var responseText = makeRequest("/rpc", params);
			var data = JSON.parse(responseText);

			if(data["JSON"] !== undefined && data["JSON"]["count"] !== undefined) {
				numberOfObjCEvents = data["JSON"]["count"];
				//console.log("[datasource] Number of events: ", numberOfObjCEvents);
			}
			else {
				//console.log("[datasource] Failed to get count of logged events", datums);
				return;
			}
		
			var totalCount = 0;
			while(totalCount < numberOfObjCEvents) {
				params = JSON.stringify({
					messageType: "refreshObjCEvents", 
					messageData: {
						start: totalCount,
						count: 10000
					}
				});

				responseText = makeRequest("/rpc", params);

				var percentComplete = totalCount / numberOfObjCEvents;
				//console.log("[datasource] Percent: ", percentComplete);
				
				var json = JSON.parse(responseText);

				//console.log("[objc] Got AJAX response to request for event log", json);
				if(json["JSON"] === undefined || json["JSON"]["events"] === undefined) {
					console.log("[datasource] ERROR, bad JSON", json);
					return;
				}

				var events = json["JSON"]["events"];
				var count = events.length;
				var percent = 0;

				//console.log("[objc] JSON len: ", events.length);

				for(var i = 0; i< count; i++) {
					try {
						var eventJson = JSON.parse(events[i]);

						handle_objc_event_data(events[i], eventJson);
					} catch(e) {
						console.log("[datasource] ERROR on import @ " + i + " for obj: ", events[i], " with error:", e);
					}
					totalCount++;
				}					

				console.log("[datasource] Imported " + i + " events. " + totalCount + " of " + numberOfObjCEvents + " complete. Sending completion notification");

				self.postMessage({
					messageType: "batch-progress",
					progress: Math.round(percentComplete * 100),
					text: "Loading " + totalCount + " of " + numberOfObjCEvents + " events..."
				});

			}

			self.postMessage({
				messageType: "batch-progress",
				progress: 100,
				text: "Rendering..."
			});

			self.postMessage({
				messageType: "batchImportComplete"
			});

			break;

		case "mustacheTemplates":

			_mustacheTemplates = e.data["templates"];
			break;

		case "setSearchParameters":
			
			_previousSearchParameters = _searchParameters;
			_searchParameters = e.data["searchParameters"];
			console.log("[datasource] Search parameters: ", _searchParameters);
			break;

		case "getEventDetailForRow":

			var row = e.data["row"];
			var index = e.data["index"];
			var operation = e.data["operation"] || "";
			var clearLogs = e.data["clearLogs"] || false;
			var message = (e.data["target"] === undefined) ? "eventDetail" : e.data["target"];
			//console.log("[datasource] [getEventDetail] ", index);
			self.postMessage({
				messageType: message,
				json: _dataSource["data"][index],
				row: row,
				index: index,
				operation: operation,
				clearLogs
			});
			break;

		case "getEventDetailForEventID":

			var eventID = e.data["eventID"] || undefined;
			var callbackName  = e.data["callbackName"] || undefined;
			var message = (e.data["callbackName"] === undefined) ? "eventDataForCurrentRow" : e.data["callbackName"];
			
			console.log("[datasource] [getEventDetailForEventID] eventID = ", eventID, " message  = ", message );
			
			if(eventID === undefined || message === undefined) {
				console.log("[datasource] undefined things. See previous log entry.");
				break;
			}

			var eventData = undefined
			for(var i = 0; i < _fullEventData.length; i++) {
				if(_fullEventData[i]["count"] == eventID) {
					eventData = _fullEventData[i];
					break;
				}
			}
			if(eventData === undefined)
				break;

			/*
			if(eventData["class-list"] === undefined)
				eventData["class-list"] = (eventData["encodedAttributes"].substring(0,2) == "T@,") ? "class-list" : "";
			*/

			var renderedHTML = Handlebars.compile(_mustacheTemplates["auditEventDetail"])(eventData);

			self.postMessage({
				messageType: message,
				json: eventData,
				eventID: eventID,
				renderedHTML: renderedHTML
			});
			
			break;

		case "updateDetailForRow":

			var index = e.data["index"];
			var row = e.data["row"];
			var renderedHTML = Handlebars.compile(_mustacheTemplates["objcEventDetail"])(_dataSource["data"][index]);

			self.postMessage({
				messageType: "newRowHTML",
				html: renderedHTML,
				row: row,
				index: index,
			});
			break;

		case "removeEntriesFromObjCLogForMethods":

			var methods = e.data["methods"] || undefined;
			var className = e.data["class"];
			var searchText = e.data["searchText"] || undefined;
			var ignoreMethods = (e.data["operation"] && e.data["operation"] == "removeClass") ? true : false;
			var dataSource;
			var shouldProcessFilteredResults = (searchText !== undefined && searchText.length > 0) ? true : false;
			var rows = [];
			
			console.log("[datasource] entered removeEntriesFromObjCLogForMethod, search = '", searchText, "',' filtered? ", shouldProcessFilteredResults, ", methods = ", methods, ", class = ", className);
			if(rows === undefined) {
				console.log("[datasource] undefined things. See previous log entry.");
				return;
			}

			if(shouldProcessFilteredResults)
				dataSource = _filteredData;
			else
				dataSource = _fullEventData;

			for(var i = 0; i < dataSource.length; i++) {
				if(dataSource[i]["class"] == className) {
					for(var m = 0; m < methods.length; m++) {
						if(dataSource[i]["method"] == methods[m]) {
							rows.push(i);
							break;
						}	
					}
				}
			}
			e.data["rows"] = rows;
			removeEntriesFromDataSet(e);			

			break;

		case "removeEntriesFromObjCLog":

			removeEntriesFromDataSet(e);
			
			break;

		case "getFreshData":

			// If we've been asked for stats data only (no event data) then we return 
			// immediately with the answer instead of doing an expensive data computation.
			if(e.data["options"] && e.data["options"]["statsOnly"] === true) {
		        self.postMessage({
		        	messageType: "freshData",
		        	data: undefined, // don't send back any data
		        	forceRedraw: false,
		        	recordsTotal: _dataSource["recordsTotal"],
		        	recordsFiltered: _dataSource["recordsFiltered"],
		        	maintainSelectedItems: e.data["options"]["maintainSelectedItems"]
		        });
		        return;
		    }

		    // In general we throttle this function to run at most once per second. 
		    // However, if "forceRedraw" is set then we ignore all throttling and run immediately.
			if(_holdoffLock === true && (e.data["options"] !== undefined && e.data["options"]["forceRedraw"] !== true)) {
				return;
			}

			_holdoffLock = true;

			var savedData = e.data["savedData"];
			var search = e.data["searchParameters"];
			var forceRedraw = (e.data["options"] && e.data["options"]["forceRedraw"] === true) ? true : false;
			var out = [];
			var doSearch = (search["text"].length > 0) ? true : false;

		 	// Handle case sensitivity options
		 	var needle = (_searchParameters["isCaseSensitive"] === true) ? search["text"] : search["text"].toLowerCase();

		 	// Check to see if we're using a filter, and if so whether or not we need to update it.
		 	if(JSON.stringify(_searchParameters) != JSON.stringify(_previousSearchParameters)) {
		 		// we need to refresh the content and apply search filtering
		 		_dataSource["filter"] = needle;

		 		// if we're not applying a filter, use the full data set as our dataSouce
		 		if(needle == "" || needle === undefined) {
		 			//console.log("[datasource] Blank search filter, using all data");
		 			_dataSource["data"] = _fullEventData;
		 		} 
		 		// otherwise we build a filtered dataSource to play with
		 		else {
		 			//console.log("[datasource] Building search filter for: '" + needle + "'");

		 			_filteredData = [];	
		 			var matchedEvents = 0;

		 			for(var i=0; i<_dataSource["recordsTotal"]; i++) {
		 				if(_fullEventData[i] === undefined)
		 					break;
			 			if(jsonMeetsFilterCriteria(_fullEventData[i])) {
			 				_filteredData.push(_fullEventData[i]);
			 				matchedEvents++;
			 			}
			 		}
		 			_dataSource["recordsFiltered"] = matchedEvents;
		 			_dataSource["data"] = _filteredData;
		 			//console.log("[datasource] Finished building data set with " + matchedEvents + " of " + _dataSource["recordsTotal"] + " events");
		 		}
		 	} else {
		 		//console.log("[datasource] Not rebuildng datasource");
		 	}

		 	// If we're not filtering search results, set filtered = total so that the UI reacts properly.
		 	if(needle == "")
		 		_dataSource["recordsFiltered"] = _dataSource["recordsTotal"];

		 	// Now build the dataset to be returned to the caller, taking account of pagination, etc
	        for ( var i=savedData.start; i<savedData.start+1000; i++) {
	        	if(_dataSource["data"][i] === undefined) {
	        		//console.log("[datasource] Ran out of available events at index " + i);
	        		break;
	        	}

				var renderedHTML = Handlebars.compile(_mustacheTemplates["objcEvent"])(_dataSource["data"][i]);
				var lineItem = [ "", _dataSource["data"][i]["count"], renderedHTML ];
	            out.push(lineItem);
	        }
	  
	  		// Send the results back to the UI for rendering
	  		var maintainSelectedItems = (e.data["options"] && e.data["options"]["maintainSelectedItems"]) ? true : false;
	        self.postMessage({
	        	messageType: "freshData",
	        	data: out,
	        	forceRedraw: forceRedraw,
	        	recordsTotal: _dataSource["recordsTotal"],
	        	recordsFiltered: _dataSource["recordsFiltered"],
	        	maintainSelectedItems: maintainSelectedItems
	        });

	        // We'll run at most once every second.
	        setTimeout(function() {
	        	_holdoffLock = false;
	        }, 1000);

	        break;

	    case "setCallWatchList":

	    	console.log("[datasource] setCallWatchList");
	    	var list = e.data["watchList"] || undefined;
	    	if(list.length === undefined || list.length <= 0)
	    		list = undefined;
	    	
	    	_callWatchList = {};

	    	for(var i = 0; i < list.length; i++) {
	    		var className = list[i]["class"];
	    		var selector = list[i]["selector"];

	    		if(_callWatchList[className] === undefined) {
	    			//console.log("[setCallWatchList] _callWatchList[className] = ", _callWatchList[className]);
	    			_callWatchList[className] = {};
	    		}
	    		//console.log("[setCallWatchList] _callWatchList[className] = ", _callWatchList[className]);
	    		_callWatchList[className][selector] = list[i];
	    		//console.log("[setCallWatchList] _callWatchList[className] = ", _callWatchList[className]);
	    		//console.log("[setCallWatchList] _callWatchList[className][selector] = ", _callWatchList[className][selector]);
	    	}

	    	console.log("[datasource] Full _callWatchList: ", _callWatchList);
	    	break;

	    default:
	    	break;
	}
});
