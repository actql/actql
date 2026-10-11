///|
/// Exact read material for the target of the same admitted Local update
/// candidate. This is neither an apply request nor Provider entry permission.
pub struct LocalTargetReadRequest {
  original : SingleWriteRequest
  binding : LocalCatalogObservationBinding
  cid : String
}

///|
pub fn prepare_local_target_read_request(
  original : SingleWriteRequest,
  current : LocalCatalogObservationBinding,
  current_catalog : CatalogObservation,
  credential_org_id : String,
  max_identity_bytes : Int,
) -> Result[LocalTargetReadRequest, WriteRequestIssue] {
  if max_identity_bytes < 1 || max_identity_bytes > 1000000 {
    return Err(InvalidLimits)
  }
  if !single_write_request_matches_local_binding(original, current) ||
    !catalog_observation_matches_local_binding(current_catalog, current) ||
    credential_org_id != current.org_id ||
    original.verb != "PATCH" ||
    !(original.kind is SingleUpdateById(_)) ||
    recheck_single_write_request(original, current_catalog) is Err(_) {
    return Err(InvalidTarget)
  }
  if !current.resource_origin.has_prefix("https://") ||
    current.resource_origin.length() <= 8 {
    return Err(InvalidOrigin)
  }
  // The existing request identity domain describes REST bytes, independently
  // of Remote/Local authority. Derive GET from the admitted target, never from
  // a separate caller path or mutation body supplied after checking.
  let writer = @encode.hashing_writer(max_identity_bytes, 16, 2) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    observation_field(writer, "body", "")
    observation_field(writer, "method", "GET")
    observation_field(writer, "path", original.path)
    observation_field(writer, "resource_origin", current.resource_origin)
    observation_field(writer, "version", "actql-salesforce-rest-request/0.1")
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok({ original, binding: current, cid: "sha256:" + digest, })
}

///|
pub fn local_target_read_request_cid(
  request : LocalTargetReadRequest,
) -> String {
  request.cid
}

///|
pub fn local_target_read_request_path(
  request : LocalTargetReadRequest,
) -> String {
  request.original.path
}

///|
pub fn local_target_read_request_binding(
  request : LocalTargetReadRequest,
) -> LocalCatalogObservationBinding {
  request.binding
}

///|
pub fn local_target_read_request_candidate(
  request : LocalTargetReadRequest,
) -> SingleWriteRequest {
  request.original
}
