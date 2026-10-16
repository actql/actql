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

///|
/// Enumerate the original observed metadata through its existing Catalog owner.
/// Installation must admit every selected contract; no sampled rows infer types.
#export_name("hubspotPropertyCatalogNames")
pub fn hubspot_property_catalog_names(
  catalog : @catalog.PropertyCatalog,
) -> Array[String] {
  @catalog.property_names(catalog)
}

///|
/// The top-level provider record id is the declared Source key, independently
/// of property uniqueness metadata. This is conditional declaration DATA:
/// duplicate record ids still refuse page admission and completion.
#export_name("hubspotObjectRelationFactsWire")
pub fn hubspot_object_relation_facts_wire() -> String {
  "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"
}
