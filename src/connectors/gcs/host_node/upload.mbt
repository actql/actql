// Private typed DATA bridge. Common retains original admission and execution.

///|
#export_name("gcsUploadDeclarationFailureCode")
pub fn gcs_upload_declaration_failure_code(
  issue : @catalog.ObjectUploadDeclarationIssue,
) -> String {
  match issue {
    InvalidBinding => "GcsInvalidUploadDeclarationBinding"
    InvalidDeclaration => "GcsInvalidUploadDeclaration"
    ConflictingCommand => "GcsUploadDeclarationConflict"
    CapacityExceeded => "GcsUploadDeclarationCapacityExceeded"
  }
}

///|
#export_name("gcsUploadCommandJson")
pub fn gcs_upload_command_json(
  connector_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.ObjectUploadDeclarationIssue] {
  @catalog.object_upload_command_json(connector_id, {
    max_bytes,
    max_nodes,
    max_depth,
  })
}

///|
#export_name("gcsUploadCatalogJson")
pub fn gcs_upload_catalog_json(
  declared_wire : String,
  connector_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.ObjectUploadDeclarationIssue] {
  @catalog.object_upload_catalog_json(declared_wire, connector_id, {
    max_bytes,
    max_nodes,
    max_depth,
  })
}

///|
#export_name("gcsUploadMappingJson")
pub fn gcs_upload_mapping_json(
  binding : @catalog.ObjectCollectionBinding,
  declared_wire : String,
  connector_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.ObjectUploadDeclarationIssue] {
  @catalog.object_upload_mapping_json(binding, declared_wire, connector_id, {
    max_bytes,
    max_nodes,
    max_depth,
  })
}
