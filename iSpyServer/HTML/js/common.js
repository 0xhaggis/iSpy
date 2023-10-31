// Global variable to store the Mustache HTML templates.
// This is visible to everything except the data source Web Worker.
var __mustacheTemplates = {};

// Global variable to store the data source Web Worker object.
var __datasourceWorker = undefined;

// Maintain a globally accessible class list
var __iSpyClassList = {};

var __classDumpPopup = undefined;

var __viewPanels = [ "info", "class", "objc", "keychain", "object", "cycript", "log", "audit" ];
var __currentView = "class";

var ON = 1;
var OFF = 0;

var originalUnloadFunc;

// Does what it says on the tin
function __pleaseWaitModal(state) {
	if(state)
		$("#please-wait").modal('show');
	else
		$("#please-wait").modal('hide');
}

var __datasourceResponderCallbacks = [];

function __datasourceResponder(event) {
	var len = __datasourceResponderCallbacks.length;
	for(var i = 0; i < len; i++) {
		var callback = __datasourceResponderCallbacks[i];
		callback(event);
	}
}

function __datasourceRegisterCallback(callback) {
	__datasourceResponderCallbacks.push(callback);
}

// Used to populate the global Mustache template variable
function loadAndCacheMustacheTemplates() {
	$.get("/templates/mustache-templates.html", function(template, textStatus, jqXhr) {
		console.log("[common] Loading Mustache templates...");
		var tmpDiv = document.createElement("div");
		
		// Create an entry in the Mustache template dictionary for each template in mustache-templates.html
		$(tmpDiv).append(template);
        $(tmpDiv).find('script[type="text/x-handlebars-template"]').each(function () {
        	__mustacheTemplates[$(this).attr("id")] = $(this).html();
        });

        /*
		// illuminate the BF logo when we'te connected_
		__datasourceWorker.onmessage = function(event) {
			if(event.data['messageType'] === undefined)
				return;
			
			switch(event.data["messageType"]) {

				case "connected":

					$("#BFLogo").css("opacity", "1");
					console.log("[common] WebSocket connected");
					break;

				case "close":

					console.log("[common] Received 'close' message from datasource Web Worker.")
					$("#BFLogo").css("opacity", ".2");
					break;

			}
		};
		*/
        
        // Pass a copy of the templates to the data source Web Worker
        __datasourceWorker.postMessage({
        	messageType: "mustacheTemplates",
        	templates: __mustacheTemplates
        });

        console.log("[common] Mustache templates loaded. Triggering mustacheReady event!");

        // Notify the tools that Mustache is ready
        $(document).trigger("mustacheReady");
    });
}

/*
	Initialize all the things!
*/
$(document).on("mustacheReady", function () {
	/*
		Select the class panel by default
	*/
	$("#btn-panel-class").trigger("click");
});


