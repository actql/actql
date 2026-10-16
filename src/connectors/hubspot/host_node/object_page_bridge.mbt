///|
/// Pure observations remain in their original HubSpot runtime. The Site sends
/// requests and owns current/credential checks; only typed row DATA crosses
/// into the independently admitted Common RowRun.
#export_name("hubspotProjectProperties")
pub fn hubspot_project_properties(
  bytes : Bytes,
  original_object_type : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_properties : Int,
  max_name_units : Int,
) -> Result[@catalog.PropertyCatalog, @catalog.PropertyIssue] {
  @catalog.project_properties(bytes, original_object_type, {
    max_bytes,
    max_nodes,
    max_depth,
    max_properties,
    max_name_units,
  })
}

///|
#export_name("hubspotProjectObjectPage")
pub fn hubspot_project_object_page(
  bytes : Bytes,
  catalog : @catalog.PropertyCatalog,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_columns : Int,
  max_cursor_units : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.ObjectPage, @catalog.ObjectPageIssue] {
  @catalog.project_object_page(bytes, catalog, names, {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_columns,
    max_cursor_units,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("hubspotObjectPageRowsWire")
pub fn hubspot_object_page_rows_wire(
  page : @catalog.ObjectPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.ObjectPageIssue] {
  @catalog.encode_object_page_rows(page, max_bytes, max_nodes, max_depth)
}

///|
#export_name("hubspotObjectPageMetadataJson")
pub fn hubspot_object_page_metadata_json(page : @catalog.ObjectPage) -> String {
  (
    {
      "objectType": page.object_type.to_json(),
      "responseSha256": page.response_sha256.to_json(),
      "rowCount": @catalog.object_page_row_count(page).to_json(),
      "nextAfter": match page.next_after {
        Some(value) => value.to_json()
        None => Json::null()
      },
    } : Json).stringify()
}
