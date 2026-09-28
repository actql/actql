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
  before_value_wire : String
  source_path : String
  source_body : String
  source_catalog_cid : String
  source_boundary_cid : String
  source_scheme_cid : String
  source_object_cid : String
}

///|
/// Provider-specific row facts for the common private Effect Preview.
/// This records no apply authority and does not replace plan verification.
pub struct TargetPreviewRow {
  target_row_identity_wire : String
  target_guard_cid : String
  before_value_wire : String
  after_value_wire : String
  intended_changes_wire : String
}

///|
pub fn target_preview_row_target_wire(value : TargetPreviewRow) -> String {
  value.target_row_identity_wire
}

///|
pub fn target_preview_row_guard_cid(value : TargetPreviewRow) -> String {
  value.target_guard_cid
}

///|
pub fn target_preview_row_before_wire(value : TargetPreviewRow) -> String {
  value.before_value_wire
}

///|
pub fn target_preview_row_after_wire(value : TargetPreviewRow) -> String {
  value.after_value_wire
}

///|
pub fn target_preview_row_changes_wire(value : TargetPreviewRow) -> String {
  value.intended_changes_wire
}

///|
pub fn prepare_observed_target_preview_row(
  request : SingleWriteRequest,
  observation : TargetObservation,
  max_identity_bytes : Int,
) -> Result[TargetPreviewRow, TargetObservationIssue] {
  if max_identity_bytes < 1 {
    return Err(InvalidLimits)
  }
  let target = match
    prepare_write_target_identity(
      request.projection,
      request.target,
      request.max_target_bytes,
      max_identity_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidRecord)
  }
  if request.verb != "PATCH" ||
    request.path != observation.source_path ||
    request.body != observation.source_body ||
    request.projection.observation_cid != observation.source_catalog_cid ||
    target.boundary_cid != observation.source_boundary_cid ||
    target.scheme_cid != observation.source_scheme_cid ||
    target.object_cid != observation.source_object_cid {
    return Err(ForeignTarget)
  }
  let output = @encode.writer(max_identity_bytes, 2, 1) catch {
    _ => return Err(CapacityExceeded)
  }
  try {
    match request.target {
      RecordId(value) | ExternalText(value) =>
        @encode.string_value(output, value)
      ExternalInt(value) => @encode.number_value(output, value.to_double())
      NoWriteTarget => return Err(InvalidRecord)
    }
  } catch {
    _ => return Err(CapacityExceeded)
  }
  let target_row_identity_wire = @encode.finish(output) catch {
    _ => return Err(CapacityExceeded)
  }
  Ok({
    target_row_identity_wire,
    target_guard_cid: observation.version_cid,
    before_value_wire: observation.before_value_wire,
    after_value_wire: request.body,
    intended_changes_wire: request.body,
  })
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
/// Return the canonical, typed projection of the observed writable fields.
/// The full HTTP response remains physical evidence, not a Preview value.
pub fn target_observation_before_value_wire(
  value : TargetObservation,
) -> String {
  value.before_value_wire
}

///|
pub fn prepare_target_observation(
  request : SingleWriteRequest,
  status : Int,
  bytes : Bytes,
  limits : TargetObservationLimits,
) -> Result[TargetObservation, TargetObservationIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_identity_bytes < 1 {
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
  let ordered = request.projection.fields.copy()
  ordered.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  let output = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(CapacityExceeded)
  }
  @encode.begin_object(output) catch {
    _ => return Err(CapacityExceeded)
  }
  for field in ordered {
    guard @decode.lookup(object, field.name) is Some(cursor) else {
      return Err(InvalidRecord)
    }
    @encode.key(output, field.name) catch {
      _ => return Err(CapacityExceeded)
    }
    match emit_write_cell(output, cursor, field, observed=true) {
      Ok(_) => ()
      Err(BudgetExceeded) => return Err(CapacityExceeded)
      Err(_) => return Err(InvalidRecord)
    }
  }
  @encode.end_object(output) catch {
    _ => return Err(CapacityExceeded)
  }
  let before_value_wire = @encode.finish(output) catch {
    _ => return Err(CapacityExceeded)
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
  Ok({
    version_cid,
    response_sha256,
    before_value_wire,
    source_path: request.path,
    source_body: request.body,
    source_catalog_cid: request.projection.observation_cid,
    source_boundary_cid: expected.boundary_cid,
    source_scheme_cid: expected.scheme_cid,
    source_object_cid: expected.object_cid,
  })
}
