/*
	watchlist.js
	Support for interacting with the objc_msgSend tracing watchlist.
*/

var CLEAR_FROM_LOG = true;

var watchlist = watchlist || (function () {
	var _methodData = [];
	var _watchlistUpdateData = undefined;
	var _watchlist = [];
	var _lastUpdate = 0;

	/*
		Helper functions
	*/

	function initialize() {
		refresh();
	}

	function watchlist() {
		return _watchlist;
	}

	// Populate the watchlist by getting it from the iDevice
	function refresh(callback) {
		var d = new Date();
		var t = d.getTime();
		if(t > _lastUpdate) {
			_lastUpdate = t;
			return $.ajax({
				type: "POST",
				url: "/rpc",
				dataType: "text",
				processData: false,
				data: '{"messageType": "getWhitelist", "messageData": {}}',
				success: function (data) {
					_watchlist = JSON.parse(data)["JSON"]["watchlist"];
					if(callback) {
						callback();
					}
				}
			});
		}
	}

	function isSelectorOnWhitelist(className, selector) {
		if(_watchlist[className]) {
			if(_watchlist[className]["methodCountForWhitelist"] == 0)
				return true;

			if(_watchlist[className]["methods"].indexOf(selector) != -1)
				return true;
		}
		return false;
	}

	function isClassOnWhitelist(className) {
		if(_watchlist[className] !== undefined) {
			return true;
		}
		return false;
	}

	function addEntries(entries) {
		var def = $.Deferred();
		var requests = [];
	
		// base request
		var req = JSON.stringify({
			messageType: "addMethodsToWhitelist", 
			messageData: entries
		});
		
		//console.log("[watchlist] Adding these entries to watchlist: ", req);	
		requests.push($.ajax({
			type: "POST",
			url: "/rpc",
			dataType: "text",
			processData: false,
			data: req
		}));

		$.when.apply($, requests).then(function() {
			def.resolve(); 
		});

		return def;
	}

	function removeEntries(entries) {
		var def = $.Deferred();
		var requests = [];
	
		// base request
		var req = JSON.stringify({
			messageType: "removeMethodsFromWhitelist", 
			messageData: entries
		});
			
		requests.push($.ajax({
			type: "POST",
			url: "/rpc",
			dataType: "text",
			processData: false,
			data: req
		}));

		$.when.apply($, requests).then(function() {
			def.resolve(); 
		});

		return def;
	}

	return {
		init: initialize,
		addEntries: addEntries,
		removeEntries: removeEntries,
		refresh: refresh,
		watchlist: watchlist,
		isSelectorOnWhitelist: isSelectorOnWhitelist,
		isClassOnWhitelist: isClassOnWhitelist
	};
})();
