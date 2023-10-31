function TableSelect(initOptions) {
	this.selector = initOptions["selector"];
	this.onChangeCallback = initOptions["onChange"];
	this.onSingleSelectCallback = initOptions["onSingleSelect"];
	this.onMultiSelectCallback = initOptions["onMultiSelect"];
	this.selectedRows = [];
	this.lastSelectedRow = undefined;
	this.onDblClick = initOptions["onDblClick"];
	var that = this;
	
	$(this.selector + ' tbody').on( 'click', 'tr', function (event) {
		var tableRow = $(this).closest("tr").prevAll("tr").length;     	

		//console.log("[select] click row: ", tableRow, " event:", event);

		// if we're selecting multiple one at a time with CMD or CTRL
		if(event.metaKey || event.ctrlKey) {
			if($(this).hasClass('active')) {
				$(that.selector).DataTable().row(tableRow).deselect();
				$(that.selector).DataTable().rows(tableRow).nodes().to$().removeClass('active');
				var position = that.selectedRows.indexOf(tableRow);
				that.selectedRows.splice(position, 1);   
				
				if(that.lastSelectedRow == tableRow)
					that.lastSelectedRow = that.selectedRows[0] || 0;
			} else {
				that.selectRow(tableRow);
			}

			if(that.onMultiSelectCallback && that.count() > 1)
				that.onMultiSelectCallback(that);
		} 

		// if we're doing multi-column select with shift key
		else if (event.shiftKey) { 
			var table = $(that.selector);        
			var start = Math.min(tableRow, that.lastSelectedRow);
			var end = Math.max(tableRow, that.lastSelectedRow);                 

			that.selectedRows = []; 

			if(that.lastSelectedRow === undefined) {
				that.selectRow(tableRow);
			} else {
				for(var i = start; i<= end; i++) {
					that.selectRow(i);
				}
			}

			if(that.onMultiSelectCallback && that.count() > 1)
				that.onMultiSelectCallback(that);
	    } 

	    // otherwise we just select a single entry
	    else {
			that.deselectAllRows();
			that.selectRow(tableRow);

	    	// fire the callback
	    	if(that.onSingleSelectCallback)
	    		that.onSingleSelectCallback(that);
	    }

	    // Fire the onChange callback, if any
	    if(that.onChangeCallback)
	    	that.onChangeCallback(that);
	});

	if(that.onDblClick !== undefined) {
		console.log("[select] dblclick handler being registered");
		$(that.selector + ' tbody').dblclick(function (event) {
			event.preventDefault();
			$(that.selectedRows + ' tbody').trigger('dblclick');
			that.onDblClick(that);
		});
	}

	// Exported functions
	this.count = TableSelect.prototype.count;
	this.deselectAllRows = TableSelect.prototype.deselectAllRows;
	this.addClass = TableSelect.prototype.addClass;
	this.removeClass = TableSelect.prototype.removeClass;
	this.prevRow = TableSelect.prototype.prevRow;
	this.nextRow = TableSelect.prototype.nextRow;

	// handle keyboard up/down controls and scrolling nicely
	if(initOptions["view"] !== undefined) {
		$(document).on("KEYDOWN", function () {
			if(__currentView == initOptions["view"])
				that.nextRow();
		});
		$(document).on("KEYUP", function () {
			if(__currentView == initOptions["view"])
				that.prevRow();
		});
		$(document).on("KEYPGDOWN", function () {
			if(__currentView == initOptions["view"])
				that.nextRow(10);
		});
		$(document).on("KEYPGUP", function () {
			if(__currentView == initOptions["view"])
				that.prevRow(10);
		});
	}
}

TableSelect.prototype.currentRow = function() {
	return this.lastSelectedRow;
}

TableSelect.prototype.addClass = function(className) {
	$(this.selector).DataTable().rows(this.selectedRows).nodes().to$().addClass(className);
}

TableSelect.prototype.removeClass = function(className) {
	$(this.selector).DataTable().rows(this.selectedRows).nodes().to$().removeClass(className);
}

