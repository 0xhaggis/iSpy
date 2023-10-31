/*
	search.js
	Support for interacting with the search feature.
*/

var search = search || (function () {
	var isClassObj = undefined;
	var isMethodObj = undefined;
	var isPropertyObj = undefined;
	var isIVarObj = undefined;
	var isCaseSensitiveObj = undefined;
	var isDataObj = undefined;
	var textObj = undefined;
	var previousTextObj = undefined;

	function isMatch(inputHaystack) {
		var caseSense = "i";
		if(search.isCaseSensitive())
			caseSense = "";
		
		var re = new RegExp(search.text(), caseSense);
		if(re.test(inputHaystack))
			return true;
		
		return false;
	}

	function ord(c) {
		return c.charCodeAt(0);
	}

	function initialize(options) {
		if(!options)
			return false;

		if(!options["input"])
			return false;

		isClassObj = options["class"];
		isMethodObj = options["method"];
		isPropertyObj = options["property"];
		isIVarObj = options["ivar"];
		isDataObj = options["data"];
		isCaseSensitiveObj = options["caseSensitive"];
		textObj = options["input"];
		previousTextObj = search.text();

		// handlers for the search option buttons
		for(var i in options) {
			// is this one of the search buttons?
			if(i.indexOf("input") == -1) {
				// yup
				var obj = options[i];
				$(obj).on("click", function () {
					$(this).toggleClass("active");
					$(document).trigger("searchOptionsChanged");
					search.focus();
				});
			} 
			// if not a search button, this is the search input field
			else {
				var obj = options[i];
				$(obj).on("click", function () {
					//console.log("Search text input click event");
					$(document).trigger("searchGotFocus");
					$(document).trigger("searchAsYouTypeChanged");
				});
				$(obj).change(function () {
					//console.log("Search text input change event");
					$(document).trigger("searchAsYouTypeChanged");
				});
			}	
		}

		focus();
		return true;
	}

	function highlightSearchTextInString(str) {
		if(!str)
			return null;

		var searchText = search.text();
		if(!searchText || searchText == "")
			return null;

		var html = str;
		if(!html || html == "")
			return null;

		var options = (search.isCaseSensitive()) ? "gm" : "gim";
		var pattern = new RegExp(searchText, options);
		var m;
		m = html.match(pattern);
		if(!m)
			return html;

		console.log("[highlightSearchTextInDOMElement] Matched: ", m, " in HTML string for " + searchText);

		for(var i = 0; i < m.length; i++) {
			console.log("[highlightSearchTextInDOMElement] Replacing " + m[i] + " with span'd version");
			html = html.replace(m[i], '<span class="search-highlight">' + m[i] + '</span>');
		}

		return html;
	}

	function highlightSearchTextInDOMElement(element) {
		if(!element || search.text() == "")
			return null;

		$(element + " span").each(function() {
			var highlightedText = highlightSearchTextInString($(this).html());
			$(this).html(highlightedText);
		});
	}

	function parameters() {
		return {
			text: text(),
			isCaseSensitive: isCaseSensitive(),
			isClass: isClass(),
			isMethod: isMethod(),
			isProperty: isProperty(),
			isIVar: isIVar(),
			isData: isData()
		};
	}

	function focus() {
		$(textObj).focus();
	}

	function isData() {
		if(isDataObj) 
			return $(isDataObj).hasClass("active");
		else
			return false;
	}

	function isClass() {
		if(isClassObj)
			return $(isClassObj).hasClass("active");
		else
			return false;
	}

	function isMethod() {
		if(isMethodObj)
			return $(isMethodObj).hasClass("active");
		else
			return false;
	}

	function isProperty() {
		if(isPropertyObj)
			return $(isPropertyObj).hasClass("active");
		else
			return false;
	}

	function isIVar() {
		if(isIVarObj)
			return $(isIVarObj).hasClass("active");
		else
			return false;
	}

	function isCaseSensitive() {
		if(isCaseSensitiveObj)
			return $(isCaseSensitiveObj).hasClass("active");
		else
			return false;
	}

	function text(newText) {
		if(newText) {
			$(textObj).get(0).value = newText;	
			return newText;
		} 
		
		return $(textObj).get(0).value;
	}

	function trigger(event) {
		$(document).trigger(event);
	}

	function changed() {
		return previousTextObj == text();
	}

	function id() {
		var name = textObj;
		if(name.indexOf("#") == 0)
			name = name.substring(1);
		return name;
	}

	return {
		init: initialize,
		textObj: textObj,
		text: text,
		isClass: isClass,
		isMethod: isMethod,
		isProperty: isProperty,
		isIVar: isIVar,
		isData: isData,
		isCaseSensitive: isCaseSensitive,
		trigger: trigger,
		focus: focus,
		parameters: parameters,
		previousTextObj: previousTextObj,
		changed: changed,
		id: id,
		isMatch: isMatch,
		highlightSearchTextInDOMElement: highlightSearchTextInDOMElement
	};
})();
