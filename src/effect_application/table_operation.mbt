///|
pub(all) enum TableContractIssue {
  InvalidLimits
  InvalidWire
  InvalidShape
  InvalidIdentity
  ForeignOperation
  Encoding
} derive(Eq, Debug)

///|
/// Content admission only. This is not approval, a dispatch claim, current
/// authorization, or evidence that an input or Catalog generation exists.
pub struct TableOperation {
  wire : String
  cid : String
  scope_cid : String
  effect_cid : String
  catalog_cid : String
  replace : Bool
  expected_uuid : String?
  expected_generation_cid : String?
  input_artifact_cid : String
  input_relation_cid : String
  schema_cid : String
  mapping_cid : String
  data_policy_cid : String
}

///|
/// The provider must independently establish durable publication of this exact
/// operation. Admitting these bytes does not confirm a Catalog transaction.
pub struct TableReceipt {
  wire : String
  cid : String
  request_cid : String
  table_uuid : String
  generation_cid : String
  schema_cid : String
  mapping_cid : String
  snapshot_id : String?
  row_count : Int64
}

///|
fn table_sealed_value(
  wire : String,
  self_field : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_allowed_nodes? : Int = 4096,
) -> Result[(@json.CanonicalValue, String), TableContractIssue] {
  if max_bytes < 1 ||
    max_bytes > 65536 ||
    max_nodes < 1 ||
    max_nodes > max_allowed_nodes ||
    max_depth < 1 ||
    max_depth > 16 {
    return Err(InvalidLimits)
  }
  let parsed = match
    @source.parse_json(wire, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidWire)
  }
  let value = @json.from_source(parsed, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(InvalidWire)
  }
  let encoded = @json.stringify_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if encoded != wire {
    return Err(InvalidWire)
  }
  guard ledger_cid(value, self_field) is Some(cid) &&
    @json.object_without_field(value, self_field) is Some(body) else {
    return Err(InvalidShape)
  }
  let expected = @json.cid_value(body, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if expected != cid {
    return Err(InvalidIdentity)
  }
  Ok((value, cid))
}

///|
fn table_uuid_valid(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  for i in 0..<36 {
    let c = value[i]
    if i == 8 || i == 13 || i == 18 || i == 23 {
      if c != '-' {
        return false
      }
    } else if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      return false
    }
  }
  true
}

///|
fn table_name_valid(value : String) -> Bool {
  let mut count = 0
  for c in value.iter() {
    if c == '\u{0000}' || c == '\r' || c == '\n' {
      return false
    }
    count += 1
  }
  count <= 256 && canonical_bounded_text(value, 1024)
}

