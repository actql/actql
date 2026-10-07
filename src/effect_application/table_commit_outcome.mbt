///|
pub(all) enum TableCommitIssue {
  InvalidLimits
  InvalidResponse
  Unconfirmed
  Receipt(TableContractIssue)
  ForeignRowCount
  Encoding
} derive(Eq, Debug)

///|
/// Project only a bounded original-operation receipt from saved physical
/// response bytes. A status code, current head, absent receipt or provider
/// error is not proof of commit/noncommit. Errors leave the dispatch uncertain.
/// Physical response custody and receipt authenticity belong to the installed
/// Catalog bridge and existing Ledger, not this content-only projection.
pub fn project_table_commit_outcome(
  operation : TableOperation,
  response_wire : String,
  status_code : Int,
  expected_row_count : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, TableCommitIssue] {
  if max_bytes < 1 || max_bytes > 65536 || max_nodes < 1 ||
    max_nodes > 4096 || max_depth < 1 || max_depth > 16 ||
    expected_row_count < 0L {
    return Err(InvalidLimits)
  }
  if status_code != 200 {
    return Err(Unconfirmed)
  }
  let source = match @source.parse_json(response_wire, {
    max_input_bytes: max_bytes, max_nodes, max_depth,
  }) {
    Ok(value) => value
    Err(_) => return Err(InvalidResponse)
  }
  let response = @json.from_source(source, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(InvalidResponse)
  }
  guard @json.object_field_count(response) == Some(2) &&
    @json.object_field(response, "ok") is Some(@json.Bool(true)) &&
    @json.object_field(response, "result") is Some(result) else {
    return Err(Unconfirmed)
  }
  let receipt_wire = @json.stringify_value(result, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let receipt = match admit_table_receipt(operation, receipt_wire, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(Receipt(issue))
  }
  if receipt.row_count != expected_row_count {
    return Err(ForeignRowCount)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "result")
    @json.emit_value(result, writer)
    @encode.key(writer, "state")
    @encode.string_value(writer, "applied")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(wire)
}
