///|
/// Pure write DATA projection in the original provider runtime. Account,
/// credential, target, Preview and physical request Owners are not bypassed.
#export_name("hubspotPrepareWriteBody")
pub fn hubspot_prepare_write_body(
  catalog : @catalog.PropertyCatalog,
  names : Array[String],
  bytes : Bytes,
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_fields : Int,
  max_name_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_comparison_work : Int,
  max_output_bytes : Int,
  max_output_nodes : Int,
  max_output_depth : Int,
) -> Result[@catalog.WriteBody, @catalog.WriteBodyIssue] {
  @catalog.prepare_write_body(catalog, names, bytes, {
    max_input_bytes,
    max_nodes,
    max_depth,
    max_fields,
    max_name_bytes,
    max_value_nodes,
    max_value_text_bytes,
    max_comparison_work,
    max_output_bytes,
    max_output_nodes,
    max_output_depth,
  })
}

///|
#export_name("hubspotWriteBodyPropertiesJson")
pub fn hubspot_write_body_properties_json(body : @catalog.WriteBody) -> String {
  @catalog.write_body_properties_json(body)
}

///|
#export_name("hubspotWriteBodyValueJson")
pub fn hubspot_write_body_value_json(body : @catalog.WriteBody) -> String {
  @catalog.write_body_value_json(body)
}

///|
#export_name("hubspotWriteBodyPropertyNames")
pub fn hubspot_write_body_property_names(
  body : @catalog.WriteBody,
) -> Array[String] {
  @catalog.write_body_property_names(body)
}

///|
#export_name("hubspotRecheckWriteBody")
pub fn hubspot_recheck_write_body(
  body : @catalog.WriteBody,
  current : @catalog.PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, @catalog.PropertyIssue] {
  @catalog.recheck_write_body(body, current, max_properties)
}
