// Pure typed provider boundary. These exports issue no Source, Account,
// credential, grant, physical request or cleanup acknowledgement.

///|
#export_name("sheetsProjectTabs")
pub fn sheets_project_tabs(
  bytes : Bytes,
  spreadsheet_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.SheetTabsPage, @catalog.SheetTabsIssue] {
  @catalog.project_sheet_tabs(bytes, spreadsheet_id, {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("sheetsTabsRowsWire")
pub fn sheets_tabs_rows_wire(
  page : @catalog.SheetTabsPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SheetTabsIssue] {
  @catalog.sheet_tabs_rows_wire(page, names, max_bytes, max_nodes, max_depth)
}

///|
#export_name("sheetsTabsRowCount")
pub fn sheets_tabs_row_count(page : @catalog.SheetTabsPage) -> Int {
  @catalog.sheet_tabs_row_count(page)
}

///|
#export_name("sheetsTabsColumnNames")
pub fn sheets_tabs_column_names() -> Array[String] {
  @catalog.sheet_tabs_column_names()
}

///|
#export_name("sheetsTabsSchemaWire")
pub fn sheets_tabs_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SheetTabsIssue] {
  @catalog.sheet_tabs_schema_wire(max_bytes, max_nodes, max_depth)
}
