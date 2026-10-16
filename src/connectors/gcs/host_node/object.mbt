// Typed ABI projection only. The portable GCS catalog owns provider meaning;
// the existing installed Source/Effect, credential and Store own physical work.

///|
pub enum GcsFailure {
  Metadata(@catalog.ObjectMetadataIssue)
  Request(@catalog.ObjectRequestIssue)
}

///|
#export_name("gcsObjectFailureCode")
pub fn gcs_object_failure_code(issue : GcsFailure) -> String {
  match issue {
    Metadata(issue) =>
      match issue {
        InvalidLimits => "GcsMetadataInvalidLimits"
        BudgetExceeded => "GcsMetadataBudgetExceeded"
        InvalidMetadata => "GcsInvalidObjectMetadata"
        ObjectMismatch => "GcsObjectMetadataMismatch"
      }
    Request(issue) =>
      match issue {
        InvalidBinding => "GcsInvalidObjectBinding"
        InvalidChanges => "GcsInvalidObjectChanges"
        ReservedMetadata => "GcsReservedRequestMetadata"
        ForeignBinding => "GcsForeignObjectBinding"
        StaleObservation => "GcsStaleObjectObservation"
        CapacityExceeded => "GcsObjectRequestCapacityExceeded"
      }
  }
}

///|
#export_name("gcsObjectMetadata")
pub fn gcs_object_metadata(
  bytes : Bytes,
  bucket : String,
  prefix : String,
  name : String?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_entries : Int,
) -> Result[@catalog.ObjectMetadata, GcsFailure] {
  @catalog.admit_object_metadata(bytes, bucket, prefix, name, {
    max_bytes,
    max_nodes,
    max_depth,
    max_metadata_entries: max_entries,
  }).map_err(Metadata)
}

///|
#export_name("gcsObjectMetadataJson")
pub fn gcs_object_metadata_json(
  original : @catalog.ObjectMetadata,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_entries : Int,
) -> Result[String, GcsFailure] {
  @catalog.object_metadata_logical_json(original, {
    max_bytes,
    max_nodes,
    max_depth,
    max_metadata_entries: max_entries,
  }).map_err(Metadata)
}

///|
#export_name("gcsObjectMutationBinding")
pub fn gcs_object_mutation_binding(
  kind : String,
  bucket : String,
  prefix : String,
  catalog_cid : String,
  installation_cid : String,
  contract_cid : String,
  permissions : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_entries : Int,
  max_path_bytes : Int,
  max_body_bytes : Int,
  max_identity_bytes : Int,
) -> Result[@catalog.ObjectMutationBinding, GcsFailure] {
  let kind : @catalog.ObjectMutationKind = match kind {
    "patch_metadata" => PatchMetadata
    "delete" => DeleteObject
    _ => return Err(Request(InvalidBinding))
  }
  @catalog.prepare_object_mutation_binding(
    kind,
    bucket,
    prefix,
    catalog_cid,
    installation_cid,
    contract_cid,
    permissions,
    {
      metadata: {
        max_bytes,
        max_nodes,
        max_depth,
        max_metadata_entries: max_entries,
      },
      max_path_bytes,
      max_body_bytes,
      max_identity_bytes,
    },
  ).map_err(Request)
}

///|
#export_name("gcsObjectPreparePatch")
pub fn gcs_object_prepare_patch(
  binding : @catalog.ObjectMutationBinding,
  original : @catalog.ObjectMetadata,
  changes : Bytes,
  marker : String,
) -> Result[@catalog.ObjectMutationRequest, GcsFailure] {
  @catalog.prepare_object_metadata_patch(binding, original, changes, marker).map_err(
    Request,
  )
}

///|
#export_name("gcsObjectPrepareDelete")
pub fn gcs_object_prepare_delete(
  binding : @catalog.ObjectMutationBinding,
  original : @catalog.ObjectMetadata,
) -> Result[@catalog.ObjectMutationRequest, GcsFailure] {
  @catalog.prepare_object_delete(binding, original).map_err(Request)
}

///|
#export_name("gcsObjectRequestProjection")
pub fn gcs_object_request_projection(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
  max_bytes : Int,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_projection_json(binding, request, max_bytes).map_err(
    Request,
  )
}

///|
#export_name("gcsObjectRequestBody")
pub fn gcs_object_request_body(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_body_for(binding, request).map_err(Request)
}

///|
#export_name("gcsObjectRequestChanges")
pub fn gcs_object_request_changes(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_changes_json(binding, request).map_err(Request)
}

///|
#export_name("gcsObjectRecheck")
pub fn gcs_object_recheck(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
  current : @catalog.ObjectMetadata,
) -> Result[Unit, GcsFailure] {
  @catalog.recheck_object_mutation(binding, request, current).map_err(Request)
}
