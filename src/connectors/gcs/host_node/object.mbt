// Typed ABI projection only. The portable GCS catalog owns provider meaning;
// the existing installed Source/Effect, credential and Store own physical work.

///|
#export_name("gcsObjectRestoreMutationValue")
pub fn gcs_object_restore_mutation_value(
  binding : @catalog.ObjectMutationBinding,
  name : String,
  status : Int,
  headers : Array[(String, String)],
  response : Bytes,
  response_sha256 : String,
  changes : Bytes,
  body : String,
  request_cid : String,
) -> Result[@catalog.ObjectMutationRequest, GcsFailure] {
  @catalog.restore_object_mutation_value_wire(
    binding, name, status, headers, response, response_sha256, changes, body, request_cid,
  ).map_err(issue => Request(issue))
}

///|
#export_name("gcsObjectResponseMatches")
pub fn gcs_object_response_matches(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
  observed : @catalog.ObjectMetadata,
) -> Bool {
  @catalog.object_mutation_response_matches(binding, request, observed)
}

///|
#export_name("gcsObjectResponseProjection")
pub fn gcs_object_response_projection(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
  status : Int,
  body : Bytes,
  max_bytes : Int,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_response_projection_json(
    binding, request, status, body, max_bytes,
  ).map_err(issue => Request(issue))
}

///|
pub enum GcsFailure {
  Metadata(@catalog.ObjectMetadataIssue)
  Request(@catalog.ObjectRequestIssue)
  TargetRead(@catalog.ObjectTargetReadIssue)
}

///|
#export_name("gcsObjectFailureCode")
pub fn gcs_object_failure_code(issue : GcsFailure) -> String {
  match issue {
    TargetRead(issue) =>
      match issue {
        InvalidName => "GcsInvalidObjectTargetName"
        InvalidResponse => "GcsInvalidObjectTargetObservation"
        CapacityExceeded => "GcsObjectTargetCapacityExceeded"
        Metadata(issue) => gcs_object_failure_code(Metadata(issue))
      }
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
#export_name("gcsObjectMutationKind")
pub fn gcs_object_mutation_kind(
  binding : @catalog.ObjectMutationBinding,
) -> String {
  match @catalog.object_mutation_kind(binding) {
    PatchMetadata => "patch_metadata"
    DeleteObject => "delete"
  }
}

///|
#export_name("gcsObjectMetadataPath")
pub fn gcs_object_metadata_path(
  binding : @catalog.ObjectMutationBinding,
  name : String,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_metadata_path(binding, name).map_err(issue => {
    TargetRead(issue)
  })
}

///|
#export_name("gcsObjectMetadataMaxBytes")
pub fn gcs_object_metadata_max_bytes(
  binding : @catalog.ObjectMutationBinding,
) -> Int {
  @catalog.object_mutation_metadata_max_bytes(binding)
}

///|
#export_name("gcsObjectTargetObservation")
pub fn gcs_object_target_observation(
  binding : @catalog.ObjectMutationBinding,
  name : String,
  status : Int,
  body : Bytes,
  headers : Array[(String, String)],
) -> Result[@catalog.ObjectMetadata, GcsFailure] {
  @catalog.admit_object_mutation_target_observation(
    binding, name, status, body, headers,
  ).map_err(issue => TargetRead(issue))
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
  }).map_err(issue => Metadata(issue))
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
  }).map_err(issue => Metadata(issue))
}

///|
#export_name("gcsObjectMetadataPage")
pub fn gcs_object_metadata_page(
  bytes : Bytes,
  bucket : String,
  prefix : String,
  max_items : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_entries : Int,
) -> Result[@catalog.ObjectMetadataPage, GcsFailure] {
  @catalog.admit_object_metadata_page(bytes, bucket, prefix, max_items, {
    max_bytes,
    max_nodes,
    max_depth,
    max_metadata_entries: max_entries,
  }).map_err(issue => Metadata(issue))
}

///|
#export_name("gcsObjectMetadataPageCount")
pub fn gcs_object_metadata_page_count(
  page : @catalog.ObjectMetadataPage,
) -> Int {
  @catalog.object_metadata_page_count(page)
}

