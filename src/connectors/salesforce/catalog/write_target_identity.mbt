///|
/// An exact provider target for the common Effect Set footprint check. The
/// physical request CID is separate and preserves the original wire spelling.
pub struct WriteTargetIdentity {
  boundary_cid : String
  scheme_cid : String
  object_cid : String
}

///|
pub fn write_target_boundary_cid(value : WriteTargetIdentity) -> String {
  value.boundary_cid
}

///|
pub fn write_target_scheme_cid(value : WriteTargetIdentity) -> String {
  value.scheme_cid
}

///|
pub fn write_target_object_cid(value : WriteTargetIdentity) -> String {
  value.object_cid
}

///|
fn write_target_digest(
  fields : Array[(String, String)],
  max_bytes : Int,
) -> Result[String, WriteCollectionRequestIssue] {
  let writer = @encode.hashing_writer(max_bytes, 64, 2) catch {
    _ => return Err(CapacityExceeded)
  }
  let digest = try {
    @encode.begin_object(writer)
    for (key, value) in fields {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(CapacityExceeded)
  }
  Ok("sha256:" + digest)
}

///|
/// The connection's admitted org, not the instance URL or authored target,
/// defines the provider boundary even for creates without an existing record.
pub fn write_projection_boundary_cid(
  projection : WriteProjection,
  max_identity_bytes : Int,
) -> Result[String, WriteCollectionRequestIssue] {
  if max_identity_bytes < 1 {
    return Err(InvalidLimits)
  }
  let org_id = match canonical_write_record_id(projection.binding.org_id) {
    Some(value) => value
    None => return Err(InvalidTarget)
  }
  write_target_digest(
    [("org_id", org_id), ("version", "actql-salesforce-target-boundary/0.1")],
    max_identity_bytes,
  )
}

///|
/// The org ID must come from the admitted connection, not the authored
/// Effect. Distinct target schemes in one org cannot prove non-overlap: an
/// external ID and a RecordId might still select the same physical record.
pub fn prepare_write_target_identity(
  projection : WriteProjection,
  target : WriteTargetValue,
  max_target_bytes : Int,
  max_identity_bytes : Int,
) -> Result[WriteTargetIdentity, WriteCollectionRequestIssue] {
  if max_target_bytes < 1 || max_identity_bytes < 1 {
    return Err(InvalidLimits)
  }
  let wire_target = match
    collection_target_key(projection, target, max_target_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let canonical_target = match
    collection_overlap_key(projection, target, wire_target) {
    Ok(Some(value)) => value
    Ok(None) | Err(_) => return Err(InvalidTarget)
  }
  let (kind, field, matching) = match projection.operation {
    WriteUpdateById => ("record_id", "Id", "case_safe_18")
    WriteUpsertByExternalId(name) => {
      guard projection.external_target is Some(metadata) else {
        return Err(InvalidTarget)
      }
      let matching = match metadata.native_type {
        "int" => "integer"
        _ =>
          match metadata.case_sensitive {
            Some(true) => "case_sensitive"
            Some(false) => "ascii_case_insensitive"
            None => return Err(InvalidTarget)
          }
      }
      ("external_id", name, matching)
    }
    WriteCreate => return Err(InvalidTarget)
  }
  let boundary_cid = match
    write_projection_boundary_cid(projection, max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let scheme_cid = match
    write_target_digest(
      [
        ("field", field),
        ("kind", kind),
        ("matching", matching),
        ("version", "actql-salesforce-target-scheme/0.1"),
      ],
      max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let object_cid = match
    write_target_digest(
      [
        ("boundary_cid", boundary_cid),
        ("resource", projection.resource),
        ("scheme_cid", scheme_cid),
        ("target", canonical_target),
        ("version", "actql-salesforce-target-object/0.1"),
      ],
      max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ boundary_cid, scheme_cid, object_cid, })
}

///|
/// The private Preview's update/upsert row identity names the provider key.
/// Compare it under the admitted Catalog matching law, not as raw JSON text.
fn write_target_matches_preview_correlation(
  projection : WriteProjection,
  target : WriteTargetValue,
  correlation_wire : String,
  max_target_bytes : Int,
  max_identity_bytes : Int,
) -> Result[Bool, WriteCollectionRequestIssue] {
  if max_identity_bytes < 1 || max_target_bytes < 1 {
    return Err(InvalidLimits)
  }
  let parsed = match
    @source.parse_json(correlation_wire, {
      max_input_bytes: max_identity_bytes,
      max_nodes: 2,
      max_depth: 1,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidTarget)
  }
  let admitted = match
    @decode.admit(parsed, {
      max_nodes: 2,
      max_depth: 1,
      max_string_bytes: max_target_bytes,
      max_total_string_bytes: max_target_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidTarget)
  }
  let preview_target = match (projection.operation, target) {
    (WriteUpdateById, RecordId(_)) =>
      match @decode.text(admitted) {
        Ok(value) => RecordId(value)
        Err(_) => return Err(InvalidTarget)
      }
    (WriteUpsertByExternalId(_), ExternalText(_)) =>
      match @decode.text(admitted) {
        Ok(value) => ExternalText(value)
        Err(_) => return Err(InvalidTarget)
      }
    (WriteUpsertByExternalId(_), ExternalInt(_)) =>
      match @decode.int32(admitted) {
        Ok(value) => ExternalInt(value)
        Err(_) => return Err(InvalidTarget)
      }
    _ => return Err(InvalidTarget)
  }
  let physical = match
    prepare_write_target_identity(
      projection, target, max_target_bytes, max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let preview = match
    prepare_write_target_identity(
      projection, preview_target, max_target_bytes, max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(
    physical.boundary_cid == preview.boundary_cid &&
    physical.scheme_cid == preview.scheme_cid &&
    physical.object_cid == preview.object_cid,
  )
}
