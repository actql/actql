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
/// Content-only admission of a Catalog's durable original nonpublication
/// fact. The installed provider establishes the matching publication fence;
/// neither a valid self-CID nor absence from current head proves that fact.
fn table_noncommit_reason(
  operation : TableOperation,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, TableContractIssue] {
  let (value, _) = match
    table_sealed_value(wire, "receipt_cid", max_bytes, max_nodes, max_depth) {
    Ok(v) => v
    Err(issue) => return Err(issue)
  }
  guard @json.object_field_count(value) == Some(8) &&
    ledger_string(value, "version") == Some("actql-table-noncommit-receipt/0.1") &&
    ledger_cid(value, "request_cid") is Some(request_cid) &&
    ledger_cid(value, "effect_identity_cid") is Some(effect_cid) &&
    ledger_cid(value, "catalog_identity_cid") is Some(catalog_cid) &&
    ledger_cid(value, "schema_cid") is Some(schema_cid) &&
    ledger_cid(value, "storage_mapping_cid") is Some(mapping_cid) &&
    ledger_string(value, "reason") is Some(reason) &&
    (reason == "CreateNameConflict" || reason == "ExpectedGenerationConflict") else {
    return Err(InvalidShape)
  }
  if request_cid != operation.cid ||
    effect_cid != operation.effect_cid ||
    catalog_cid != operation.catalog_cid ||
    schema_cid != operation.schema_cid ||
    mapping_cid != operation.mapping_cid ||
    operation.replace != (reason == "ExpectedGenerationConflict") {
    return Err(ForeignOperation)
  }
  Ok(reason)
}

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
  if max_bytes < 1 ||
    max_bytes > 65536 ||
    max_nodes < 1 ||
    max_nodes > 4096 ||
    max_depth < 1 ||
    max_depth > 16 ||
    expected_row_count < 0L {
    return Err(InvalidLimits)
  }
  if status_code != 200 && status_code != 409 {
    return Err(Unconfirmed)
  }
  let source = match
    @source.parse_json(response_wire, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidResponse)
  }
  let response = @json.from_source(source, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(InvalidResponse)
  }
  guard @json.object_field_count(response) == Some(2) &&
    @json.object_field(response, "ok") is Some(@json.Bool(committed)) &&
    @json.object_field(response, "result") is Some(result) else {
    return Err(Unconfirmed)
  }
  if committed != (status_code == 200) {
    return Err(Unconfirmed)
  }
  let receipt_wire = @json.stringify_value(
    result, max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let reason = if committed {
    let receipt = match
      admit_table_receipt(
        operation, receipt_wire, max_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Receipt(issue))
    }
    if receipt.row_count != expected_row_count {
      return Err(ForeignRowCount)
    }
    None
  } else {
    match
      table_noncommit_reason(
        operation, receipt_wire, max_bytes, max_nodes, max_depth,
      ) {
      Ok(reason) => Some(reason)
      Err(issue) => return Err(Receipt(issue))
    }
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    if reason is Some(code) {
      @encode.key(writer, "error")
      @encode.begin_object(writer)
      @encode.key(writer, "code")
      @encode.string_value(writer, code)
      @encode.key(writer, "details")
      @json.emit_value(result, writer)
      @encode.key(writer, "message")
      @encode.string_value(writer, "Table operation did not commit")
      @encode.end_object(writer)
    } else {
      @encode.key(writer, "result")
      @json.emit_value(result, writer)
    }
    @encode.key(writer, "state")
    @encode.string_value(writer, if committed { "applied" } else { "failed" })
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(wire)
}
