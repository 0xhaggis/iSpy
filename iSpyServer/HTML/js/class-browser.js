/*
	class-browser.js
	Browse the classes and protocols of the target app.
*/

var classBrowser = classBrowser || (function () {
	var _classListDataTable = undefined;
	var _methodListDataTable = undefined;
	var _savedData = undefined;
	var _savedCallback = undefined;
	var _classList = undefined;
	var _currentlyDisplayedClass = undefined;
	var _classList = []; // this is the _filtered_ class list 
	var _refreshHoldoff = false;
	var _needRefresh = false;
	var _watchlistUpdateData = undefined;
	var _classSelector = undefined;
	var _methodSelector = undefined;
	var _isFirstRun = true;
	var _classDumper = undefined;
	var _lastIconUpdate = 0;

	var _classDumpRegions = [{
		name: "search", 
		element: "#searchBox",
		callback: function () {
			//console.log("[keyboard callback] class search");
		}
	}, {
		name: "list",
		element: "#class-dump-outer",
		callback: function () {
			//console.log("[keyboard callback] class list");
		}
	}];

	keyboard.registerForTabKey({
		view: "class",
		regions: _classDumpRegions		
	});

	/*
		Helper functions
	*/

	function replaceIcon(icon, cssTag) {
		// XXX TODO make regex
		icon = icon.replace("glyphicon-eye-open watchlist-not-available", "glyphicon-eye-open " + cssTag);
		icon = icon.replace("glyphicon-eye-open watchlist-disabled", "glyphicon-eye-open " + cssTag);
		icon = icon.replace("glyphicon-eye-open watchlist-enabled", "glyphicon-eye-open " + cssTag);
		icon = icon.replace("glyphicon-eye-open watchlist-partial", "glyphicon-eye-open " + cssTag);
		return icon;
	}

	function updateIconCSS(wlClass, className, icon) {
		if(__iSpyClassList[className]["methods"].length <= 0) {
			icon = replaceIcon(icon, "watchlist-not-available");
		} else if( (wlClass == undefined) || (wlClass && wlClass["methodCountForWhitelist"] == 0) ) {
			icon = replaceIcon(icon, "watchlist-disabled");
		} else if(wlClass["methodCountForWhitelist"] < __iSpyClassList[className]["methods"].length) {
			icon = replaceIcon(icon, "watchlist-partial");
		} else if(wlClass["methodCountForWhitelist"] == __iSpyClassList[className]["methods"].length) {
			icon = replaceIcon(icon, "watchlist-enabled");
		}
		return icon;
	}

	function refreshWhitelistIconForClass(className) {
		var found = false, end = false;
		var rowNum = 0;

		while(!found && !end) {
			var d = _classListDataTable.row(rowNum).data();
			if(!d) {
				end = true;
				break;
			}

			var rowClassName = d[1];
			if(rowClassName == className) {
				var wl = watchlist.watchlist();
				if(!wl)
					return;

				var wlClass = wl[className];
				var icon = d[0];

				console.log("[refreshWhitelistIconForClass] wlClass: ", wlClass);

				d[0] = updateIconCSS(wlClass, className, icon); // d[0] contains the icon's HTML

				_classListDataTable.row(rowNum).data(d).draw();
				found = true;
				break;
			}
			rowNum++;
		}
	}

	function refreshWhitelistIcons() {
		var wl = watchlist.watchlist();
		console.log("[refreshWhitelistIcons]");

		_classListDataTable.rows().every(function () {
			var d = this.data();
			var className = d[1];
			var icon = d[0];
			var wlClass = wl[className];

			d[0] = updateIconCSS(wlClass, className, icon); // d[0] contains the icon's HTML

			this.data(d);
			this.invalidate();
		});

		_classListDataTable.draw();
		_classSelector.highlightSelectedRows();
	}

	function getWhitelistUpdateData() {
		// build list of classes / methods
		var len = _classSelector.count();
		var i;
		var requests = [];
		var watchlistUpdateData = {};
		watchlistUpdateData["classes"] = [];

		for(i = 0; i < len; i++) {
			watchlistUpdateData["classes"].push({
				"class": _classList[_classSelector.selectedRows[i]],
				"methods": []
			});
		}

		return watchlistUpdateData;
	}

	// This uses cascading promises to synchronize multiple nested ajax requests.
	function addSelectedClassesToWhitelist() {
		//__pleaseWaitModal(ON);

		var entries = getWhitelistUpdateData();

		$.when(watchlist.addEntries(entries)).done(function () {
			$.when(watchlist.refresh()).done(function () {
				//refreshWhitelistIcons();
			});
		});
	}

	// This uses cascading promises to synchronize multiple nested ajax requests.
	function removeSelectedClassesFromWhitelist(clearLogs) {	
		//__pleaseWaitModal(ON);
		
		// build list of classes / methods
		var entries = getWhitelistUpdateData();
		console.log("[remove] removign entries: ", entries);

		// send to idevice to be removed from watchlist
		$.when(watchlist.removeEntries(entries)).done(function () {
			// get new watchlist from device
			$.when(watchlist.refresh()).done(function () {
				// update UI	
				if(clearLogs) {
					var message = {
						messageType: "removeEntriesFromObjCLog",
						searchText: search.text(),
						rows: func_classSelector.selectedRows,
						operation: "removeClass",
						clearLogs: clearLogs
					};
					__datasourceWorker.postMessage(message);
				}
				//console.log("[removeEntries] entries: ", entries);
				$.each(entries, function(className, classData) {
					refreshWhitelistIconForClass(className);
				});
			});
		});	
	}

	function updateUI() {
		var HTML = Handlebars.compile(__mustacheTemplates["please-wait-body-ok"])({});
		$("#please-wait-body").html(HTML);
		$("#classListTable").DataTable().ajax.reload();
		$(document).on('classBrowserNeedsUIRefresh', function () {
			$(document).off('classBrowserNeedsUIRefresh');
			//console.log("[classdump] Rendering with: ", _classSelector);
			
			//if(_classSelector.lastSelectedRow === undefined || _classSelector.selectedRows.length <= 0)
				_classSelector.deselectAllRows();
				_classSelector.selectRow(0);
			/*
			var savedSelectedRows = _classSelector.selectedRows;
			var savedLastSelectedRow = _classSelector.lastSelectedRow;

		    //setTimeout(function () {
				var HTML = Handlebars.compile(__mustacheTemplates["please-wait-body-working"])({});
				//console.log("[classdump] Refreshing the list and reselecting: ", _classSelector);

				_classSelector.deselectAllRows();
				_classSelector.selectedRows = savedSelectedRows;
		    	_classSelector.lastSelectedRow = savedLastSelectedRow;

				for(var i = 0; i < _classSelector.count(); i++) {
					$("#classListTable").DataTable().row(_classSelector.selectedRows[i]).nodes().to$().addClass("active");
				}
				
				$("#classListTable").DataTable().rows(_classSelector.selectedRows).select();
				*/
				_classDumper.renderClass({
					className: _classList[_classSelector.selectedRows[0]],
					callback: renderCallback
				});
				
				//$("#please-wait-body").html(HTML);
			//}, 750);
			
			handleSearchChange();
			__pleaseWaitModal(false);
		});
	}

	// XXX FIX ME was written drunk. Nested setTimeouts = hard to debug.
	function handleSearchChange() {
		//console.log("[ClassDump] Caught searchAsYouTypeChanged, rebuilding class list");
		// refresh at most once every 1/4 second
		//console.log("[handleSearchChange] _needRefresh = " + _needRefresh + ", _refreshHoldoff = " + _refreshHoldoff);
		_needRefresh = true;
		if(!_refreshHoldoff) {
			_refreshHoldoff = true;
			_needRefresh = false;
			setTimeout(function () {
				if(_needRefresh) {
					_needRefresh = false;
					_refreshHoldoff = true;
					$("#classListTable").DataTable().ajax.reload();
					setTimeout(function () {
						_refreshHoldoff = false;
						handleSearchChange();
					}, 333);
				} else {
					_needRefresh = false;
					_refreshHoldoff = false;
					_classSelector.deselectAllRows();
					_classSelector.selectRow(0);
					_classDumper.renderClass({
						className: _classList[_classSelector.selectedRows[0]],
						callback: renderCallback
					});
				}
			}, 250);
			//$("#classDumpSection").addClass("dimmed");
			$("#classListTable").DataTable().ajax.reload();
		} 
	}


	function renderCallback(options) {
		//console.log("[ClassDump renderCallback] Options: ", options, " This ", this)
	
		if(options && options["className"])
			_currentlyDisplayedClass = options["className"];
		$("#classDumpSection").removeClass("dimmed");
		$("#classDumpSection").removeClass("hidden");
	}

	function iconHoldoff() {
		var d = new Date();
		var t = d.getTime();

		if(t > _lastIconUpdate) {
			refreshWhitelistIcons();
			_lastIconUpdate = t;
			_classDumper.refreshMethodListTable();
		} else {
			setTimeout(iconHoldoff, 500);
		}
	}

	/*
		This is our main entry point, triggered by Moustache successfully initializing.
	*/

	$(document).on("mustacheReady", function () {
		console.log("[ClassDump] Initializing.");

		/*
			Handle row selection for the class list DataTable
		*/
		_classSelector = new TableSelect({
			view: "class",
			selector: "#classListTable",
			onSingleSelect: function (selSelf) {
				//console.log("single click callback: ", selSelf);
				_classDumper.renderClass({
					className: _classList[selSelf.lastSelectedRow],
					callback: renderCallback
				});
			},
			onMultiSelect: function (selSelf) {
				if(selSelf.count() > 1)
    				$("#classDumpSection").addClass("dimmed");
			},
			onChange: function (selSelf) {
				var len = selSelf.count();
				var classStr = "" + len;
				classStr += ((len > 1)?" classes":" class");
				$("#spanClassAdd").html(classStr);
				$("#spanClassRemove").html(classStr);
				$("#spanClassRemoveAndClear").html(classStr);
			}
		});


		/*
			Use the ClassDumper class to attach the class dump rendered to a DOM element
		*/
		_classDumper = new ClassDumper({
			DOMElement: "#classDumpSection"
		});


		/*
			Handle row selection for the method list DataTable
		*/
		_methodSelector = new TableSelect({
			selector: "#methodListTable",
			onSingleSelect: function () {},
			onShiftSelect: function () {},
			onMetaSelect: function () {},
			onChange: function () {}
		});


		/*
			Create the class list DataTable
		*/
		$.ajax({
			type: "POST",
			url: "/rpc",
			dataType: "text",
			processData: false,
			data: '{"messageType":"classDump","messageData":{}}',
			success: function(json) {
				json = JSON.parse(json)["JSON"]["classes"];
				__iSpyClassList = json;
			}
		}).done(function () {
			_classListDataTable = $('#classListTable').DataTable({		
				dom: "t",
				select: {
					style: "os"
				},
				bootstrap: true,
				//serverSide: true,
				paging: false,
				info: false,
				bAutoWidth: true,
				ajax: function (data, callback, settings) {
					_classList = [];
					var theData = [];
					$.each(__iSpyClassList, function(className, classData) {
						// If there's nothing in the search box, do no searching.
						if(search.text().length <= 0) {
							_classList.push(className);
						}
						else {
							// Classes
							if(search.isClass()) {
								if(search.isMatch(className)) {
									_classList.push(className);
									return;
								}	
							}
							
							// Properties
							if(search.isProperty()) {
								for(var i = 0; i< classData["properties"].length; i++) {
									var propertyName = classData["properties"][i];
									if(search.isMatch(propertyName)) {
										_classList.push(className);
										return;
									}
								}
							}

							// ivars
							if(search.isIVar()) {
								for(var i = 0; i< classData["ivars"].length; i++) {
									var iVarName = classData["ivars"][i];
									if(search.isMatch(iVarName)) {
										_classList.push(className);
										return;
									}
								}
							}

							// methods
							if(search.isMethod()) {
								for(var i = 0; i< classData["methods"].length; i++) {
									var methodName = classData["methods"][i];
									if(search.isMatch(methodName)) {
										_classList.push(className);
										return;
									}
								}
							}
						}
					});

					_classList.sort(); // TBD this needs to be optimized away

					for(var i = 0; i < _classList.length; i++) {
						var className = _classList[i];
						var statusHTML = '<span class="glyphicon glyphicon-eye-open watchlist-disabled"></span>';
						var wl = watchlist.watchlist();
						var wlClass = wl[className];

						statusHTML = updateIconCSS(wlClass, className, statusHTML);
						/*if(__iSpyClassList[className]["methodCountForClass"] == 0) {
							statusHTML += 'watchlist-not-available"></span>';
						} else if( (wlClass === undefined) || ((wlClass["methodCountForWhitelist"] == 0) && (wlClass["methodCountForClass"] > 0))) {
							statusHTML += 'watchlist-disabled"></span>';
						} else if(wlClass["methodCountForClass"] == wlClass["methodCountForWhitelist"]) {
							statusHTML += 'watchlist-enabled"></span>';
						} else {
							statusHTML += 'watchlist-partial"></span>';
						}
						*/
						theData.push([statusHTML, className]);
					}

					//console.log("[callback] data:", theData);
					callback({
						data: theData,
						draw: data.draw
					});
					$(document).trigger("classBrowserNeedsUIRefresh");
		        },
				deferRender: true
			});
			
			updateUI();
			_classSelector.selectRow(0);
			handleSearchChange();
			__pleaseWaitModal(false);
		});

		console.log("[classdump] table: _classListDataTable", _classListDataTable);

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

		context.attach("#classListTable tr", watchlistContextMenu);

		/*
			Setup the search feature
		*/
		// triggered when typing in the search box
		$(document).on("searchAsYouTypeChanged", function() {
			handleSearchChange();
		});

		// triggered by hitting enter in the search box
		$(document).on("searchChanged", function() {
			handleSearchChange();
		});

		// triggered by changing one of the search option buttons
		$(document).on("searchOptionsChanged", function() {
			handleSearchChange();
		});

		/*
			If we want to do something when the user changes view/tool, then we need to catch "toolChanged".
		*/
		$(document).on("toolChanged", function(event, newTool) {
			if(newTool == "class") {
				$("#searchButtonDiv button").each(function () {
					$(this).removeClass("disabled");
				});
				$("#btnData").addClass("disabled");
				//$("#classListTable").DataTable().rows(_classSelector.selectedRows).nodes().to$().addClass("active");
				//$("#classListTable").DataTable().rows(_classSelector.selectedRows).select();
				if(_classSelector.count() == 1)
					$("#classDumpSection").removeClass("dimmed");

				keyboard.moveFocusToRegion("list");

				/*
				$("#navbar-menu-placeholder").append($(_newNavBarEntriesHTML));
				$("#navbar-menu-placeholder ul li").on("click", function() {
					var item = $(this).first().children()[0];
					var choice = $(item).data("menu-item");
					
					if(choice === undefined)
						return;

					//console.log("You chose: '" + choice + "' ", _keychainItems[choice]);
					updateUIForKeychainItem(choice);
				});
		*/
			}
		});


		/*
			Disable the D ("data") button on the toolbar because it's not appropriate to class browsing (default view)
		*/
		$("#btnData").addClass("disabled");

		var that = this;
	    __datasourceRegisterCallback(function(event) {
	        if(event === undefined || event.data === undefined || event.data['messageType'] === undefined)
	            return;

	        switch(event.data["messageType"]) {

	            case "watchlistChanged":
	            	console.log("[WL] event.data = ", event.data);
	            	var classes = event.data["messageData"]["classes"];
	            	console.log("[watchlist callback] Refreshing icons due to messageType: " + event.data["messageType"]);

	            	var d = new Date();
	            	var t = d.getTime();
	            	_lastIconUpdate = t;

	            	setTimeout(iconHoldoff, 500);
	            	
	            	break;

	            default:
	            	console.log("datasourceCallback: Received unknown message: " + event.data["messageType"]);
	        }
	    }); 


	   	$(document).on("updateUI", function () {
	   		updateUI();
	   	});
		
		/*
			So long and thanks for all the fish.
		*/
		console.log("[ClassDump] Finished initializing.");
	});

	function classDumper() {
		return _classDumper;
	}

	return {
		refreshWhitelistIcons: refreshWhitelistIcons,
		refreshWhitelistIconForClass: refreshWhitelistIconForClass,
		classDumper: classDumper
	};
})();
