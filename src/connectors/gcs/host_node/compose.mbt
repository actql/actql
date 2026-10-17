// Typed projection of the existing portable GCS Owner, never a send issuer.

///|
#export_name("gcsComposeFailureCode")
pub fn gcs_compose_failure_code(issue : @catalog.ObjectUploadIssue) -> String {
  match issue {
    InvalidBinding => "GcsInvalidComposeBinding"
    InvalidInput => "GcsInvalidComposeInput"
    ForeignBinding => "GcsForeignComposeBinding"
    ContentMismatch => "GcsComposeContentMismatch"
    TargetExists => "GcsComposeTargetExists"
    StaleObservation => "GcsStaleComposeObservation"
    CapacityExceeded => "GcsComposeCapacityExceeded"
    RequiresResumable => "GcsComposeRequiresResumable"
  }
}

///|
#export_name("gcsComposeBinding")
pub fn gcs_compose_binding(
  target : @catalog.ObjectUploadBinding,
  max_sources : Int,
  max_result_bytes : Int64,
) -> Result[@catalog.ObjectComposeBinding, @catalog.ObjectUploadIssue] {
  @catalog.prepare_object_compose_binding(target, max_sources, max_result_bytes)
}

///|
#export_name("gcsComposePrepare")
pub fn gcs_compose_prepare(
  binding : @catalog.ObjectComposeBinding,
  before : @catalog.ObjectUploadObservation,
  sources : Array[@catalog.ObjectMetadata],
  marker : String,
) -> Result[@catalog.ObjectComposeRequest, @catalog.ObjectUploadIssue] {
  @catalog.prepare_object_compose(binding, before, sources, marker)
}

///|
#export_name("gcsComposeProjection")
pub fn gcs_compose_projection(
  binding : @catalog.ObjectComposeBinding,
  request : @catalog.ObjectComposeRequest,
  max_bytes : Int,
) -> Result[String, @catalog.ObjectUploadIssue] {
  @catalog.object_compose_projection_json(binding, request, max_bytes)
}

///|
#export_name("gcsComposeBody")
pub fn gcs_compose_body(
  binding : @catalog.ObjectComposeBinding,
  request : @catalog.ObjectComposeRequest,
) -> Result[String, @catalog.ObjectUploadIssue] {
  @catalog.object_compose_body_for(binding, request)
}

///|
#export_name("gcsComposeRecheck")
pub fn gcs_compose_recheck(
  binding : @catalog.ObjectComposeBinding,
  request : @catalog.ObjectComposeRequest,
  current : @catalog.ObjectUploadObservation,
  sources : Array[@catalog.ObjectMetadata],
) -> Result[Unit, @catalog.ObjectUploadIssue] {
  @catalog.recheck_object_compose(binding, request, current, sources)
}

///|
#export_name("gcsComposeResponseMatches")
pub fn gcs_compose_response_matches(
  binding : @catalog.ObjectComposeBinding,
  request : @catalog.ObjectComposeRequest,
  response : @catalog.ObjectMetadata,
) -> Bool {
  @catalog.object_compose_response_matches(binding, request, response)
}

///|
#export_name("gcsComposeResponseProjection")
pub fn gcs_compose_response_projection(
  binding : @catalog.ObjectComposeBinding,
  request : @catalog.ObjectComposeRequest,
  status : Int,
  body : Bytes,
  max_bytes : Int,
) -> Result[String, @catalog.ObjectUploadIssue] {
  @catalog.object_compose_response_projection_json(
    binding, request, status, body, max_bytes,
  )
}
