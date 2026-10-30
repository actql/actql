///|
// One existing checked CREATE change envelope, not an arbitrary JS snapshot or
// row authority. Input bytes are bounded before parser/index construction.
fn create_proposal_values(
  catalog : FormFieldCatalog,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : RecordWriteLimits,
  request_limits : RecordMutationLimits,
) -> Result[RecordWriteValues, RecordCreateJsonIssue] {
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
  guard @decode.closed_object(cursor, ["state", "value"]) is Ok(object) &&
    @decode.lookup(object, "state") is Some(state) &&
    @decode.text(state) == Ok("present") &&
    @decode.lookup(object, "value") is Some(value) else {
    return Err(InvalidRecords)
  }
  create_json_values(catalog, value, write_limits)
}

///|
/// Consume the complete bounded Common change wire without a JS value encoder.
/// Original Form admission and native output limits remain the same as the
/// array ingress; no defaults, provider record IDs or permission are inserted.
pub fn prepare_record_create_request_proposal(
  catalog : FormFieldCatalog,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : RecordWriteLimits,
  request_limits : RecordMutationLimits,
) -> Result[RecordCreateRequest, RecordCreateJsonIssue] {
  let values = match
    create_proposal_values(
      catalog, bytes, max_input_bytes, write_limits, request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match prepare_record_create_request(catalog, [values], request_limits) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Request(issue))
  }
}

///|
/// Same authenticated saved change wire and complete physical body, not a new
/// prepare/tag/CID. Caller custody/current/row binding remains mandatory.
pub fn restore_record_create_request_proposal(
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
  let values = match
    create_proposal_values(
      catalog, bytes, max_input_bytes, write_limits, request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    restore_record_create_request(
      catalog,
      [values],
      original_body,
      request_limits,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Request(issue))
  }
}
