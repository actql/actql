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
  let target_keys : Array[String?] = []
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
    if target is Some(key) && target_keys.contains(Some(key)) {
      return Err(DuplicateTarget)
    }
    let input_bytes = match
      @scalar.admit_utf8_length(item.body.json, remaining) {
      Ok(value) => value
      Err(_) => return Err(CapacityExceeded)
    }
    remaining -= input_bytes
    row_cids.push(item.row_preview_cid)
    target_keys.push(target)
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
      emit_collection_record(writer, rows[index], target_keys[index], limits) {
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
  Ok({ verb, path, body, row_preview_cids: row_cids, })
}
