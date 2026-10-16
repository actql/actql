// Typed Connector DATA projection. Common's original StoreCommandBinding and
// installed ReferenceIssuer remain the sole admission/custody receiver.

///|
#export_name("gcsCollectionFailureCode")
pub fn gcs_collection_failure_code(
  issue : @catalog.ObjectCollectionIssue,
) -> String {
  match issue {
    InvalidBinding => "GcsInvalidCollectionBinding"
    CapacityExceeded => "GcsCollectionCapacityExceeded"
    ForeignBinding => "GcsForeignCollectionBinding"
  }
}

///|
#export_name("gcsCollectionBinding")
pub fn gcs_collection_binding(
  project : String,
  bucket : String,
  prefix : String,
  target_ref : String,
  resource_kind : String,
  catalog_cid : String,
  installation_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@catalog.ObjectCollectionBinding, @catalog.ObjectCollectionIssue] {
  @catalog.prepare_object_collection_binding(
    project,
    bucket,
    prefix,
    target_ref,
    resource_kind,
    catalog_cid,
    installation_cid,
    { max_bytes, max_nodes, max_depth, },
  )
}

///|
#export_name("gcsCollectionIdentityJson")
pub fn gcs_collection_identity_json(
  binding : @catalog.ObjectCollectionBinding,
) -> String {
  @catalog.object_collection_identity_json(binding)
}

///|
#export_name("gcsCollectionIdentityCid")
pub fn gcs_collection_identity_cid(
  binding : @catalog.ObjectCollectionBinding,
) -> String {
  @catalog.object_collection_identity_cid(binding)
}

///|
#export_name("gcsCollectionResourceJson")
pub fn gcs_collection_resource_json(
  binding : @catalog.ObjectCollectionBinding,
) -> String {
  @catalog.object_collection_resource_json(binding)
}

///|
#export_name("gcsCollectionCheckBinding")
pub fn gcs_collection_check_binding(
  original : @catalog.ObjectCollectionBinding,
  selected : @catalog.ObjectCollectionBinding,
  installation_cid : String,
  target_ref : String,
) -> Result[Unit, @catalog.ObjectCollectionIssue] {
  @catalog.check_object_collection_binding(
    original, selected, installation_cid, target_ref,
  )
}
