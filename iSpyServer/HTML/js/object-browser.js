/*
	object-browser.js
	Browse instantiated objects in the target app.
*/

$(document).ready( function () {
	var _objectListDataTable = undefined;
	var _methodListDataTable = undefined;
	var _instanceListDataTable = undefined;
	var _savedData = undefined;
	var _savedCallback = undefined;
	var _methodData = [];
	var _currentlyDisplayedObject = undefined;
	var _objectList = {};
	var _refreshHoldoff = false;
	var _needRefresh = false;
	var _watchlistUpdateData = undefined;
	var _objectSelector = undefined;
	var _methodSelector = undefined;
	var _instanceSelector = undefined;
	var _isFirstRun = true;
	var _classDumper = undefined;

	var _objectInstanceRegions = [{
		name: "search", 
		element: "#searchBox",
		callback: function () {
			console.log("[keyboard callback] object search");
		}
	}, {
		name: "classList",
		element: "#object-classes-outer",
		callback: function () {
			console.log("[keyboard callback] object list");
		}
	}, {
		name: "instanceList",
		element: "#object-instances-outer",
		callback: function () {
			console.log("[keyboard callback] object list");
		}
	}, {
		name: "details",
		element: "#object-details-outer",
		callback: function () {
			console.log("[keyboard callback] object list");
		}
	}];

	keyboard.registerForTabKey({
		view: "object",
		regions: _objectInstanceRegions		
	});

	/*
		Helper functions
	*/

	function getWhitelistUpdateData() {
		// build list of classes / methods
		var len = _objectSelector.count();
		var i;
		var requests = [];
		var watchlistUpdateData = {};
		watchlistUpdateData["classes"] = [];

		for(i = 0; i < len; i++) {
			watchlistUpdateData["classes"].push({
				"class": _objectList[_objectSelector.selectedRows[i]],
				"methods": []
			});
		}

		return watchlistUpdateData;
	}

	function handleSearchChange() {
		console.log("[ObjectDump] Caught searchAsYouTypeChanged, rebuilding class list");
		// refresh at most once every 1/4 second
		if(!_refreshHoldoff) {
			_refreshHoldoff = true;
			_needRefresh = false;
			setTimeout(function () {
				_refreshHoldoff = false;
			}, 250);
			//$("#objectDumpSection").addClass("dimmed");
			console.log("[ObjectDump] refreshing...");
			$("#objectListTable").DataTable().ajax.reload();
		} 

		// don't drop the ball
		if(_refreshHoldoff && _needRefresh) {
			setTimeout(function () {
				$(document).trigger("searchAsYouTypeChanged");
			}, 100);
		}
	}


	function renderCallback(options) {
		//console.log("[ObjectDump renderCallback] Options: ", options, " This ", this)
	
		if(options && options["className"])
			_currentlyDisplayedObject = options["className"];
		$("#objectDumpSection").removeClass("dimmed");
		$("#objectDumpSection").removeClass("hidden");
	}

	function getSortedObject(object) {
		var sortedObject = {};

		var keys = Object.keys(object);
		keys.sort();

		for (var i = 0, size = keys.length; i < size; i++) {
			key = keys[i];
			value = object[key];
			sortedObject[key] = value;
		}

		return sortedObject;
	}

	function getClassNameFromCurrentRow() {
		var rowObj = _objectListDataTable.row(_objectSelector.lastSelectedRow);
		var data = rowObj.data();
		return data[1].replace(/&nbsp;/g, " "); // class name
	}

	function getInstanceAddressFromCurrentRow() {
		var rowObj = _instanceListDataTable.row(_instanceSelector.lastSelectedRow);
		var data = rowObj.data();
		return data[0]; // class name
	}


	/*
		This is our main entry point, triggered by Moustache successfully initializing.
	*/


	$(document).on("mustacheReady", function () {
		console.log("[ObjectDump] Initializing.");

		/*
			Handle row selection for the class list DataTable
		*/
		_objectSelector = new TableSelect({
			selector: "#objectListTable",
			onSingleSelect: function (selSelf) {
				var className = getClassNameFromCurrentRow();
				_instanceListDataTable.clear();
				//console.log("[ObjectDumper] Getting instances for " + className + " (" + _objectList[className].length + ")");

				for(var i = 0; i< _objectList[className].length; i++) {
					//console.log("[ObjectDumper] Adding ",_objectList[className][i]);
					_instanceListDataTable.row.add([_objectList[className][i]]).draw();
				}

				_instanceSelector.selectRow(0);
				_instanceSelector.onSingleSelectCallback();
			},
			onMultiSelect: function (selSelf) {
				if(selSelf.count() > 1)
    				$("#object-details-outer").addClass("dimmed");
			},
			onChange: function (selSelf) {
				var len = selSelf.count();
				var classStr = "" + len;
				classStr += ((len > 1)?" classes":" class");
				$("#spanClassAdd").html(classStr);
				$("#spanClassRemove").html(classStr);
				$("#spanClassRemoveAndClear").html(classStr);
			},
			onDblClick: function (objSelf) {
				var className = getClassNameFromCurrentRow();
				if(className == null)
					return;

				__classDumpPopup.renderClass({
					className: className,
					callback: function (objSelf) {
						$(objSelf.DOMElement).removeClass("hidden");
						$("#class-dump-popup-modal").modal('show');
					}
				});

			}
		});

		_instanceSelector = new TableSelect({
			selector: "#objectInstanceListTable",
			onSingleSelect: function (selSelf) {
				var objectAddress = getInstanceAddressFromCurrentRow();
				//console.log("[ObjectDumper] Selected address " + objectAddress);
				
				$.ajax({
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
						$("#object-details-outer").html(renderedHTML);
					}
				});
			},
			onMultiSelect: function (selSelf) {

			},
			onChange: function (selSelf) {

			}
		});

		/*
			Create the class list DataTable
		*/
		_objectListDataTable = $('#objectListTable').DataTable({
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
			ajax: {
				url: "/rpc",
				type: "POST",
				data: function () {
						return('{ "messageType": "instancesOfAppClasses", "messageData": { } }');
				},
				dataSrc: function(json) {
					console.log("[ObjectDumper] JSON: ", json);

					json = json["JSON"]["classInstances"]; // array of instances
					
					var theData = [];
					var found;
					_objectList = {};

					// first find all of the objects that match current search criteria
					for(var i = 0; i < json.length; i++) {
						//found = false;
						var className = json[i]["class"];
						var objectAddress = json[i]["address"];

						if(_objectList[className] === undefined)
							_objectList[className] = [];

						if(search.text().length <= 0) {
							_objectList[className].push(objectAddress);
						}
						else {
							// Classes
							if(search.isClass()) {
								if(search.isMatch(className)) {
									_objectList[className].push(objectAddress);
									continue;
								}	
							}
							
							/*if(search.isClass()) {
								if(search.isMatch(className)) {
									_objectList[className].push(objectAddress);
									continue;
								}	
							}*/

							if(!found && search.isMatch(objectAddress)) {
								_objectList[className].push(objectAddress);
								continue;
							}							
						}
					}

					// now sort the objects and render them for the UI
					$.each(getSortedObject(_objectList), function(k, v) {
						if(_objectList[k].length <= 0)
							return;

						theData.push([ 
							'<span class="badge">' + _objectList[k].length + '</span>',
							k.replace(/ /g, "&nbsp;") 
						]);
					});

					return theData;
				},
				complete: function () {
					_objectSelector.deselectAllRows();

					//console.log("[classdump] AJAX complete. isFirstRun: ", _isFirstRun, " _objectList.length: ", _objectList.length, " _objectList: ", _objectList, " _objectSelector.lastSelectedRow: ", _objectSelector.lastSelectedRow);
					if(_isFirstRun && _objectList.length > 0) {
						//console.log("[classdump] First run");
						_objectSelector.removeClass("	dimmed");
						_isFirstRun = false;
						/*_classDumper.renderClass({
							className: _objectList[0],
							callback: renderCallback
						});*/
						_objectSelector.selectRow(0);
						__pleaseWaitModal(false);
					} 
					// If nothing is selected then select the first class in the list
					else if(_objectSelector.count() == 0 && _objectList.length > 0) {
						//console.log("[classdump] Selecting first row.");
						$("#objectDumpSection").removeClass("dimmed");
						/*_classDumper.renderClass({
							className: _objectList[0],
							callback: renderCallback
						});*/
						_objectSelector.selectRow(0);
					}
					// There's nothing to select, so we dim the class dump pane
					else {//} if(_objectSelector.count() == 0 && _objectList.length < 0) {
						//$("#object-details-outer").addClass("dimmed");
					}
					//console.log("[classdump] AJAX Done.");
				}
	        },
			deferRender: true
		});

		$("#objectListTable").on("click", function () {
			keyboard.moveFocusToRegion("classList");
		});


		/*
			Create the class list DataTable
		*/
		_instanceListDataTable = $('#objectInstanceListTable').DataTable({
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
		
		$("#objectInstanceListTable").on("click", function () {
			keyboard.moveFocusToRegion("instanceList");
		});


		/*
			Setup the context menus
		*/
		var watchlistContextMenu = [{
			text: 'Add <span id="spanClassAdd"></span> to watchlist',
			action: function(e){
				addSelectedClassesToWhitelist();
				e.preventDefault();
			}
		}, {
			text: 'Remove <span id="spanClassRemove"></span> from watchlist',
			action: function(e){
				removeSelectedClassesFromWhitelist();
				e.preventDefault();
			}
		}, {
			text: 'Remove <span id="spanClassRemoveAndClear"></span> from watchlist and clear from log',
			action: function(e){
				removeSelectedClassesFromWhitelist(true); // pass "true" to make it erase all of selected classes from the logs
				e.preventDefault();
			}
		}];

		context.attach("#objectListTable tr", watchlistContextMenu);

		/*
			Setup the search feature
		*/
		$(document).on("searchAsYouTypeChanged", function() {
			handleSearchChange();
		});
		$(document).on("searchOptionsChanged", function() {
			handleSearchChange();
		});

		__datasourceRegisterCallback(function (event) {
			if(event === undefined || event.data === undefined || event.data['messageType'] === undefined)
				return;

			switch(event.data["messageType"]) {

				case "addObjectDispatch":
					//console.log("[ObjectDumper] Adding object: ", event.data);
					break;

				case "removeObjectDispatch":
					//console.log("[ObjectDumper] Removing object: ", event.data);
					break;
			}
		});

		/*
			If we want to do something when the user changes view/tool, then we need to catch "toolChanged".
		*/
		$(document).on("toolChanged", function(event, newTool) {
			if(newTool == "object") {
				$("#searchButtonDiv button").each(function () {
					$(this).removeClass("disabled");
				});

				if(_objectSelector.count() == 1)
					$("#objectDumpSection").removeClass("dimmed");
			}
		});

		$(document).on("KEYDOWN", function () {
			if(__currentView == "object") {
				var region = keyboard.currentRegion();
				if(region == "instanceList" || region == "details") {
					_instanceSelector.nextRow();
				} else {
					_objectSelector.nextRow();
				}
			}
		});
		$(document).on("KEYUP", function () {
			if(__currentView == "object") {
				var region = keyboard.currentRegion();
				if(region == "instanceList" || region == "details") {
					_instanceSelector.prevRow();
				} else {
					_objectSelector.prevRow();
				}
			}
		});
		$(document).on("KEYPGDOWN", function () {
			if(__currentView == "object") {
				var region = keyboard.currentRegion();
				if(region == "instanceList" || region == "details") {
					_instanceSelector.nextRow(10);
				} else {
					_objectSelector.nextRow(10);
				}
			}
		});
		$(document).on("KEYPGUP", function () {
			if(__currentView == "object") {
				var region = keyboard.currentRegion();
				if(region == "instanceList" || region == "details") {
					_instanceSelector.prevRow(10);
				} else {
					_objectSelector.prevRow(10);
				}
			}
		});

		$(document).on("toolChanged", function(event, newTool) {
			if(newTool == "object") {
				keyboard.moveFocusToRegion("classList");
				_objectSelector.selectRow(0);
			}
		});

		/*
			So long and thanks for all the fish.
		*/
		console.log("[ObjectDump] Finished initializing.");
	});
});
