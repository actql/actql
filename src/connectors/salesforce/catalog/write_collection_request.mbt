///|
pub(all) struct WriteCollectionRequestLimits {
  max_path_bytes : Int
  max_target_bytes : Int
  max_body_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
} derive(Eq, Debug)

///|
pub(all) enum WriteCollectionRequestIssue {
  InvalidLimits
  InvalidVersion
  InvalidRows
  MixedProjection
  InvalidTarget
  DuplicateRow
  DuplicateTarget
  InvalidBody
  CapacityExceeded
} derive(Eq, Debug)

///|
pub(all) struct WriteCollectionItem {
  row_preview_cid : String
  body : WriteBody
  target : WriteTargetValue
}

///|
/// Bounded physical request material for rows of one already admitted member.
/// This is not an Effect dispatch permit. The apply controller must retain
/// exact row identities, current authorization, and the durable send record.
pub struct WriteCollectionRequest {
  verb : String
  path : String
  body : String
  kind : WriteCollectionKind
  projection : WriteProjection
  row_preview_cids : Array[String]
}

///|
pub fn write_collection_request_method(
  value : WriteCollectionRequest,
) -> String {
  value.verb
}

///|
pub fn write_collection_request_path(value : WriteCollectionRequest) -> String {
  value.path
}

///|
pub fn write_collection_request_body(value : WriteCollectionRequest) -> String {
  value.body
}

///|
pub fn write_collection_request_grant_operation(
  value : WriteCollectionRequest,
) -> String {
  match value.kind {
    CollectionCreate => "salesforce:record:create"
    CollectionUpdate => "salesforce:record:update"
    CollectionUpsert => "salesforce:record:upsert"
  }
}

///|
pub fn recheck_write_collection_request(
  value : WriteCollectionRequest,
  current : CatalogObservation,
) -> Result[Unit, WriteProjectionIssue] {
  recheck_write_projection(value.projection, current)
}

///|
pub fn write_collection_request_matches_site_scope(
  value : WriteCollectionRequest,
  tenant : String,
  principal : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
) -> Bool {
  write_binding_matches_site_scope(
    value.projection.binding,
    tenant,
    principal,
    environment,
    site_key,
    site_generation,
    connector_registration,
    connector_revision,
    resource_origin,
    run_invocation_cid,
    dispatch_request_cid,
  )
}

///|
pub fn write_collection_request_row_count(
  value : WriteCollectionRequest,
) -> Int {
  value.row_preview_cids.length()
}

///|
pub fn write_collection_request_row_cid(
  value : WriteCollectionRequest,
  index : Int,
) -> String? {
  value.row_preview_cids.get(index)
}

///|
/// Bind the physical REST bytes and their ordered Preview-row correlation.
/// A byte-identical body with a different member row inventory is a distinct
/// batch request for ledger and response-mapping purposes.
pub fn write_collection_request_cid(
  value : WriteCollectionRequest,
  resource_origin : String,
  max_wire_bytes : Int,
) -> Result[String, WriteRequestIssue] {
  if max_wire_bytes < 1 || max_wire_bytes > 1000000 {
    return Err(InvalidLimits)
  }
  if !resource_origin.has_prefix("https://") || resource_origin.length() <= 8 {
    return Err(InvalidOrigin)
  }
  let writer = @encode.hashing_writer(max_wire_bytes, 1000, 3) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    @encode.key(writer, "body")
    @encode.string_value(writer, value.body)
    @encode.key(writer, "method")
    @encode.string_value(writer, value.verb)
    @encode.key(writer, "path")
    @encode.string_value(writer, value.path)
    @encode.key(writer, "resource_origin")
    @encode.string_value(writer, resource_origin)
    @encode.key(writer, "row_preview_cids")
    @encode.begin_array(writer)
    for cid in value.row_preview_cids {
      @encode.string_value(writer, cid)
    }
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-salesforce-collection-request/0.1")
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok("sha256:" + digest)
}

