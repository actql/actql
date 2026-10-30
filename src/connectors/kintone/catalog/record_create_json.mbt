///|
/// Typed DATA refusal at the mapped-value/native-request boundary. No grant,
/// target observation or acknowledged provider outcome is constructed here.
pub(all) enum RecordCreateJsonIssue {
  InvalidLimits
  BudgetExceeded
  InvalidRecords
  Write(RecordWriteIssue)
  Request(RecordMutationIssue)
} derive(Eq, Debug)

///|
fn create_json_write_limits_valid(limits : RecordWriteLimits) -> Bool {
  limits.max_fields > 0 &&
  limits.max_name_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_text_bytes > 0 &&
  limits.max_output_bytes > 0
}

///|
fn create_json_values(
  catalog : FormFieldCatalog,
  cursor : @decode.Cursor,
  limits : RecordWriteLimits,
) -> Result[RecordWriteValues, RecordCreateJsonIssue] {
  guard @decode.open_object(cursor) is Ok(_) &&
    @decode.object_length(cursor) is Some(count) else {
    return Err(InvalidRecords)
  }
  if count > limits.max_fields {
    return Err(BudgetExceeded)
  }
  let cells = []
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes
  for index in 0..<count {
    let (name, value) = @decode.field_at(cursor, index).unwrap()
    guard @scalar.admit_utf8_length(name, limits.max_name_bytes) is Ok(bytes) &&
      bytes <= text else {
      return Err(BudgetExceeded)
    }
    text -= bytes
    guard record_write_field_contract(catalog, name) is Some(contract) else {
      return Err(Write(FieldUnavailable(name)))
    }
    match
      @admitted.admit_usage(contract, value, {
        max_nodes: nodes,
        max_depth: limits.max_depth,
        max_text_bytes: text,
      }) {
      Ok((checked, used_nodes, used_text)) => {
        nodes -= used_nodes
        text -= used_text
        cells.push((name, checked))
      }
      Err(_) => return Err(Write(InvalidValue(name)))
    }
  }
  match prepare_record_write_values(catalog, cells, limits) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Write(issue))
  }
}

///|
fn create_json_records(
  catalog : FormFieldCatalog,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : RecordWriteLimits,
  request_limits : RecordMutationLimits,
) -> Result[Array[RecordWriteValues], RecordCreateJsonIssue] {
  if max_input_bytes <= 0 ||
    !create_json_write_limits_valid(write_limits) ||
    !mutation_limits_valid(request_limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > max_input_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes,
      max_nodes: write_limits.max_nodes,
      max_depth: write_limits.max_depth,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidRecords
        },
      )
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: write_limits.max_nodes,
      max_depth: write_limits.max_depth,
      max_string_bytes: write_limits.max_text_bytes,
      max_total_string_bytes: write_limits.max_text_bytes,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.kind {
          BudgetExceeded => BudgetExceeded
          _ => InvalidRecords
        },
      )
  }
  guard @decode.array_length(cursor) is Some(count) && count > 0 else {
    return Err(InvalidRecords)
  }
  if count > request_limits.max_records || count > 100 {
    return Err(BudgetExceeded)
  }
  let records = []
  for index in 0..<count {
    let row = @decode.element_at(cursor, index).unwrap()
    guard @decode.open_object(row) is Ok(_) else { return Err(InvalidRecords) }
    match create_json_values(catalog, row, write_limits) {
      Ok(value) => records.push(value)
      Err(issue) => return Err(issue)
    }
  }
  Ok(records)
}

///|
/// Exact mapped value rows, not fabricated provider records. The original
/// Form supplies every carrier; defaults, IDs and revision are not injected.
pub fn prepare_record_create_request_json(
  catalog : FormFieldCatalog,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : RecordWriteLimits,
  request_limits : RecordMutationLimits,
) -> Result[RecordCreateRequest, RecordCreateJsonIssue] {
  let records = match
    create_json_records(
      catalog, bytes, max_input_bytes, write_limits, request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match prepare_record_create_request(catalog, records, request_limits) {
    Ok(request) => Ok(request)
    Err(issue) => Err(Request(issue))
  }
}

///|
/// Same checked values and original Form, plus exact saved physical bytes.
/// Parsing admits values only; comparison emits no new request document.
pub fn restore_record_create_request_json(
  catalog : FormFieldCatalog,
  bytes : Bytes,
  original_body : String,
  max_input_bytes : Int,
  write_limits : RecordWriteLimits,
  request_limits : RecordMutationLimits,
) -> Result[RecordCreateRequest, RecordCreateJsonIssue] {
  if !mutation_limits_valid(request_limits) {
    return Err(InvalidLimits)
  }
  guard @scalar.admit_utf8_length(
      original_body,
      request_limits.max_output_bytes,
    )
    is Ok(_) else {
    return Err(BudgetExceeded)
  }
  let records = match
    create_json_records(
      catalog, bytes, max_input_bytes, write_limits, request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    restore_record_create_request(
      catalog, records, original_body, request_limits,
    ) {
    Ok(request) => Ok(request)
    Err(issue) => Err(Request(issue))
  }
}

///|
/// Canonical Common values retained by this original request, not the native
/// wrapper objects or newly observed provider data. No key/type normalization.
pub fn record_create_request_values_json(
  request : RecordCreateRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RecordCreateJsonIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_array(writer)
    for record in request.records {
      @encode.begin_object(writer)
      for (name, value) in record.originals {
        @encode.key(writer, name)
        @admitted.emit_checked_wire_value(value, writer)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
