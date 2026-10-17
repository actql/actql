///|
#export_name("notionStartReadRow")
pub fn notion_start_read_row(
  binding : @catalog.NotionDataSourceReadContracts,
  page : @catalog.OriginalNotionQueryPage,
  row : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_bytes : Int,
  max_columns : Int,
  max_work : Int,
) -> Result[@catalog.NotionReadRow, @catalog.NotionReadRowIssue] {
  @catalog.start_notion_read_row(binding, page, row, {
    values: { max_nodes, max_depth, max_text_bytes, },
    max_columns,
    max_work,
  })
}

///|
#export_name("notionCompleteReadRowProperty")
pub fn notion_complete_read_row_property(
  row : @catalog.NotionReadRow,
  column : Int,
  page : @catalog.NotionPropertyItemPage,
) -> Result[Unit, @catalog.NotionReadRowIssue] {
  @catalog.complete_notion_read_row_property(row, column, page)
}

///|
#export_name("notionReadRowPendingJson")
pub fn notion_read_row_pending_json(
  row : @catalog.NotionReadRow,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionReadRowIssue] {
  @catalog.notion_read_row_pending_wire(row, max_bytes, max_nodes, max_depth)
}

///|
#export_name("notionReadRowJson")
pub fn notion_read_row_json(
  row : @catalog.NotionReadRow,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionReadRowIssue] {
  @catalog.notion_read_row_wire(row, max_bytes, max_nodes, max_depth)
}
