///|
#export_name("hubspotMappingSource")
pub fn hubspot_mapping_source(
  target : String,
  field : String,
  null_behavior : String,
) -> @catalog.MappingSource {
  { target, field, null_behavior, }
}

///|
#export_name("hubspotPrepareExecutionMapping")
pub fn hubspot_prepare_execution_mapping(
  catalog : @catalog.PropertyCatalog,
  connector_id : String,
  manifest_cid : String,
  resource : String,
  kind : Int,
  key : String,
  fields : Array[String],
  sources : Array[@catalog.MappingSource],
  max_properties : Int,
  max_fields : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@catalog.ExecutionMapping, @catalog.MappingIssue] {
  let operation = match (kind, key) {
    (0, "") => @catalog.Create
    (1, "id") => @catalog.Update
    (2, key) if !key.is_empty() && key != "id" => @catalog.Upsert(key)
    _ => return Err(@catalog.InvalidWrite)
  }
  @catalog.prepare_execution_mapping(
    catalog,
    connector_id,
    manifest_cid,
    resource,
    operation,
    fields,
    sources,
    {
      max_properties,
      max_fields,
      max_name_bytes,
      max_bytes,
      max_nodes,
      max_depth,
    },
  )
}

///|
#export_name("hubspotExecutionMappingRef")
pub fn hubspot_execution_mapping_ref(
  value : @catalog.ExecutionMapping,
) -> String {
  value.mapping_ref
}

///|
#export_name("hubspotExecutionMappingCid")
pub fn hubspot_execution_mapping_cid(
  value : @catalog.ExecutionMapping,
) -> String {
  value.mapping_cid
}

///|
#export_name("hubspotExecutionMappingBody")
pub fn hubspot_execution_mapping_body(
  value : @catalog.ExecutionMapping,
) -> String {
  @catalog.execution_mapping_body(value)
}

///|
#export_name("hubspotExecutionMappingFields")
pub fn hubspot_execution_mapping_fields(
  value : @catalog.ExecutionMapping,
) -> Array[String] {
  @catalog.execution_mapping_fields(value)
}

///|
#export_name("hubspotRecheckExecutionMapping")
pub fn hubspot_recheck_execution_mapping(
  value : @catalog.ExecutionMapping,
  current : @catalog.PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, @catalog.PropertyIssue] {
  @catalog.recheck_execution_mapping(value, current, max_properties)
}

///|
#export_name("hubspotPrepareExecutionWriteBody")
pub fn hubspot_prepare_execution_write_body(
  value : @catalog.ExecutionMapping,
  current : @catalog.PropertyCatalog,
  bytes : Bytes,
  max_properties : Int,
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
) -> Result[@catalog.WriteBody, @catalog.MappingIssue] {
  @catalog.prepare_execution_write_body(value, current, bytes, max_properties, {
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
