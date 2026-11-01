///|
/// Compare one original request with the Common row's mapped values. The
/// temporary parsed request is only comparison workspace, never a replacement
/// acquisition, physical request, declaration, response or permission.
pub fn record_create_request_matches_value_wire(
  request : RecordCreateRequest,
  value_wire : String,
  max_input_bytes : Int,
  write_limits : RecordWriteLimits,
  limits : RecordMutationLimits,
) -> Result[Bool, RecordCreateJsonIssue] {
  if !write_json_limits_valid(write_limits) ||
    !mutation_limits_valid(limits) ||
    max_input_bytes <= 2 {
    return Err(InvalidLimits)
  }
  if !record_create_request_is_original(request) ||
    request.records.length() != 1 {
    return Err(InvalidRecords)
  }
  guard @scalar.admit_utf8_length(value_wire, max_input_bytes - 2) is Ok(_) else {
    return Err(BudgetExceeded)
  }
  let expected = match
    prepare_record_create_request_json(
      request.catalog,
      @utf8.encode("[" + value_wire + "]"),
      max_input_bytes,
      write_limits,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = request.records[0].originals
  let fields = expected.records[0].originals
  if original.length() != fields.length() {
    return Ok(false)
  }
  let mut remaining = limits.max_comparison_work
  for (name, value) in original {
    let mut found = None
    for (other, checked) in fields {
      for text in [name, other] {
        if text.length() > remaining {
          return Err(BudgetExceeded)
        }
        remaining -= text.length()
      }
      if name == other {
        found = Some(checked)
        break
      }
    }
    guard found is Some(checked) else { return Ok(false) }
    let comparison = match
      @admitted.start_complete_equality(value, checked, {
        max_nodes: limits.max_output_nodes,
        max_depth: limits.max_output_depth,
        max_text_bytes: limits.max_output_bytes,
      }) {
      Ok(cursor) => cursor
      Err(_) => return Err(BudgetExceeded)
    }
    while true {
      if remaining <= 0 {
        @admitted.cancel_complete_equality(comparison)
        return Err(BudgetExceeded)
      }
      match @admitted.advance_complete_equality(comparison, 1) {
        EqualityContinue(work~) => remaining -= work
        EqualityComplete(equal~, work~) => {
          remaining -= work
          if !equal {
            return Ok(false)
          }
          break
        }
        EqualityFailed(_, work=_) => return Err(BudgetExceeded)
      }
    }
  }
  Ok(true)
}