TableSelect.prototype.selectRow = function(index) {
	//console.log("[select] this.selector: ", this.selector);

	if(index === undefined || index < 0)
		return;

	var tableElement = $(this.selector);
	//console.log("[select] tableElement: ", tableElement);

	var table = tableElement.DataTable();
	//console.log("[select] table: ", table);
	
	table.rows(index).select();
	table.rows(index).nodes().to$().addClass("active");
	this.selectedRows.push(index);
	this.lastSelectedRow = index;

	var tableDivElement = $($($(tableElement.parent()).parent()).get(0));
	//console.log("[select] tableDivElement: ", tableDivElement);
	
	var rowElement = table.rows(index).nodes().to$();
	var tableOnScreenHeightInPixels = tableDivElement.height();
	var rowHeightInPixels = rowElement.height();
	//var rowYABS = $(rowElement[0]).position().top;
	var rowYABS = index * rowHeightInPixels;
	if($(rowElement[0]).position() === undefined)
		return;
	var rowYREL = $(rowElement[0]).position().top;
	var selectMinY = tableOnScreenHeightInPixels / 4;
	var selectMaxY = selectMinY * 3;
	var minScroll = 0;
	var rowsOnPage = table.rows().count();
	var maxScroll = (rowsOnPage * rowHeightInPixels) - tableOnScreenHeightInPixels;
	var scrollElement;
	if(this.selector == "#objcTable") { //// ewww, gross
		scrollElement = tableElement.parent();
	} else {
		scrollElement = tableDivElement;
	}
	var scrollTop = scrollElement.scrollTop();

	/*console.log("[select] ========== go =========");
	console.log("[select] table.page(): ", table.page());
	console.log("[select] scrollElement: ", scrollElement);
	console.log("[select] tableDivElement: ", tableDivElement);
	console.log("[select] tableElement: ", tableElement);
	console.log("[select] tableOnScreenHeightInPixels: ", tableOnScreenHeightInPixels);
	console.log("[select] rowHeightInPixels: ", rowHeightInPixels);
	console.log("[select] rowYABS: ", rowYABS);
	console.log("[select] scrollTop: ", tableDivElement.scrollTop());
	console.log("[select] rowElement: ", rowElement);
	console.log("[select] selectMinY: " + selectMinY + " selectMaxY: " + selectMaxY);
	console.log("[select] rowsOnPage: ", rowsOnPage);
	console.log("[select] maxScroll = ", maxScroll);*/

	if(!tableOnScreenHeightInPixels || tableOnScreenHeightInPixels == 0 || rowHeightInPixels == 0)
		return;

	//console.log("[select] ========== <<<< =========");

	while(rowYREL < selectMinY && scrollTop > minScroll) {
		//scrollTop = scrollElement.scrollTop();
		scrollTop -= rowHeightInPixels;
		scrollElement.scrollTop(scrollTop);
		rowYREL = $(rowElement[0]).position().top;
		/*console.log("[select] < tableOnScreenHeightInPixels: ", tableOnScreenHeightInPixels);
		console.log("[select] < scrollTop: ", scrollTop, " minScroll: ", minScroll);
		console.log("[select] < rowYREL: ", rowYREL);
		console.log("[select] < rowYABS: ", rowYABS);*/
	}

	//console.log("[select] selectMinY: " + selectMinY + " selectMaxY: " + selectMaxY);
	//console.log("[select] ========== >>>> =========");

	scrollTop = scrollElement.scrollTop();
	while(rowYREL > selectMaxY && scrollTop < maxScroll) {
		//scrollTop = scrollElement.scrollTop();
		scrollTop += rowHeightInPixels;
		scrollElement.scrollTop(scrollTop);
		rowYREL = $(rowElement[0]).position().top;
		/*console.log("[select] > tableOnScreenHeightInPixels: ", tableOnScreenHeightInPixels);
		console.log("[select] > scrollTop: ", scrollTop, " maxScroll: ", maxScroll);
		console.log("[select] > rowYREL: ", rowYREL);
		console.log("[select] > rowYABS: ", rowYABS);*/
	}
}

TableSelect.prototype.deselectAllRows = function() {
	$(this.selector).DataTable().rows().deselect();
	$(this.selector).each(function() {
		$(this).find("tr").removeClass('active');
	});
	this.lastSelectedRow = undefined;
	this.selectedRows = []; 
}

TableSelect.prototype.highlightSelectedRows = function() {
	$(this.selector).DataTable().rows(this.selectedRows).nodes().to$().addClass("active");
	$(this.selector).DataTable().rows(this.selectedRows).select();
}

TableSelect.prototype.count = function() {
	return this.selectedRows.length;
}

TableSelect.prototype.nextRow = function(numRows) {
	if(numRows === undefined)
		numRows = 1;
	var oldRow = this.lastSelectedRow;
	var page = $(this.selector).DataTable().page.info();
	var MAX_ROWS = page.end;
	var numRowsOnPage = page.end; //((page.end - page.start - 1) < MAX_ROWS) ? (page.end - page.start - 1) : MAX_ROWS;

	console.log("[nextRow] page = ", page, " oldRow = ", oldRow, " numRowsOnPage = ", numRowsOnPage, " numRows = ", numRows);
	if(oldRow >= numRowsOnPage - 1)
		return;

	if(oldRow + numRows > numRowsOnPage)
		numRows = numRowsOnPage - oldRow - 1;
	
	this.deselectAllRows();
	this.selectRow(oldRow + numRows);
	this.onSingleSelectCallback(this);
}

TableSelect.prototype.prevRow = function(numRows) {
	if(numRows === undefined)
		numRows = 1;

	var oldRow = this.lastSelectedRow;
	var page = $(this.selector).DataTable().page.info();
	
	if(oldRow <= 0)
		return;
	
	if(oldRow - numRows < 0)
		numRows = oldRow;

	this.deselectAllRows();
	this.selectRow(oldRow - numRows);
	this.onSingleSelectCallback(this);
}
