/*
	keychain.js
	View/edit the keychain on the iDevice.
*/

$(document).ready( function () {
	var _newNavBarEntriesHTML = "";
	var _keychainItems = {};
	var _currentChain = "";

	Handlebars.registerHelper('if_eq', function(a, b, opts) {
	    if(a == b)
	        return opts.fn(this);
	    else
	        return opts.inverse(this);
	});

	Handlebars.registerHelper('if_neq', function(a, b, c, opts) {
	    if(a == b || ((c) && a == c))
	        return opts.inverse(this);
	    else
	        return opts.fn(this);
	});

	function updateUIForKeychainItem(item) {
		var HTML;
		//console.log("items: ", _keychainItems[item], _keychainItems[item].length);
		if(_keychainItems[item].length === 0) {
			HTML = Handlebars.compile(__mustacheTemplates["keychainForm"])({
				"notFoundContent": item
			});
		} else {
			HTML = Handlebars.compile(__mustacheTemplates["keychainForm"])(_keychainItems[item]);
		}

		_currentChain = item;
		//console.log("HTML: ", HTML);
		$("#panel-keychain").html(HTML);
	
		// make sure pressing the "edit" button actually does something
		$(".keychain-edit-button").on("click", function () {
			console.log("You pressed: ", this);
			var index = $(this).attr("data-index");
			console.log("index, chain, item", index, _currentChain, _keychainItems[_currentChain][index]);
			var formHTML = Handlebars.compile(__mustacheTemplates["tmpl-edit-keychain-form"])(_keychainItems[_currentChain][index]);
			$("#edit-keychain-form").html(formHTML);
			$("#edit-keychain-item").modal('show');
			$("#edit-keychain-save").on("click", function() {
				$("#edit-keychain-item").modal('hide');
				_keychainItems[_currentChain][index]["svce"] = $("#edit-keychain-service").attr("value");
				_keychainItems[_currentChain][index]["v_Data"] = $("#edit-keychain-data").get()[0].value; // stupid javascript
				// do_save_here
				updateUIForKeychainItem(_currentChain);
			});
		});
	}

	$(document).on("mustacheReady", function() {
		console.log("[keychain] Initializing.");
		$.ajax({
			type: "POST",
			url: "/rpc",
			data: JSON.stringify({
				messageType: "keyChainItems", 
				messageData: {}
			}),
			success: function ( data, textStatus, jqXHR ) {
				// Get the JSON blob containing keychain entries
				var jsonData = JSON.parse(data)["JSON"];
				//console.log("[keychain] Got keychain data: ", jsonData);
				_keychainItems = jsonData;

				// Update the keychain viewer pane
				var firstItem = Object.keys(jsonData)[0];
				updateUIForKeychainItem(firstItem);

				// Update the menu bar
				_newNavBarEntriesHTML = Handlebars.compile(__mustacheTemplates["tmpl-navbar-menu-keychain"])(jsonData);
				console.log("[keychain] Finished initializing.");
			}
		});
	});

	// If we want to do something when the user changes view/tool, then we need to catch "toolChanged".
	$(document).on("toolChanged", function(event, newTool) {
		if(newTool == "keychain") {
			$("#searchButtonDiv button").each(function () {
				$(this).removeClass("disabled");
			});
			
			$("#navbar-menu-placeholder").append($(_newNavBarEntriesHTML));
			$("#navbar-menu-placeholder ul li").on("click", function() {
				var item = $(this).first().children()[0];
				var choice = $(item).data("menu-item");
				
				if(choice === undefined)
					return;

				//console.log("You chose: '" + choice + "' ", _keychainItems[choice]);
				updateUIForKeychainItem(choice);
			});
		}
	});
});