///|
fn collection_target_key(
  projection : WriteProjection,
  target : WriteTargetValue,
  max_target_bytes : Int,
) -> Result[String?, WriteCollectionRequestIssue] {
  match (projection.operation, target) {
    (WriteCreate, NoWriteTarget) => Ok(None)
    (WriteUpdateById, RecordId(id)) => {
      if !write_record_id_valid(id) {
        return Err(InvalidTarget)
      }
      Ok(Some(id))
    }
    (WriteUpsertByExternalId(_), ExternalText(text)) => {
      guard projection.external_target is Some(field) &&
        (field.native_type == "string" || field.native_type == "email") else {
        return Err(InvalidTarget)
      }
      let normalized = match @canonical.normalize_nfc(text) {
        Ok(value) => value
        Err(_) => return Err(InvalidTarget)
      }
      if normalized.is_empty() ||
        @scalar.admit_utf8_length(normalized, max_target_bytes) is Err(_) {
        return Err(InvalidTarget)
      }
      Ok(Some(normalized))
    }
    (WriteUpsertByExternalId(_), ExternalInt(value)) => {
      let rendered = value.to_string()
      guard projection.external_target is Some(field) &&
        field.native_type == "int" &&
        rendered.length() <= max_target_bytes else {
        return Err(InvalidTarget)
      }
      Ok(Some(rendered))
    }
    _ => Err(InvalidTarget)
  }
}

///|
/// A collection is one member on one bound connection and resource. This key
/// is for overlap admission only; the separately retained target is sent on
/// the wire without changing its spelling.
fn collection_overlap_key(
  projection : WriteProjection,
  target : WriteTargetValue,
  wire_target : String?,
) -> Result[String?, WriteCollectionRequestIssue] {
  match (projection.operation, target, wire_target) {
    (WriteCreate, NoWriteTarget, None) => Ok(None)
    (WriteUpdateById, RecordId(id), Some(_)) =>
      match canonical_write_record_id(id) {
        Some(value) => Ok(Some(value))
        None => Err(InvalidTarget)
      }
    (WriteUpsertByExternalId(_), ExternalText(_), Some(value)) => {
      guard projection.external_target is Some(field) else {
        return Err(InvalidTarget)
      }
      match field.case_sensitive {
        Some(true) => Ok(Some(value))
        Some(false) => {
          for character in value.iter() {
            if character > '\u{7f}' {
              return Err(InvalidTarget)
            }
          }
          Ok(Some(value.to_lower()))
        }
        None => Err(InvalidTarget)
      }
    }
    (WriteUpsertByExternalId(_), ExternalInt(_), Some(value)) => Ok(Some(value))
    _ => Err(InvalidTarget)
  }
}

///|
fn emit_collection_record(
  writer : @encode.Writer,
  item : WriteCollectionItem,
  target_key : String?,
  limits : WriteCollectionRequestLimits,
) -> Result[Unit, WriteCollectionRequestIssue] {
  let parsed = match
    @source.parse_json(item.body.json, {
      max_input_bytes: limits.max_body_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => CapacityExceeded
          _ => InvalidBody
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_body_bytes,
      max_total_string_bytes: limits.max_body_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind is @decode.BudgetExceeded {
          CapacityExceeded
        } else {
          InvalidBody
        },
      )
  }
  guard @decode.open_object(root) is Ok(object) else { return Err(InvalidBody) }
  let projection = item.body.projection
  let keys : Array[(String, Int)] = []
  for field in projection.fields {
    if field.name == "attributes" || field.name == "Id" || field.name == "id" {
      return Err(InvalidBody)
    }
    keys.push((field.name, 0))
  }
  match projection.operation {
    WriteCreate => ()
    WriteUpdateById => keys.push(("Id", 1))
    WriteUpsertByExternalId(name) => keys.push((name, 1))
  }
  keys.push(("attributes", 2))
  keys.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  @encode.begin_object(writer) catch {
    _ => return Err(CapacityExceeded)
  }
  for (key, kind) in keys {
    @encode.key(writer, key) catch {
      _ => return Err(CapacityExceeded)
    }
    match kind {
      0 => {
        guard @decode.lookup(object, key) is Some(cursor) else {
          return Err(InvalidBody)
        }
        let mut selected : FieldMetadata? = None
        for field in projection.fields {
          if field.name == key {
            selected = Some(field)
            break
          }
        }
        guard selected is Some(field) else { return Err(InvalidBody) }
        match emit_write_cell(writer, cursor, field) {
          Ok(_) => ()
          Err(BudgetExceeded) => return Err(CapacityExceeded)
          Err(_) => return Err(InvalidBody)
        }
      }
      1 => {
        guard target_key is Some(value) else { return Err(InvalidTarget) }
        match item.target {
          ExternalInt(number) =>
            @encode.number_value(writer, number.to_double()) catch {
              _ => return Err(CapacityExceeded)
            }
          _ =>
            @encode.string_value(writer, value) catch {
              _ => return Err(CapacityExceeded)
            }
        }
      }
      _ => {
        @encode.begin_object(writer) catch {
          _ => return Err(CapacityExceeded)
        }
        @encode.key(writer, "type") catch {
          _ => return Err(CapacityExceeded)
        }
        @encode.string_value(writer, projection.resource) catch {
          _ => return Err(CapacityExceeded)
        }
        @encode.end_object(writer) catch {
          _ => return Err(CapacityExceeded)
        }
      }
    }
  }
  @encode.end_object(writer) catch {
    _ => return Err(CapacityExceeded)
  }
  Ok(())
}

