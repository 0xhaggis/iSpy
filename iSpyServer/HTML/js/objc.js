/*
	objc.js
	Capture and display objc_msgSend() events from the iDevice.
*/

$(document).ready( function () {
	
	// Setup call auditing
	var _audit = new Audit();

	// Setup call logging
	objcBrowser();
});

var objcBrowser = objcBrowser || (function () {
	var _refreshNeeded = false;
	var _ajaxRefreshNeeded = true;
    var _savedData = undefined;
    var _savedCallback = undefined;
	var _objcDataTable = undefined;
	var _REFRESH_HOLDOFF_INTERVAL = 1000;
	var _EVENT_DATA_COLUMN = 2;
	var _refreshHoldoff = false;
	var _refreshTimer = false;
	var _latestData = [ "", "", "" ];
	var _recordsFiltered = 0;
	var _internal = undefined;
	var _cachedData = [];
	var _objcSelector = undefined;
	var _oneTimeFlag = false;
	var _prevSearch = undefined;
	var _numLoggedEvents = 0;

	/*
		The locations to which the tab cycler will visit on each (shift)-TAB press.
	*/

	var _objcRegions = [{
		name: "search", 
		element: "#searchBox",
		callback: function () {
			//console.log("[keyboard callback] search");
		}
	}, {
		name: "list",
		element: "#objc-table-outer"
	}];

	// Dispatch message to the datasource requested fresh data
	var requestFreshDataFromFilterWorker = function (options) {

		var message = {
			messageType: "getFreshData",
			searchParameters: search.parameters(),
			savedData: _savedData,
			options: options
		};
		
		__datasourceWorker.postMessage(message);
	}

	function removeSelectedMethodFromWhitelist(clearLogs) {
		removeSelectedMethodFromWhitelist_real(clearLogs, "removeMethod");
	}

	function removeSelectedClassFromWhitelist(clearLogs) {
		removeSelectedMethodFromWhitelist_real(clearLogs, "removeClass");
	}

	function removeSelectedMethodFromWhitelist_real(clearLogs, operation) {
		__pleaseWaitModal(true);
		var index = context.element().currentTarget._DT_RowIndex;
		if(_objcSelector.selectedRows.length <= 0) {
			_objcSelector.selectRow(index);
		}

		var selectedRows = [];
		for(var i = 0; i < _objcSelector.selectedRows.length; i++) {
			var page = _objcDataTable.page.info();
			selectedRows.push(page.start + _objcSelector.selectedRows[i]);
		}

		// once complete, this function will trigger the "finishedRemovingObjcEvents" event.
		__datasourceWorker.postMessage({
			messageType: "removeEntriesFromObjCLog",
			rows: selectedRows,
			searchText: search.text(),
			operation: operation,
			clearLogs: (clearLogs === undefined) ? false : clearLogs
		});
	}

	/*
		Handle incoming message events from the datasource
	*/
	__datasourceRegisterCallback(function (event) {
		if(event === undefined || event.data === undefined || event.data['messageType'] === undefined)
			return;

		switch(event.data["messageType"]) {

			case "batch-progress":
				$("#objc-progress-bar").css("width", "" + event.data["progress"] + "%").attr('aria-valuenow', event.data["progress"]).html(event.data["progress"] + "%");
				if(event.data["text"] !== undefined)
					$("#objc-progress-text").html(event.data["text"]);
				break;

			case "finishedRemovingObjcEvents":

				//console.log("[objc] finishedRemovingObjcEvents: data: ", event.data);
				var operation = event.data["operation"];
				var deletionMap = event.data["deletionMap"];
				var watchlistUpdateData = { "classes": [] };
				var req;
				
				var savedRow = _objcSelector.selectedRows[0];

				requestFreshDataFromFilterWorker({
					forceRedraw: true,
					statsOnly: false,
					maintainSelectedItems: true
				});
				
				if(operation == "removeClass" || operation == "removeMethod") {
					$.each(deletionMap, function (className, val) {
						watchlistUpdateData["classes"].push({
							class: className,
							methods: deletionMap[className]["methods"]
						});
					});
					//console.log("[objc] update data: ", watchlistUpdateData);
					req = JSON.stringify({
						messageType: "removeMethodsFromWhitelist", 
						messageData: watchlistUpdateData
					});
					//console.log("[objc] outbound json: ", req);
					
					$.ajax({
						type: "POST",
						url: "/rpc",
						dataType: "text",
						processData: false,
						data: req,
						success: function () {
							console.log("[objc] refreshing watchlist icons");
							classBrowser.refreshWhitelistIcons();
							classBrowser.classDumper().refreshMethodListTable();
							_objcSelector.deselectAllRows();
							_objcSelector.selectRow(savedRow);
							__pleaseWaitModal(false);
						} 
					});
				}
 
				break;

			case "newData":

				var forceRedraw = (event.data["forceRedraw"] === undefined) ? false : event.data["forceRedraw"];
				var page = _objcDataTable.page.info();

				requestFreshDataFromFilterWorker({
					forceRedraw: forceRedraw,
					statsOnly: (page.end - page.start < page.length) ? false : true,
					maintainSelectedItems: event.data["maintainSelectedItems"]
				});
 
				break;

			case "freshData":

				var d = event.data;
				var proxyDraw = function () {};
				var page = _objcDataTable.page.info();
				var dataObj;

				// Don't redraw the table if we don't have to. It's an expensive operation.
				if(((d["forceRedraw"] === true) || ((page.end - page.start) < page.length))) {
					proxyDraw = _savedData.draw;
				}

				// if no data was passed (speed optimization) then used cached data 
				if(d["data"] !== undefined) {
					_cachedData = d["data"];
				} 
				dataObj = _cachedData;

				_savedCallback({
					data: dataObj,
					draw: proxyDraw,
					recordsTotal: d["recordsTotal"],
		            recordsFiltered: d["recordsFiltered"]
				});

				if(d["maintainSelectedItems"] === true)
					_objcSelector.highlightSelectedRows();	

				break;

			case "newRowHTML":

				var html = event.data["html"];
				$("#callDataSection").html(html);

				break;

			case "eventDetail":

				var json = event.data["json"];
				//console.log("[objc] [eventDetail] Got JSON: ", json);
				break;

			case "batchImportComplete":
				console.log("[objc] Batch import complete, connecting the datasource to websocket");
				__datasourceWorker.postMessage({
					messageType: "connect"
				});

			break;

			default:
				break;
		} // switch
	}); 


	/*
		Initialize all the things once Mustache becomes active.
	*/

	$(document).on("mustacheReady", function () {
		console.log("[objc] Initializing.");

		// The main DataTable holds a fast, responsive UI for browsing objc_msgSend events.
		_objcDataTable = $('#objcTable').DataTable({
			select: true,
			bootstrap: true,
			serverSide: true,
			scrollY: "85vh",
			displayBuffer: 20,
			paging: true,
			bAutoWidth: false,
			lengthMenu: [ 1000 ],
			ajax: function ( data, callback, settings ) {
	            _savedData = data;
	            _savedCallback = callback;

	            requestFreshDataFromFilterWorker({
	            	"forceRedraw": true
	            });
	        },
			deferRender: true,
			columns: [
				{ "width":"1vw" },	// id
				{ "width":"4vw" },	// id
				{ "width":"95vw" }	// call parameters
			]
		});

		// Hook into the guts of the DataTables private oApi
		$.fn.dataTableExt.oApi.internalRef = function (settings) {
			return settings; 
		};
		_internal = $("#objcTable").dataTable().internalRef();

		// Attach callback function to the "click" event on a table row.
		// Used to handle user interacation with table.
		// also attach double click handler to display the class name on double click.
		_objcSelector = new TableSelect({
			//view: "objc",
			selector: "#objcTable",
			onSingleSelect: function (objSelf) {
				var page = _objcDataTable.page.info();
				var rowObj = _objcDataTable.row(objSelf.lastSelectedRow);
				var data = rowObj.data();
				var eventIndex = page.start + rowObj.index();

				__datasourceWorker.postMessage({
					messageType: "updateDetailForRow",
					index: eventIndex,
					row: rowObj.index()
				});
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

		console.log("[objc] Running batch import");

		__datasourceWorker.postMessage({
			messageType: "batchImport"
		});

		// Hide some of the unused DataTables UI stuff, like column names, search, etc
		$(".dataTables_scrollHead").addClass("collapse hidden");
		$("#objcTable_wrapper div").first().addClass("collapse hidden");

		console.log("[objc] Finished initializing.");
	});

	function getClassNameFromCurrentRow() {
		var page = _objcDataTable.page.info();
		var rowObj = _objcDataTable.row(_objcSelector.lastSelectedRow);
		var data = rowObj.data();
		var offs = data[2].indexOf("data-className");
		
		if(offs == -1)
			return null;
		
		var className = data[2].substring(offs + 22);
		offs = className.indexOf('"');
		
		if(offs == -1)
			return null;

		return className.substring(0, offs);
	}

	// this is called any time enter is pressed or an option is twiddled
	function doSearchChanged() {
		//console.log("[objc] Caught searchChanged");
		_prevSearch = search.text();

		__datasourceWorker.postMessage({
			messageType: "setSearchParameters",
			searchParameters: search.parameters()
		});

		requestFreshDataFromFilterWorker();

		var oTable = $('#objcTable').dataTable();
  		oTable.fnPageChange('first');

  		_objcSelector.deselectAllRows();
  		_objcSelector.selectRow(0);		
	}

	// Triggered whenever the user changes tool view. Handle stuff here :)
	$(document).on("toolChanged", function(event, newTool) {
		if(newTool == "objc") {
			$("#searchButtonDiv button").each(function () {
				$(this).removeClass("disabled");
			});
			$("#btnProperty").addClass("disabled");
			$("#btnIVar").addClass("disabled");
			
			console.log("[objc] Switched to the objc panel");
			if(_prevSearch != search.text())
				doSearchChanged();
		}
	});

	// Could be the user pressed enter in the search box... 
	$(document).on("searchChanged", function() {
		doSearchChanged();
	});
	// ...or maybe one of the search option buttons was toggled
	$(document).on("searchOptionsChanged", function() {
		doSearchChanged();
	});

	// Setup the context menu
	var objcContextMenu = [{
		text: 'Remove method <span id="objcSpanMethodRemove"></span> from watchlist',
		action: function(e, data){
			removeSelectedMethodFromWhitelist();
			e.preventDefault();
		}
	}, {
		text: 'Remove method <span id="objcSpanMethodRemoveAndClear"></span> from watchlist and clear from log',
		action: function(e){
			removeSelectedMethodFromWhitelist(true); // pass "true" to make it erase all of selected classes from the logs
			e.preventDefault();
		}
	}, {
		text: 'Remove class <span id="objcSpanMethodRemove"></span> from watchlist',
		action: function(e){
			removeSelectedClassFromWhitelist();
			e.preventDefault();
		}
	}, {
		text: 'Remove class <span id="objcSpanClassRemoveAndClear"></span> from watchlist and clear from log',
		action: function(e){
			removeSelectedClassFromWhitelist(true); // pass "true" to make it erase all of selected classes from the logs
			e.preventDefault();
		}
	}];

	// Attach the context menu to a right-click event handler
	context.attach("#objcTable tr", objcContextMenu);

	// Make sure to handle nice keyboard navigation on the list of events
	$(document).on("KEYDOWN", function () {
		if(__currentView == "objc") {
			keyboard.moveFocusToRegion("list");
			_objcSelector.nextRow();
		}
	});

	$(document).on("KEYUP", function () {
		if(__currentView == "objc") {
			keyboard.moveFocusToRegion("list");
			_objcSelector.prevRow();
		}
	});

	$(document).on("KEYPGDOWN", function () {
		if(__currentView == "objc") {
			keyboard.moveFocusToRegion("list");
			_objcSelector.nextRow(10);
		}
	});

	$(document).on("KEYPGUP", function () {
		if(__currentView == "objc") {
			keyboard.moveFocusToRegion("list");
			_objcSelector.prevRow(10);
		}
	});

	// Configure TAB navigation
	keyboard.registerForTabKey({
		regions: _objcRegions		
	});

	// any time the list of objc events is redrawn we need to make sure to (re)select the correct item in the list
    $("#objcTable").on("draw.dt", function () {
		if(_objcDataTable.page.info().end === 0)
			return;

		if(_objcSelector.lastSelectedRow === undefined)
			_objcSelector.selectRow(0);
		else
			_objcSelector.selectRow(_objcSelector.lastSelectedRow);
		
		_objcSelector.onSingleSelectCallback(_objcSelector);
    });
});
