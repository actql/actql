///|
/// Admit the Local writer's saved physical response before projecting its
/// logical facts. The original bytes stay in the existing Ledger/Catalog;
/// neither this self-CID nor this projection proves durable publication.
pub fn project_iceberg_commit_response(
  response_wire : String,
  status_code : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @effect.TableCommitIssue] {
  if max_bytes < 1 ||
    max_bytes > 65536 ||
    max_nodes < 1 ||
    max_nodes > 4096 ||
    max_depth < 1 ||
    max_depth > 16 {
    return Err(InvalidLimits)
  }
  if status_code != 200 && status_code != 409 {
    return Err(Unconfirmed)
  }
  let parsed = match
    @source.parse_json(response_wire, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidResponse)
  }
  let response = @json.from_source(parsed, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(InvalidResponse)
  }
  guard @json.object_field_count(response) == Some(2) &&
    @json.object_field(response, "ok") is Some(@json.Bool(committed)) &&
    @json.object_field(response, "result") is Some(receipt) &&
    committed == (status_code == 200) else {
    return Err(Unconfirmed)
  }
  // Original nonpublication records are backend-neutral. Their binding and
  // reason still require the common operation-specific admission below.
  if !committed {
    return Ok(response_wire)
  }
  guard @json.object_field_count(receipt) == Some(12) &&
    ledger_string(receipt, "version") == Some("actql-table-receipt/0.1") &&
    ledger_cid(receipt, "receipt_cid") is Some(physical_cid) &&
    @json.object_without_field(receipt, "receipt_cid") is Some(physical_body) &&
    ledger_string(receipt, "metadata_location") is Some(location) &&
    !location.is_empty() &&
    location.length() <= 4096 &&
    ledger_integer(receipt, "row_count", 0L) is Some(row_count) else {
    return Err(Receipt(@effect.InvalidShape))
  }
  let expected = @json.cid_value(physical_body, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if physical_cid != expected {
    return Err(Receipt(@effect.InvalidIdentity))
  }
  match @json.object_field(receipt, "snapshot_id") {
    Some(@json.Null) if row_count == 0L => ()
    Some(@json.String(id)) => {
      if id.is_empty() ||
        id.length() > 19 ||
        id[0] == '0' ||
        (id.length() == 19 && id > "9223372036854775807") {
        return Err(Receipt(@effect.InvalidShape))
      }
      for c in id.iter() {
        if c < '0' || c > '9' {
          return Err(Receipt(@effect.InvalidShape))
        }
      }
    }
    _ => return Err(Receipt(@effect.InvalidShape))
  }
  // Strip only physical fields; do not normalize user values, invent a
  // snapshot or derive success from current head. The common Owner re-admits
  // this sealed logical record against the original operation and row count.
  let body = @json.object_without_field(physical_body, "metadata_location").unwrap()
  let body = @json.object_without_field(body, "snapshot_id").unwrap()
  let body = @json.object_without_field(body, "version").unwrap()
  let body = @json.object_with_string_field(
    body, "version", "actql-table-logical-receipt/0.1",
  ).unwrap()
  let body = @json.object_with_string_field(
    body, "physical_receipt_cid", physical_cid,
  ).unwrap()
  let cid = @json.cid_value(body, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let logical = @json.object_with_string_field(body, "receipt_cid", cid).unwrap()
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "ok")
    @encode.bool_value(writer, true)
    @encode.key(writer, "result")
    @json.emit_value(logical, writer)
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(Encoding) })
}