$(document).ready( function () {

	var _defaultPanel = "class";
	var _previouslySelectedRow = undefined;

	/*
		Display a nice spinny thing while we load all the things
	*/
	__pleaseWaitModal(true);


	/*
		Setup the objc_msgSend logging watchlist class
	*/
	watchlist.init();

	/*
		Initialize context menu system
	*/
	context.init({
		fade: false,
		filter: function ($obj){},
		above: 'auto',
		preventDoubleContext: true,
		compress: false
	});

	console.log("[common] Creating Web Worker");
	__datasourceWorker = new Worker("js/ispy-datasource.js"); // Setup the WebWorker to handle WebSocket connections to iDevices
	
	/*
		Initialize the background datasource Web Worker for handling objc_msgSend events
		This does NOT connect the Web Worker to the iSpy WebSocket. "connect" will be called later.
	*/
	console.log("[common] Initializing Web Worker");
	__datasourceWorker.postMessage({
		messageType: "init"
	});

	/*
		We trigger a message to the document so that JS classes can register for notifications
	*/
	console.log("[common] Setting up dispatcher for messages from Web Worker");
	__datasourceWorker.onmessage = function (event) {
		__datasourceResponder(event);
	}

	__datasourceRegisterCallback(function(event) {
        if(event === undefined || event.data === undefined || event.data['messageType'] === undefined)
            return;

        switch(event.data["messageType"]) {

        	case "connected":

				console.log("[objc] Connected to data source Web Worker.");
				$("#objc-table-wait").addClass("hidden");
				$("#objc-table-outer").removeClass("hidden");

				break;

			case "close":

				console.log("[objc] Received 'close' message from datasource Web Worker.");
				break;

			case "connected":

				$("#BFLogo").css("opacity", "1");
				console.log("[common] WebSocket connected");
				break;

			case "close":

				console.log("[common] Received 'close' message from datasource Web Worker.")
				$("#BFLogo").css("opacity", ".2");
				break;

			case "log":
				var message = unescape(event.data["message"])	.replace(/\n+$/g, '')
																.replace(/</g, "&lt;")
																.replace(/>/g, "&gt;")
																+ "\n";
				if(message.length == 1) // skip solo newlines
					break;

				$("#log-window").append(message).scrollTop(0xffffffff);
				
				break;
		}
	});

	/*
		Load the Mustache HTML templates
	*/
	$(document).on("mustacheReady", function () {
		console.log("[common] Initializing __classDumpPopup");
		__classDumpPopup = new ClassDumper({
			DOMElement: "#popupClassDump"
		});

		$("body").delegate(".class-link", "click", function () {
			var className = $(this).html().replace(/ \*$/, "");

			__classDumpPopup.renderClass({
				className: className,
				callback: function (objSelf) {
					$(objSelf.DOMElement).removeClass("hidden");
					$("#class-dump-popup-modal").modal('show');
				}
			});
		});

		$("body").delegate(".object-link", "click", function () {
			var objectAddress = $(this).html();

			__classDumpPopup.renderObject({
				objectAddress: objectAddress,
				callback: function (objSelf) {
					//console.log("[objc render] Callback: ", objSelf);
					$(objSelf.DOMElement).removeClass("hidden");
					$("#class-dump-popup-modal").modal('show');
				}
			});
		});

	});
	loadAndCacheMustacheTemplates();

	$("#class-dump-popup-modal").modal({
		keyboard: true,
		backdrop: true,
		show: false
	});

	// Ensure we ignore unwanted keyboard events
    $("#searchBox").unbind('keyup');
    $("#searchBox").unbind('keyup.DT');

    keyboard.init();
    keyboard.setView("class");

	// Use alt-` to popup the classdump popup
	keyboard.addHandler({
		keyCode: 192, // `
		altKey: true,
		selector: document,
		type: "keydown",
		preventDefault: true,
		handler: function (e) {
			$("#class-dump-popup-modal").modal("toggle");
		}
	});

	// Use ESC to dismiss the popover window
	keyboard.addHandler({
		keyCode: 27, // ESC
		selector: document,
		type: "keydown",
		preventDefault: true,
		handler: function (e) {
    		$("#class-dump-popup-modal").modal("hide");
		}
	});

	// Use / to jump to the search box
	keyboard.addHandler({
		keyCode: 191, // /
		selector: document,
		type: "keyup",
		preventDefault: true,
		handler: function (e) {
			search.focus();
		}
	});

	// Use alt-[1-5] to display the various tools/views
	for(var i = 49; i <= 58; i++) {
		keyboard.addHandler({
			keyCode: i,
			selector: document,
			type: "keydown",
			altKey: true,
			preventDefault: true,
			handler: function (e) {
				var index = e.keyCode - 49;
				$(search.textObj).blur();
				$("#btn-panel-" + __viewPanels[index]).trigger("click");
			}
		});			
	}

	// Send an event upon an arrow down keypress
	keyboard.addHandler({
		keyCode: 40, // DOWN
		selector: document,
		type: "keydown",
		preventDefault: true,
		handler: function (e) {
			$(document).trigger("KEYDOWN");
		}
	});

	// Send an event upon an arrow PGUP keypress
	keyboard.addHandler({
		keyCode: 33, // PGUP
		selector: document,
		type: "keydown",
		preventDefault: true,
		handler: function (e) {
			$(document).trigger("KEYPGUP");
		}
	});

	// Send an event upon an arrow PGDOWN keypress
	keyboard.addHandler({
		keyCode: 34, // PGDOWN
		selector: document,
		type: "keydown",
		preventDefault: true,
		handler: function (e) {
			$(document).trigger("KEYPGDOWN");
		}
	});

	// Send an event upon an arrow up keypress
	keyboard.addHandler({
		keyCode: 38, // UP
		selector: document,
		type: "keydown",
		preventDefault: true,
		handler: function (e) {
			$(document).trigger("KEYUP");
		}
	});

	// Prevent the default handler for ENTER keydown. If we don't, the page reloads.
	keyboard.addHandler({
		keyCode: 13, // ENTER
		selector: search.textObj,
		type: "keydown",
		preventDefault: true
	});

	keyboard.addHandler({
		keyCode: keyboard.ANY_KEY,
		type: "keydown",
		selector: document,
		ctrlKey: false,
		metaKey: false,
		altKey: false,
		shiftKey: keyboard.BOTH_STATES,
		handler: function (e) {
			var key = String.fromCharCode(e.keyCode).substring(0,1);
			if(key.match(/[a-zA-Z_]/) != null || e.keyCode == 8) {
				keyboard.moveFocusToRegion("search");
				$(document).trigger("searchAsYouTypeChanged");
			}
		}
	});

	// Inside the search box we trigger a search event if:
	// (a) key is pressed AND
	// (b) the search box has focus AND
	// (c) the keypress isn't already bound
	keyboard.addHandler({
		selector: search.textObj,
		type: "keypress",
		altKey: false,
		metaKey: false,
		ctrlKey: false,
		keyCode: keyboard.ANY_KEY,
		handler: function (e) {
			//console.log("target: " + e.target.id + " /// searchid: ", search.id());
			if(e.target.id == search.id()) {
				//$(document).trigger("searchAsYouTypeChanged");
			}
		}
	});

	// We have to handle backspace in the search bar in order to trigger a search refresh
	keyboard.addHandler({
		keyCode: 8,
		selector: search.textObj,
		type: "keyup",
		preventDefault: true,
		handler: function (e) {
			if(e.target.id == search.id()) {
				//$(document).trigger("searchAsYouTypeChanged");
			}
		}
	});

	// we have to do some extra work for the DEL key, which doesn't trigger an onchange event for some unknown reason
	keyboard.addHandler({
		selector: document,
		type: "keyup",
		altKey: false,
		metaKey: false,
		ctrlKey: false,
		keyCode: 46, // DEL key
		handler: function (e) {
			//console.log("target: " + e.target.id + " /// searchid: ", search.id());
			if(e.target.id == search.id()) {
				$(document).trigger("searchAsYouTypeChanged");
			}
		}
	});

	keyboard.addHandler({
		keyCode: 13, // ENTER
		selector: search.textObj,
		type: "keyup",
		preventDefault: true,
		handler: function (e) {
			//console.log("[keyboard] keyup 13");
			search.previousTextObj = search.text();
			$(document).trigger("searchChanged");
		}
	});	

/*
	$(document).on("rowSelected", function (e, index) {
		if(index == _previouslySelectedRow)
			return;
		_previouslySelectedRow = index;
		keyboard.moveFocusToRegion("list");
	});
*/

	$(document).on("searchGotFocus", function (e) {
		//console.log("[common] Caught 'focus' event, moving to search");	
		keyboard.moveFocusToRegion("search");
	});

	/*
		Setup the tool buttons on the navbar.
	*/
	$("#navbar-panel-buttons").children().on("click", function() {
		// Show the appropriate main panel
		var panel = $(this).first().children()[0];
		panel = $(panel).attr("id");
		var panelName = panel.replace("btn-panel-", "");
		panel = panel.replace("btn-", "");

		if(!panel)
			return;

		$(".ispypane").addClass("hidden");
		$("#" + panel).removeClass("hidden");

		// Nofity tools that the view changed
		__currentView = panelName;
		keyboard.setView(panelName);
		$(document).trigger("toolChanged", [panelName]);
	});

	$('#navbar-panel-buttons2').children().click(function(e) {
		console.log("Download pressed!");
		window.onbeforeunload = undefined;
		e.preventDefault();
		window.location.href = '/ipa';
		setTimeout(function() {
			window.onbeforeunload = function() {
				return "Are you sure?";
			};
			$('#btn-panel-ipa').closest("label").removeClass("active");
		}, 500);
	});

	/*
		Setup the search stuff
	*/
	search.init({
		"class": "#btnClass",
		"method": "#btnMethod",
		"property": "#btnProperty",
		"ivar": "#btnIVar",
		"regex": "#btnRegex",
		"caseSensitive": "#btnCaseSensitive",
		"input": "#searchBox",
		"data": "#btnData"
	});

	
	/*
		Let the objc_msgSend Web Worker know the current search parameters
	*/
	__datasourceWorker.postMessage({
		messageType: "setSearchParameters",
		searchParameters: search.parameters(),
	});


	/*
		Setup tool tips for search buttons
	*/
	$('#btnRegex').popover({
		trigger: "hover",
		content: "Toggle regex",
		placement: "bottom",
		delay: { "show": 1000, "hide": 100 }
	});
	$('#btnCaseSensitive').popover({
		trigger: "hover",
		content: "Toggle case sensitivity",
		placement: "bottom",
		delay: { "show": 1000, "hide": 100 }
	});
	$('#btnClass').popover({
		trigger: "hover",
		content: "Search class names",
		placement: "bottom",
		delay: { "show": 1000, "hide": 100 }
	});
	$('#btnMethod').popover({
		trigger: "hover",
		content: "Search method (selector) names",
		placement: "bottom",
		delay: { "show": 1000, "hide": 100 }
	});
	$('#btnProperty').popover({
		trigger: "hover",
		content: "Search property names",
		placement: "bottom",
		delay: { "show": 1000, "hide": 100 }
	});
	$('#btnIVar').popover({
		trigger: "hover",
		content: "Search instance variable names",
		placement: "bottom",
		delay: { "show": 1000, "hide": 100 }
	});
	$('#btnData').popover({
		trigger: "hover",
		content: "Search data values",
		placement: "bottom",
		delay: { "show": 1000, "hide": 100 }
	});


	/*
		A generic catch-all handler for when the tool view changes.
	*/
	$(document).on("toolChanged", function () {
		$(".btn").removeClass("disabled");
		//console.log("[common] Resetting navbar to default.");
		//$("#navbar-menu-placeholder").html("");
	});

	/*
		It can be really annoying to accidentally swipe left (go back) and close iSpy...
	*/
 	originalUnloadFunc = window.onbeforeunload;
	window.onbeforeunload = function() {
		return "Are you sure?";
	};

	/*
		For the Cycript shell.

	var history = new Josh.History({ key: 'helloworld.history'});
	var shell = Josh.Shell({history: history});
	shell.activate();
	*/
});

