// Typed physical projection only. Existing Core, Store and credential owners
// retain Content custody, approved claims, send/ACK and Unknown responsibility.

///|
#export_name("gcsUploadFailureCode")
pub fn gcs_upload_failure_code(issue : @catalog.ObjectUploadIssue) -> String {
  match issue {
    InvalidBinding => "GcsInvalidUploadBinding"
    InvalidInput => "GcsInvalidUploadInput"
    ForeignBinding => "GcsForeignUploadBinding"
    ContentMismatch => "GcsUploadContentMismatch"
    TargetExists => "GcsUploadTargetExists"
    StaleObservation => "GcsStaleUploadObservation"
    CapacityExceeded => "GcsUploadCapacityExceeded"
    RequiresResumable => "GcsUploadRequiresResumable"
  }
}

///|
#export_name("gcsUploadBinding")
pub fn gcs_upload_binding(
  collection : @catalog.ObjectCollectionBinding,
  command_cid : String,
  permissions : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_entries : Int,
  max_content_bytes : Int,
  max_body_bytes : Int,
  max_path_bytes : Int,
  max_identity_bytes : Int,
) -> Result[@catalog.ObjectUploadBinding, @catalog.ObjectUploadIssue] {
  @catalog.prepare_object_upload_binding(collection, command_cid, permissions, {
    metadata: {
      max_bytes,
      max_nodes,
      max_depth,
      max_metadata_entries: max_entries,
    },
    max_content_bytes,
    max_body_bytes,
    max_path_bytes,
    max_identity_bytes,
  })
}

///|
#export_name("gcsUploadMetadataPath")
pub fn gcs_upload_metadata_path(
  binding : @catalog.ObjectUploadBinding,
  name : String,
) -> Result[String, @catalog.ObjectUploadIssue] {
  @catalog.object_upload_metadata_path(binding, name)
}

///|
#export_name("gcsUploadMetadataMaxBytes")
pub fn gcs_upload_metadata_max_bytes(
  binding : @catalog.ObjectUploadBinding,
) -> Int {
  @catalog.object_upload_metadata_max_bytes(binding)
}

///|
#export_name("gcsUploadObservation")
pub fn gcs_upload_observation(
  binding : @catalog.ObjectUploadBinding,
  name : String,
  status : Int,
  bytes : Bytes,
) -> Result[@catalog.ObjectUploadObservation, @catalog.ObjectUploadIssue] {
  @catalog.admit_object_upload_observation(binding, name, status, bytes)
}

///|
#export_name("gcsUploadPrepareMultipart")
pub fn gcs_upload_prepare_multipart(
  binding : @catalog.ObjectUploadBinding,
  before : @catalog.ObjectUploadObservation,
  content : Bytes,
  content_ref_cid : String,
  content_cid : String,
  media_type : String,
  overwrite_presence : String,
  marker : String,
) -> Result[@catalog.ObjectUploadRequest, @catalog.ObjectUploadIssue] {
  // The private physical ABI carries a closed DATA spelling, not compiler
  // Option<Bool> layout. Never collapse absent into an explicit false.
  let overwrite : Bool? = match overwrite_presence {
    "absent" => None
    "false" => Some(false)
    "true" => Some(true)
    _ => return Err(InvalidInput)
  }
  @catalog.prepare_object_multipart_upload(
    binding, before, content, content_ref_cid, content_cid, media_type, overwrite,
    marker,
  )
}

///|
#export_name("gcsUploadBody")
pub fn gcs_upload_body(
  binding : @catalog.ObjectUploadBinding,
  request : @catalog.ObjectUploadRequest,
) -> Result[Bytes, @catalog.ObjectUploadIssue] {
  @catalog.object_upload_body_for(binding, request)
}

///|
#export_name("gcsUploadProjection")
pub fn gcs_upload_projection(
  binding : @catalog.ObjectUploadBinding,
  request : @catalog.ObjectUploadRequest,
  max_bytes : Int,
) -> Result[String, @catalog.ObjectUploadIssue] {
  @catalog.object_upload_projection_json(binding, request, max_bytes)
}

///|
#export_name("gcsUploadRecheck")
pub fn gcs_upload_recheck(
  binding : @catalog.ObjectUploadBinding,
  request : @catalog.ObjectUploadRequest,
  current : @catalog.ObjectUploadObservation,
) -> Result[Unit, @catalog.ObjectUploadIssue] {
  @catalog.recheck_object_upload(binding, request, current)
}

///|
#export_name("gcsUploadResponseMatches")
pub fn gcs_upload_response_matches(
  binding : @catalog.ObjectUploadBinding,
  request : @catalog.ObjectUploadRequest,
  response : @catalog.ObjectMetadata,
) -> Bool {
  @catalog.object_upload_response_matches(binding, request, response)
}

///|
#export_name("gcsUploadResponseProjection")
pub fn gcs_upload_response_projection(
  binding : @catalog.ObjectUploadBinding,
  request : @catalog.ObjectUploadRequest,
  status : Int,
  body : Bytes,
  max_bytes : Int,
) -> Result[String, @catalog.ObjectUploadIssue] {
  @catalog.object_upload_response_projection_json(
    binding, request, status, body, max_bytes,
  )
}
