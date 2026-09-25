///|
pub(all) struct TargetObservationLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_identity_bytes : Int
}

///|
pub(all) enum TargetObservationIssue {
  InvalidLimits
  CapacityExceeded
  InvalidRecord
  ForeignTarget
} derive(Eq, Debug)

///|
/// A bounded, target-bound physical observation. This is not an apply permit:
/// current authority, complete Preview admission and write preflight remain
/// independent obligations.
pub struct TargetObservation {
  version_cid : String
  response_sha256 : String
}

///|
pub fn target_observation_version_cid(value : TargetObservation) -> String {
  value.version_cid
}

///|
pub fn target_observation_response_sha256(value : TargetObservation) -> String {
  value.response_sha256
}

///|
pub fn prepare_target_observation(
  request : SingleWriteRequest,
  status : Int,
  bytes : Bytes,
  limits : TargetObservationLimits,
) -> Result[TargetObservation, TargetObservationIssue] {
  if limits.max_bytes < 1 || limits.max_nodes < 1 ||
    limits.max_depth < 1 || limits.max_identity_bytes < 1 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(CapacityExceeded)
  }
  if status != 200 || request.verb != "PATCH" {
    return Err(InvalidRecord)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => CapacityExceeded
          _ => InvalidRecord
        },
      )
  }
  let record = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind is @decode.BudgetExceeded {
          CapacityExceeded
        } else {
          InvalidRecord
        },
      )
  }
  guard @decode.open_object(record) is Ok(object) else {
    return Err(InvalidRecord)
  }
  guard @decode.lookup(object, "Id") is Some(id_value) &&
    @decode.text(id_value) is Ok(record_id) &&
    canonical_write_record_id(record_id) is Some(_) else {
    return Err(InvalidRecord)
  }
  for field in request.projection.fields {
    if @decode.lookup(object, field.name) is None {
      return Err(InvalidRecord)
    }
  }
  let observed_target = match request.projection.operation {
    WriteUpdateById => RecordId(record_id)
    WriteUpsertByExternalId(name) => {
      guard @decode.lookup(object, name) is Some(value) else {
        return Err(InvalidRecord)
      }
      match request.target {
        ExternalText(_) =>
          match @decode.text(value) {
            Ok(text) => ExternalText(text)
            Err(_) => return Err(InvalidRecord)
          }
        ExternalInt(_) =>
          match @decode.int32(value) {
            Ok(number) => ExternalInt(number)
            Err(_) => return Err(InvalidRecord)
          }
        _ => return Err(InvalidRecord)
      }
    }
    WriteCreate => return Err(InvalidRecord)
  }
  let expected = match
    prepare_write_target_identity(
      request.projection,
      request.target,
      request.max_target_bytes,
      limits.max_identity_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidRecord)
  }
  let observed = match
    prepare_write_target_identity(
      request.projection,
      observed_target,
      request.max_target_bytes,
      limits.max_identity_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignTarget)
  }
  if expected.boundary_cid != observed.boundary_cid ||
    expected.scheme_cid != observed.scheme_cid ||
    expected.object_cid != observed.object_cid {
    return Err(ForeignTarget)
  }
  let response_sha256 = @sha.hex(bytes)
  let version_cid = match
    write_target_digest(
      [
        ("object_cid", expected.object_cid),
        ("response_sha256", response_sha256),
        ("version", "actql-salesforce-target-observation/0.1"),
      ],
      limits.max_identity_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(CapacityExceeded)
  }
  Ok({ version_cid, response_sha256, })
}
