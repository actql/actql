///|
/// Mapped value DATA admitted against the original Form. This does not supply
/// a target, revision, Preview, current permission or provider outcome.
pub(all) enum RecordWriteJsonIssue {
  InvalidLimits
  BudgetExceeded
  InvalidValues
  Write(RecordWriteIssue)
} derive(Eq, Debug)

///|
fn write_json_limits_valid(limits : RecordWriteLimits) -> Bool {
  limits.max_fields > 0 &&
  limits.max_name_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_text_bytes > 0 &&
  limits.max_output_bytes > 0
}

///|
fn write_json_cursor(
  bytes : Bytes,
  max_input_bytes : Int,
  limits : RecordWriteLimits,
) -> Result[@decode.Cursor, RecordWriteJsonIssue] {
  if max_input_bytes <= 0 || !write_json_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > max_input_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidValues
        },
      )
  }
  match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_text_bytes,
      max_total_string_bytes: limits.max_text_bytes,
    }) {
    Ok(value) => Ok(value)
    Err(error) =>
      Err(
        match error.kind {
          BudgetExceeded => BudgetExceeded
          _ => InvalidValues
        },
      )
  }
}

///|
fn write_json_values(
  catalog : FormFieldCatalog,
  cursor : @decode.Cursor,
  limits : RecordWriteLimits,
) -> Result[RecordWriteValues, RecordWriteJsonIssue] {
  guard @decode.open_object(cursor) is Ok(_) &&
    @decode.object_length(cursor) is Some(count) else {
    return Err(InvalidValues)
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
/// One mapped object, without native wrapper fields or an inferred target.
/// CREATE uses the same cursor/value admission for its array of objects.
pub fn prepare_record_write_values_json(
  catalog : FormFieldCatalog,
  bytes : Bytes,
  max_input_bytes : Int,
  limits : RecordWriteLimits,
) -> Result[RecordWriteValues, RecordWriteJsonIssue] {
  match write_json_cursor(bytes, max_input_bytes, limits) {
    Ok(cursor) => write_json_values(catalog, cursor, limits)
    Err(issue) => Err(issue)
  }
}
