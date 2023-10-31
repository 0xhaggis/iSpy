/*
	dashboard.js
	
*/

$(document).ready( function () {
	var _infoListDataTable = undefined;
	var _infoSelector = undefined;
	var _menuItems = [
		{
			title: "Overview",
			render: function () {
				$.ajax({
					type: "POST",
					url: "/rpc",
					dataType: "text",
					processData: false,
					data: '{ "messageType": "applicationIcon", "messageData": {} }',
					success: function (data) {
						var json = JSON.parse(data);
						if(json === undefined || json["JSON"] == undefined) {
							return;
						}
						json = json["JSON"];
						console.log("[Dashboard] appicon response: ", json);
						var renderedHTML = Handlebars.compile(__mustacheTemplates["dashboard-app-icon"])(json);
						$("#infoSectionAppIcon").html(renderedHTML);
					}
				});

				$.ajax({
					type: "POST",
					url: "/rpc",
					dataType: "text",
					processData: false,
					data: '{ "messageType": "ASLR", "messageData": {} }',
					success: function (data) {
						var json = JSON.parse(data);
						if(json === undefined || json["JSON"] == undefined) {
							return;
						}
						json = json["JSON"];
						console.log("[Dashboard] ASLR response: ", json);
						var renderedHTML = Handlebars.compile(__mustacheTemplates["dashboard-ASLR"])(json);
						$("#infoSectionASLR").html(renderedHTML);
					}
				});
			}
		}
	];

	/*
		Create the class list DataTable
	*/
	_infoListDataTable = $('#infoListTable').DataTable({
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

	_infoSelector = new TableSelect({
		selector: "#infoListTable",
		onSingleSelect: function (selSelf) {
			var row = selSelf.currentRow();
			_menuItems[row].render();
		},
		onMultiSelect: function (selSelf) {

		},
		onChange: function (selSelf) {

		}
	});

	$(document).on("mustacheReady", function () {
		console.log("[Dashboard] Initializing.");

		_infoListDataTable.clear();
		for(var i = 0; i < _menuItems.length; i++) {
			var item = _menuItems[i];
			_infoListDataTable.row.add([item["title"]]).draw();
		}

	});
});