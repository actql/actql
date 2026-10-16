///|
/// Only schema DATA crosses into the independently compiled Common declaration
/// Owner. The original property catalog stays in this provider runtime.
#export_name("hubspotObjectSchemaWire")
pub fn hubspot_object_schema_wire(
  catalog : @catalog.PropertyCatalog,
  names : Array[String],
  max_columns : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.ObjectPageIssue] {
  @catalog.object_schema_wire(
    catalog, names, max_columns, max_name_bytes, max_bytes, max_nodes, max_depth,
  )
}