///|
/// Salesforce sObject Collections returns results in the request's row order.
/// Only rows of one member may enter this request; `allOrNone=false` is fixed.
/// A provider-atomic command is a different admitted operation, not a flag on
/// this ordinary continue-row request.
pub fn prepare_continue_write_collection(
  rows : Array[WriteCollectionItem],
  api_version : String,
  limits : WriteCollectionRequestLimits,
) -> Result[WriteCollectionRequest, WriteCollectionRequestIssue] {
  if limits.max_path_bytes < 1 ||
    limits.max_target_bytes < 1 ||
    limits.max_body_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_rows < 1 {
    return Err(InvalidLimits)
  }
  if rows.is_empty() || rows.length() > limits.max_rows || rows.length() > 200 {
    return Err(InvalidRows)
  }
  guard write_api_major(api_version) is Some(major) else {
    return Err(InvalidVersion)
  }
  let first = rows[0].body.projection
  if major < 42 || (first.operation is WriteUpsertByExternalId(_) && major < 46) {
    return Err(InvalidVersion)
  }
  let base = "/services/data/" + api_version + "/composite/sobjects"
  let (verb, path) = match first.operation {
    WriteCreate => ("POST", base)
    WriteUpdateById => ("PATCH", base)
    WriteUpsertByExternalId(field) =>
      ("PATCH", base + "/" + first.resource + "/" + field)
  }
  if path.length() > limits.max_path_bytes {
    return Err(CapacityExceeded)
  }
  let row_cids : Array[String] = []
  let wire_targets : Array[String?] = []
  let overlap_keys : Array[String?] = []
  let mut remaining = limits.max_body_bytes
  for item in rows {
    let projection = item.body.projection
    if projection.operation != first.operation ||
      projection.resource != first.resource ||
      projection.observation_cid != first.observation_cid ||
      projection.binding != first.binding {
      return Err(MixedProjection)
    }
    if !observation_cid(item.row_preview_cid) ||
      row_cids.contains(item.row_preview_cid) {
      return Err(DuplicateRow)
    }
    let target = match
      collection_target_key(projection, item.target, limits.max_target_bytes) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let overlap = match
      collection_overlap_key(projection, item.target, target) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if overlap is Some(key) && overlap_keys.contains(Some(key)) {
      return Err(DuplicateTarget)
    }
    let input_bytes = match
      @scalar.admit_utf8_length(item.body.json, remaining) {
      Ok(value) => value
      Err(_) => return Err(CapacityExceeded)
    }
    remaining -= input_bytes
    row_cids.push(item.row_preview_cid)
    wire_targets.push(target)
    overlap_keys.push(overlap)
  }
  let writer = @encode.writer(
    limits.max_body_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(CapacityExceeded)
  }
  @encode.begin_object(writer) catch {
    _ => return Err(CapacityExceeded)
  }
  @encode.key(writer, "allOrNone") catch {
    _ => return Err(CapacityExceeded)
  }
  @encode.bool_value(writer, false) catch {
    _ => return Err(CapacityExceeded)
  }
  @encode.key(writer, "records") catch {
    _ => return Err(CapacityExceeded)
  }
  @encode.begin_array(writer) catch {
    _ => return Err(CapacityExceeded)
  }
  for index in 0..<rows.length() {
    match
      emit_collection_record(writer, rows[index], wire_targets[index], limits) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  @encode.end_array(writer) catch {
    _ => return Err(CapacityExceeded)
  }
  @encode.end_object(writer) catch {
    _ => return Err(CapacityExceeded)
  }
  let body = @encode.finish(writer) catch { _ => return Err(CapacityExceeded) }
  let kind = match first.operation {
    WriteCreate => CollectionCreate
    WriteUpdateById => CollectionUpdate
    WriteUpsertByExternalId(_) => CollectionUpsert
  }
  Ok({ verb, path, body, kind, projection: first, row_preview_cids: row_cids, })
}
