///|
/// Interpret the SAME parameter-bound Source request passed to the provider.
/// The caller retains the actual RowAcquisition; this produces only vendor
/// query DATA and does not reconstruct that owner from equal JSON or a CID.
pub fn prepare_calendar_events_request(
  wire : String,
  profile : @calendar_profile.Profile,
  limits : CalendarEventsLimits,
) -> Result[CalendarEventsQuery, CalendarEventsIssue] {
  if !events_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if wire.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let bytes = @utf8.encode(wire)
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let original = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidQuery
        },
      )
  }
  let cursor = match
    @decode.admit(original, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidQuery)
  }
  guard @decode.open_object(cursor) is Ok(object) &&
    @decode.object_field_names(cursor) is Ok(names) &&
    names.length() == 4 &&
    names.all(name => {
      ["calendar_id", "time_min", "time_max", "time_zone"].contains(name)
    }) else {
    return Err(InvalidQuery)
  }
  let fields = []
  for name in ["calendar_id", "time_min", "time_max", "time_zone"] {
    // Missing and explicit NULL are not hidden query/profile defaults.
    guard @decode.field(object, name) is Present(value) &&
      @decode.text(value) is Ok(text) else {
      return Err(InvalidQuery)
    }
    fields.push(text)
  }
  prepare_calendar_events_query(
    fields[0],
    fields[1],
    fields[2],
    fields[3],
    profile,
    limits,
  )
}

///|
/// The complete object contract used by a SourceView's existing request_schema
/// reference, not the response row's column-schema map or a new publication.
pub fn calendar_events_request_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarEventsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let string = @contract.primitive(@contract.StringType, nullable=false)
  let contract = @contract.object_contract(
    [
      ("calendar_id", string),
      ("time_min", string),
      ("time_max", string),
      ("time_zone", string),
    ],
    nullable=false,
    max_fields=4,
    // Total UTF-8 bytes of these four fixed field names, not per-name size.
    max_name_bytes=36,
  ).unwrap()
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @contract.emit_checked(contract, writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
