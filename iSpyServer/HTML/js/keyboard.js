/*
	keyboard.js
	Support for hotkeys.
*/

var keyboard = keyboard || (function () {
	var DEBOUNCE_TIMEOUT = 20; // used for keydown events
	var ANY_KEY = "0xbadc0ded";
	var BOTH_STATES = "0xdeadbeef";
	var _keyEvents = [];
	var _tabRegions = {};
	var _debounce = false;
	var _currentView = undefined;
	
	function init(options) {

		// Trap the TAB key 
		addHandler({
			type: "keydown",
			keyCode: 9,
			preventDefault: true,
			shiftKey: BOTH_STATES,
			ctrlKey: false,
			metaKey: false,
			altKey: false,
			handler: function (e) {
				//console.log("[keyboard] _tabRegions: ", _tabRegions);
				
				var view = _tabRegions[_currentView];
				if(view === undefined)
					return;

				var currentRegion = view["currentRegion"];
				var region = view["regions"][currentRegion];
				var element = region["element"];
				
				//$(element).removeClass("focus");
				try {
					$(element).removeClass("focus");
					$(element).get(0).blur();	
				} catch(ev) {

				}

				if((e.shiftKey === false) && ((++currentRegion) == view["regions"].length))
					currentRegion = 0;
				if((e.shiftKey === true) && ((--currentRegion) == -1))
					currentRegion = view["regions"].length - 1;


				view["currentRegion"] = currentRegion;
				region = view["regions"][currentRegion];

				element = region.element;
				$(element).focus();
				$(element).addClass("focus");

				if(region.callback)
					region.callback(e);
			}
		})
	}

	function getRegionObjForIndex(index) {
		var view = _tabRegions[_currentView];
		if(view === undefined)
			return undefined;
		
		var currentRegion = view["currentRegion"];
		var region = view["regions"][currentRegion];

		return region;
	}

	function moveFocusToRegionIndex(index) {
		var view = _tabRegions[_currentView];
		if(view === undefined)
			return undefined;

		var currentRegion = view["currentRegion"];
		if(currentRegion === undefined)
			return undefined;

		var region = view["regions"][currentRegion];
		if(region === undefined) {
			return undefined;
		}

		var element = region["element"];

		try {
			$(element).removeClass("focus");
			$(element).get(0).blur(); // this can barf	
		} catch(ev) {}

		view["currentRegion"] = index;
		region = view["regions"][index];
		element = region.element;
		
		$(element).focus();
		$(element).addClass("focus");
		
		if(region.callback)
			region.callback();

		return;
	}

	function moveFocusToRegion(regionName) {
		//console.log("[keyboard] movefocustoregion _currentView: ", _currentView);
		var view = _tabRegions[_currentView];
		if(view === undefined)
			return;

		var regions = view["regions"];

		for(var i = 0; i < regions.length; i++) {
			if(regions[i]["name"] == regionName) {
				moveFocusToRegionIndex(i);
				return;
			}
		}

		//console.log("[keyboard focus] This wasn't supposed to happen with regionName = ", regionName);
	}

	function setView(view) {
		_currentView = view;
	}

	function registerForTabKey(options) {
		var view = options.view;

		//console.log("[reg] options: ", options);
		_tabRegions[view] = {};
		_tabRegions[view]["currentRegion"] = options.startingRegion || 0;
		_tabRegions[view]["regions"] = options["regions"];
		//console.log("[reg] _tr[ov]: ", _tabRegions);
	}

	function isGlobalHotkey(e) {
		var key = keyboard.isMatch(e);
		if(key !== undefined) {
			var element = key.selector;
			
			if(	e.indexOf('#') == 0 || e.indexOf('.') == 0)
				element = element.substring(1);
			
			if(element == e.target.id)
				return true;
		}

		return false;
	}

	function addHandler(obj) {
		if(obj.type === undefined)
			return false;
		
		if(obj.altKey === undefined)
			obj.altKey = false;
		if(obj.metaKey === undefined)
			obj.metaKey = false;
		if(obj.shiftKey === undefined)
			obj.shiftKey = false;
		if(obj.ctrlKey === undefined)
			obj.ctrlKey = false;
		if(obj.selector === undefined)
			obj.selector = document;
		if(obj.handler === undefined)
			obj.handler = function () {};
		if(obj.stopPropagation === undefined)
			obj.stopPropagation = false;
		
		_keyEvents.push(obj);

		$(obj.selector).bind(obj.type, function (e) {
			//console.log("[keyboard] Got keycode " + e.keyCode + " (" + String.fromCharCode(e.keyCode) + ")");
			var key = keyboard.isMatch(e);
			if(key !== undefined) {
				debounce(key.handler, e);
				if(key.preventDefault === true)
					e.preventDefault();
				return;
			}
		});
	}

	function isMatch(e) {
		for(var i in _keyEvents) {
			if(	(_keyEvents[i].altKey == BOTH_STATES || _keyEvents[i].altKey === e.altKey) &&
				(_keyEvents[i].metaKey == BOTH_STATES || _keyEvents[i].metaKey === e.metaKey) &&
				(_keyEvents[i].shiftKey == BOTH_STATES || _keyEvents[i].shiftKey === e.shiftKey) &&
				(_keyEvents[i].ctrlKey == BOTH_STATES || _keyEvents[i].ctrlKey === e.ctrlKey) &&
				_keyEvents[i].type === e.type)
			{

				if( (_keyEvents[i].keyCode === e.keyCode) || 
					(_keyEvents[i].keyCode === ANY_KEY))
				{
					return _keyEvents[i];
				}

				// if it's a "keypress" event, 
				if(_keyEvents[i].type == "keypress") {
					//console.log("[keyboard] keypress: ", getChar(e.keyCode));
					if( (_keyEvents[i].keyCode === getChar(e.keyCode)) || 
						(_keyEvents[i].keyCode === ANY_KEY))
					{
						return _keyEvents[i];		
					}
				} else {
					if( (_keyEvents[i].keyCode === e.keyCode) || 
						(_keyEvents[i].keyCode === ANY_KEY))
					{
						return _keyEvents[i];
					}
				}
			}
		}
		return undefined;
	}

	// from http://javascript.info/tutorial/keyboard-events
	function getChar(event) {
		event = event || window.event; // haggis: add sanity check
		if (event.which == null) {
			return String.fromCharCode(event.keyCode) // IE
		} else if (event.which!=0 && event.charCode!=0) {
			return String.fromCharCode(event.which)   // the rest
		} else {
			return null // special key
		}
	}

	function debounce(callback, args) {
		if(_debounce === true)
			return false;

		_debounce = true;
		
		setTimeout(function () {
			_debounce = false;
		}, DEBOUNCE_TIMEOUT);

		if(callback)
			callback(args);
	}

	function currentRegion() {
		var view = _tabRegions[_currentView];
		if(view === undefined)
			return undefined;

		var currentRegion = view["currentRegion"];
		
		return view["regions"][currentRegion]["name"]; 
	}	

	return {
		init: init,
		addHandler: addHandler,
		isMatch: isMatch,
		ANY_KEY: ANY_KEY,
		BOTH_STATES: BOTH_STATES,
		registerForTabKey: registerForTabKey,
		setView: setView,
		moveFocusToRegion: moveFocusToRegion,
		currentRegion: currentRegion	
	};
})();