///|
pub fn admit_table_operation(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[TableOperation, TableContractIssue] {
  let (value, cid) = match
    table_sealed_value(wire, "request_cid", max_bytes, max_nodes, max_depth) {
    Ok(v) => v
    Err(issue) => return Err(issue)
  }
  guard @json.object_field_count(value) == Some(14) &&
    ledger_string(value, "version") == Some("actql-table-operation/0.1") &&
    ledger_string(value, "action") is Some(action) &&
    (action == "create" || action == "replace") &&
    ledger_cid(value, "logical_request_scope_cid") is Some(scope_cid) &&
    ledger_cid(value, "effect_identity_cid") is Some(effect_cid) &&
    ledger_cid(value, "catalog_identity_cid") is Some(catalog_cid) &&
    ledger_cid(value, "input_artifact_cid") is Some(input_artifact_cid) &&
    ledger_cid(value, "input_relation_cid") is Some(input_relation_cid) &&
    ledger_cid(value, "schema_cid") is Some(schema_cid) &&
    ledger_cid(value, "storage_mapping_cid") is Some(mapping_cid) &&
    ledger_cid(value, "data_policy_cid") is Some(data_policy_cid) &&
    ledger_string(value, "table_name") is Some(name) &&
    table_name_valid(name) &&
    @json.object_field(value, "namespace") is Some(@json.Array(parts)) else {
    return Err(InvalidShape)
  }
  if @json.array_count(parts) < 1 || @json.array_count(parts) > 16 {
    return Err(InvalidShape)
  }
  for i in 0..<@json.array_count(parts) {
    guard @json.array_at(parts, i) is Some(@json.String(part)) &&
      table_name_valid(part) else {
      return Err(InvalidShape)
    }
  }
  let replace = action == "replace"
  let (expected_uuid, expected_generation_cid) = match
    @json.object_field(value, "expected_table") {
    Some(@json.Null) if !replace => (None, None)
    Some(expected) if replace => {
      guard @json.object_field_count(expected) == Some(2) &&
        ledger_string(expected, "table_uuid") is Some(uuid) &&
        table_uuid_valid(uuid) &&
        ledger_cid(expected, "generation_cid") is Some(generation) else {
        return Err(InvalidShape)
      }
      (Some(uuid), Some(generation))
    }
    _ => return Err(InvalidShape)
  }
  Ok({
    wire,
    cid,
    scope_cid,
    effect_cid,
    catalog_cid,
    replace,
    expected_uuid,
    expected_generation_cid,
    input_artifact_cid,
    input_relation_cid,
    schema_cid,
    mapping_cid,
    data_policy_cid,
  })
}

///|
fn table_snapshot_id(
  value : @json.CanonicalValue,
) -> Result[String?, TableContractIssue] {
  match @json.object_field(value, "snapshot_id") {
    Some(@json.Null) => Ok(None)
    Some(@json.String(id)) => {
      if id.is_empty() || id.length() > 19 || id[0] == '0' {
        return Err(InvalidShape)
      }
      for c in id.iter() {
        if c < '0' || c > '9' {
          return Err(InvalidShape)
        }
      }
      if id.length() == 19 && id > "9223372036854775807" {
        return Err(InvalidShape)
      }
      Ok(Some(id))
    }
    _ => Err(InvalidShape)
  }
}

///|
pub fn admit_table_receipt(
  request : TableOperation,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[TableReceipt, TableContractIssue] {
  let (value, cid) = match
    table_sealed_value(wire, "receipt_cid", max_bytes, max_nodes, max_depth) {
    Ok(v) => v
    Err(issue) => return Err(issue)
  }
  guard @json.object_field_count(value) == Some(12) &&
    ledger_string(value, "version") == Some("actql-table-receipt/0.1") &&
    ledger_cid(value, "request_cid") is Some(request_cid) &&
    ledger_cid(value, "effect_identity_cid") is Some(effect_cid) &&
    ledger_cid(value, "catalog_identity_cid") is Some(catalog_cid) &&
    ledger_cid(value, "schema_cid") is Some(schema_cid) &&
    ledger_cid(value, "storage_mapping_cid") is Some(mapping_cid) &&
    ledger_string(value, "table_uuid") is Some(table_uuid) &&
    table_uuid_valid(table_uuid) &&
    ledger_cid(value, "generation_cid") is Some(generation_cid) &&
    ledger_string(value, "metadata_location") is Some(location) &&
    !location.is_empty() &&
    location.length() <= 4096 &&
    ledger_integer(value, "row_count", 0L) is Some(row_count) else {
    return Err(InvalidShape)
  }
  let snapshot_id = match table_snapshot_id(value) {
    Ok(v) => v
    Err(issue) => return Err(issue)
  }
  if row_count > 0L && snapshot_id is None {
    return Err(InvalidShape)
  }
  if request_cid != request.cid ||
    effect_cid != request.effect_cid ||
    catalog_cid != request.catalog_cid ||
    schema_cid != request.schema_cid ||
    mapping_cid != request.mapping_cid ||
    (request.expected_uuid is Some(uuid) && uuid != table_uuid) {
    return Err(ForeignOperation)
  }
  if request.expected_generation_cid == Some(generation_cid) {
    return Err(ForeignOperation)
  }
  Ok({
    wire,
    cid,
    request_cid,
    table_uuid,
    generation_cid,
    schema_cid,
    mapping_cid,
    snapshot_id,
    row_count,
  })
}