///|
#export_name("gcsObjectMetadataPageNextToken")
pub fn gcs_object_metadata_page_next_token(
  page : @catalog.ObjectMetadataPage,
) -> String? {
  @catalog.object_metadata_page_next_token(page)
}

///|
#export_name("gcsObjectMetadataPageRowJson")
pub fn gcs_object_metadata_page_row_json(
  page : @catalog.ObjectMetadataPage,
  index : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, GcsFailure] {
  @catalog.object_metadata_page_row_json(page, index, max_bytes, {
    max_bytes,
    max_nodes,
    max_depth,
    max_metadata_entries: max_nodes,
  }).map_err(issue => Metadata(issue))
}

///|
#export_name("gcsObjectListingPrefix")
pub fn gcs_object_listing_prefix(
  installed_prefix : String,
  request : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, GcsFailure] {
  @catalog.object_listing_prefix(installed_prefix, request, {
    max_bytes,
    max_nodes,
    max_depth,
    max_metadata_entries: max_nodes,
  }).map_err(issue => Metadata(issue))
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
  ).map_err(issue => Request(issue))
}

///|
#export_name("gcsObjectPreparePatch")
pub fn gcs_object_prepare_patch(
  binding : @catalog.ObjectMutationBinding,
  original : @catalog.ObjectMetadata,
  changes : Bytes,
  marker : String,
) -> Result[@catalog.ObjectMutationRequest, GcsFailure] {
  @catalog.prepare_object_metadata_patch(binding, original, changes, marker).map_err(issue => {
      Request(issue)
    },
  )
}

///|
#export_name("gcsObjectPrepareEffectPatch")
pub fn gcs_object_prepare_effect_patch(
  binding : @catalog.ObjectMutationBinding,
  original : @catalog.ObjectMetadata,
  changes : Bytes,
  marker : String,
) -> Result[@catalog.ObjectMutationRequest, GcsFailure] {
  @catalog.prepare_object_metadata_patch_value_wire(
    binding, original, changes, marker,
  ).map_err(issue => Request(issue))
}

///|
#export_name("gcsObjectCheckPatchInput")
pub fn gcs_object_check_patch_input(
  binding : @catalog.ObjectMutationBinding,
  changes : Bytes,
  marker : String,
  effect_wire : Bool,
) -> Result[Unit, GcsFailure] {
  @catalog.check_object_metadata_patch_input(
    binding, changes, marker, effect_wire,
  ).map_err(issue => Request(issue))
}

///|
#export_name("gcsObjectPrepareDelete")
pub fn gcs_object_prepare_delete(
  binding : @catalog.ObjectMutationBinding,
  original : @catalog.ObjectMetadata,
) -> Result[@catalog.ObjectMutationRequest, GcsFailure] {
  @catalog.prepare_object_delete(binding, original).map_err(issue => {
    Request(issue)
  })
}

///|
#export_name("gcsObjectRequestProjection")
pub fn gcs_object_request_projection(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
  max_bytes : Int,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_projection_json(binding, request, max_bytes).map_err(issue => {
      Request(issue)
    },
  )
}

///|
#export_name("gcsObjectPatchEffectTarget")
pub fn gcs_object_patch_effect_target(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
  max_bytes : Int,
) -> Result[String, GcsFailure] {
  @catalog.object_metadata_patch_effect_target_json(binding, request, max_bytes).map_err(issue => {
      Request(issue)
    },
  )
}

///|
#export_name("gcsObjectRequestBody")
pub fn gcs_object_request_body(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_body_for(binding, request).map_err(issue => {
    Request(issue)
  })
}

///|
#export_name("gcsObjectRequestChanges")
pub fn gcs_object_request_changes(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
) -> Result[String, GcsFailure] {
  @catalog.object_mutation_changes_json(binding, request).map_err(issue => {
    Request(issue)
  })
}

///|
#export_name("gcsObjectRecheck")
pub fn gcs_object_recheck(
  binding : @catalog.ObjectMutationBinding,
  request : @catalog.ObjectMutationRequest,
  current : @catalog.ObjectMetadata,
) -> Result[Unit, GcsFailure] {
  @catalog.recheck_object_mutation(binding, request, current).map_err(issue => {
    Request(issue)
  })
}
