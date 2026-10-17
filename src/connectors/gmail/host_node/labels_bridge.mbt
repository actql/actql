///|
#export_name("gmailProjectLabelList")
pub fn gmail_project_label_list(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.GmailLabelListPage, @catalog.GmailLabelListIssue] {
  @catalog.project_gmail_label_list(body, {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("gmailLabelListRowsWire")
pub fn gmail_label_list_rows_wire(
  page : @catalog.GmailLabelListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.GmailLabelListIssue] {
  @catalog.gmail_label_list_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("gmailLabelListMetadataJson")
pub fn gmail_label_list_metadata_json(
  page : @catalog.GmailLabelListPage,
) -> String {
  ({ "rowCount": @catalog.gmail_label_list_row_count(page).to_json() } : Json).stringify()
}

///|
#export_name("gmailLabelListColumnNames")
pub fn gmail_label_list_column_names() -> Array[String] {
  @catalog.gmail_label_list_column_names()
}

///|
#export_name("gmailLabelListSchemaWire")
pub fn gmail_label_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.GmailLabelListIssue] {
  @catalog.gmail_label_list_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("gmailLabelListRelationFactsWire")
pub fn gmail_label_list_relation_facts_wire() -> String {
  @catalog.gmail_label_list_facts_wire()
}
