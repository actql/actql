///|
/// Pure original response-envelope DATA; no Source or physical receipt issue.
#export_name("clientProgramRowSourceProjectJsonPage")
pub fn client_program_row_source_project_json_page(
  bytes : Bytes,
  items_path : Array[String],
  cursor_present : Bool,
  cursor_path : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
) -> Result[
  @client_row_source_host.RowSourceJsonPage,
  @client_row_source_host.RowSourceJsonPageIssue,
] {
  @client_row_source_host.project_row_source_json_page(
    bytes, items_path, cursor_present, cursor_path, max_bytes, max_nodes, max_depth,
    max_rows, max_cursor_bytes,
  )
}

///|
#export_name("clientProgramRowSourceJsonPageRowsWire")
pub fn client_program_row_source_json_page_rows_wire(
  value : @client_row_source_host.RowSourceJsonPage,
) -> String {
  @client_row_source_host.row_source_json_page_rows_wire(value)
}

///|
#export_name("clientProgramRowSourceJsonPageRowCount")
pub fn client_program_row_source_json_page_row_count(
  value : @client_row_source_host.RowSourceJsonPage,
) -> Int {
  @client_row_source_host.row_source_json_page_row_count(value)
}

///|
#export_name("clientProgramRowSourceJsonPageHasNextCursor")
pub fn client_program_row_source_json_page_has_next_cursor(
  value : @client_row_source_host.RowSourceJsonPage,
) -> Bool {
  @client_row_source_host.row_source_json_page_has_next_cursor(value)
}

///|
#export_name("clientProgramRowSourceJsonPageNextCursor")
pub fn client_program_row_source_json_page_next_cursor(
  value : @client_row_source_host.RowSourceJsonPage,
) -> Result[String, @client_row_source_host.RowSourceJsonPageIssue] {
  @client_row_source_host.row_source_json_page_next_cursor(value)
}

///|
#export_name("clientProgramRowSourceProjectTypedJsonPage")
pub fn client_program_row_source_project_typed_json_page(
  bytes : Bytes,
  items_path : Array[String],
  cursor_present : Bool,
  cursor_path : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
) -> Result[
  @client_row_source_host.RowSourceProjectedJsonPage,
  @client_row_source_host.RowSourceJsonPageIssue,
] {
  @client_row_source_host.project_row_source_typed_json_page(
    bytes, items_path, cursor_present, cursor_path, max_bytes, max_nodes, max_depth,
    max_rows, max_cursor_bytes,
  )
}

///|
#export_name("clientProgramRowSourceJsonPageOriginal")
pub fn client_program_row_source_json_page_original(
  page : @client_row_source_host.RowSourceJsonPage,
) -> @client_row_source_host.RowSourceProjectedJsonPage {
  @client_row_source_host.row_source_json_page_original(page)
}

///|
#export_name("clientProgramRowSourceTypedJsonPageRowCount")
pub fn client_program_row_source_typed_json_page_row_count(
  page : @client_row_source_host.RowSourceProjectedJsonPage,
) -> Int {
  @client_row_source_host.row_source_typed_json_page_row_count(page)
}

///|
#export_name("clientProgramRowSourceTypedJsonPageHasNextCursor")
pub fn client_program_row_source_typed_json_page_has_next_cursor(
  page : @client_row_source_host.RowSourceProjectedJsonPage,
) -> Bool {
  @client_row_source_host.row_source_typed_json_page_has_next_cursor(page)
}

///|
#export_name("clientProgramRowSourceTypedJsonPageNextCursor")
pub fn client_program_row_source_typed_json_page_next_cursor(
  page : @client_row_source_host.RowSourceProjectedJsonPage,
) -> Result[String, @client_row_source_host.RowSourceJsonPageIssue] {
  @client_row_source_host.row_source_typed_json_page_next_cursor(page)
}

///|
#export_name("clientProgramRowSourceAcceptChargedProjectedPage")
pub fn client_program_row_source_accept_charged_projected_page(
  run : @client_row_source_host.RowRun,
  charge : @client_row_source_host.RowPageCharge,
  page : @client_row_source_host.RowSourceProjectedJsonPage,
) -> Result[Int, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.accept_charged_row_run_projected_page(
    run, charge, page,
  )
}
