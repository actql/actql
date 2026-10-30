///|
pub(all) struct CalendarFreeBusyLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_calendars : Int
  max_rows : Int
  max_request_bytes : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum CalendarFreeBusyIssue {
  InvalidLimits
  InvalidQuery
  BudgetExceeded
  InvalidResponse
  ForeignCalendars
  CalendarRejected(String)
  InvalidInterval
  InvalidSelection(String)
} derive(Eq, Debug)

///|
// This is a checked vendor request, not an Account, Source or egress grant.
// Its private constructor snapshots the original ordered calendar selection.
pub struct CalendarFreeBusyQuery {
  priv calendar_ids : Array[String]
  priv start : String
  priv end : String
  priv request_wire : String
}

///|
pub struct CalendarFreeBusyPage {
  response_sha256 : String
  priv query : CalendarFreeBusyQuery
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
fn free_busy_limits_valid(limits : CalendarFreeBusyLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_calendars > 0 &&
  limits.max_calendars <= 50 &&
  limits.max_rows > 0 &&
  limits.max_request_bytes > 0 &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0
}

///|
pub fn prepare_calendar_free_busy_query(
  calendar_ids : Array[String],
  start : String,
  end : String,
  limits : CalendarFreeBusyLimits,
) -> Result[CalendarFreeBusyQuery, CalendarFreeBusyIssue] {
  if !free_busy_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if calendar_ids.is_empty() || calendar_ids.length() > limits.max_calendars {
    return Err(InvalidQuery)
  }
  guard @admitted.compare_timestamp_text(start, end) is Some(order) && order < 0 else {
    return Err(InvalidQuery)
  }
  let ids : Array[String] = []
  for id in calendar_ids {
    if id.is_empty() || ids.contains(id) {
      return Err(InvalidQuery)
    }
    ids.push(id)
  }
  let writer = @encode.writer(
    limits.max_request_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let request_wire = try {
    @encode.begin_object(writer)
    @encode.key(writer, "timeMin")
    @encode.string_value(writer, start)
    @encode.key(writer, "timeMax")
    @encode.string_value(writer, end)
    // Explicit UTC prevents a process-local zone or API default selecting the
    // timestamp interpretation. No group expansion is requested by this port.
    @encode.key(writer, "timeZone")
    @encode.string_value(writer, "UTC")
    @encode.key(writer, "calendarExpansionMax")
    @encode.number_value(writer, ids.length().to_double())
    @encode.key(writer, "items")
    @encode.begin_array(writer)
    for id in ids {
      @encode.begin_object(writer)
      @encode.key(writer, "id")
      @encode.string_value(writer, id)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  Ok({ calendar_ids: ids, start, end, request_wire, })
}

///|
pub fn calendar_free_busy_request_wire(query : CalendarFreeBusyQuery) -> String {
  query.request_wire
}

///|
// The same existing physical conversion; canonical Timestamp admission still
// accepts only its original UTC wire. Raw vendor observations retain offsets.
fn calendar_rfc3339(text : String) -> String? {
  @admitted.normalize_timestamp_text(text, 40)
}

///|
fn free_busy_no_errors(object : @decode.ObjectView) -> Bool {
  match @decode.field(object, "errors") {
    Missing => true
    Present(value) => @decode.array_length(value) == Some(0)
    ExplicitNull => false
  }
}

///|
pub fn project_calendar_free_busy(
  bytes : Bytes,
  query : CalendarFreeBusyQuery,
  limits : CalendarFreeBusyLimits,
) -> Result[CalendarFreeBusyPage, CalendarFreeBusyIssue] {
  if !free_busy_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes ||
    query.calendar_ids.length() > limits.max_calendars {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(cursor) is Ok(root) &&
    @decode.lookup(root, "kind") is Some(kind) &&
    @decode.text(kind) is Ok("calendar#freeBusy") &&
    @decode.lookup(root, "timeMin") is Some(start) &&
    @decode.text(start) is Ok(start) &&
    calendar_rfc3339(start) == Some(query.start) &&
    @decode.lookup(root, "timeMax") is Some(end) &&
    @decode.text(end) is Ok(end) &&
    calendar_rfc3339(end) == Some(query.end) else {
    return Err(InvalidResponse)
  }
  match @decode.field(root, "groups") {
    Missing => ()
    Present(value) if @decode.object_length(value) == Some(0) => ()
    _ => return Err(ForeignCalendars)
  }
  guard @decode.lookup(root, "calendars") is Some(calendars) &&
    @decode.open_object(calendars) is Ok(calendar_map) &&
    @decode.object_length(calendars) == Some(query.calendar_ids.length()) else {
    return Err(ForeignCalendars)
  }
  let rows = []
  let text_contract = @contract.primitive(@contract.StringType, nullable=false)
  let timestamp_contract = @contract.primitive(
    @contract.TimestampType,
    nullable=false,
  )
  let mut nodes = limits.max_value_nodes
  let mut text_bytes = limits.max_value_text_bytes
  for id in query.calendar_ids {
    guard @decode.lookup(calendar_map, id) is Some(calendar) &&
      @decode.open_object(calendar) is Ok(calendar) else {
      return Err(ForeignCalendars)
    }
    if !free_busy_no_errors(calendar) {
      return Err(CalendarRejected(id))
    }
    let intervals = match @decode.field(calendar, "busy") {
      Missing => continue
      ExplicitNull => return Err(InvalidResponse)
      Present(value) => value
    }
    guard @decode.array_length(intervals) is Some(count) else {
      return Err(InvalidResponse)
    }
    if count > limits.max_rows - rows.length() {
      return Err(BudgetExceeded)
    }
    for index in 0..<count {
      guard @decode.open_object(@decode.element_at(intervals, index).unwrap())
        is Ok(interval) &&
        @decode.lookup(interval, "start") is Some(start) &&
        @decode.text(start) is Ok(start) &&
        calendar_rfc3339(start) is Some(start) &&
        @decode.lookup(interval, "end") is Some(end) &&
        @decode.text(end) is Ok(end) &&
        calendar_rfc3339(end) is Some(end) &&
        @admitted.compare_timestamp_text(start, end) == Some(-1) else {
        return Err(InvalidInterval)
      }
      let values = []
      for
        (text, contract) in [
          (id, text_contract),
          (start, timestamp_contract),
          (end, timestamp_contract),
        ] {
        // Admission accounts each retained cell, even a repeated calendar ID.
        let cursor = match
          @decode.admit_raw_json(text.to_json(), @decode.cursor_span(cursor), {
            max_nodes: 1,
            max_depth: 1,
            max_string_bytes: limits.max_bytes,
            max_total_string_bytes: limits.max_bytes,
          }) {
          Ok(value) => value
          Err(_) => return Err(BudgetExceeded)
        }
        let (value, used_nodes, used_text) = match
          @admitted.admit_usage(contract, cursor, {
            max_nodes: nodes,
            max_depth: limits.max_depth,
            max_text_bytes: text_bytes,
          }) {
          Ok(value) => value
          Err(_) => return Err(BudgetExceeded)
        }
        nodes -= used_nodes
        text_bytes -= used_text
        values.push(value)
      }
      rows.push(values)
    }
  }
  Ok({ response_sha256: @sha.hex(bytes), query, rows, })
}

///|
pub fn calendar_free_busy_row_count(page : CalendarFreeBusyPage) -> Int {
  page.rows.length()
}

///|
pub fn calendar_free_busy_matches_query(
  page : CalendarFreeBusyPage,
  query : CalendarFreeBusyQuery,
) -> Bool {
  physical_equal(page.query, query)
}

///|
pub fn calendar_free_busy_column_names() -> Array[String] {
  ["calendar_id", "start", "end"]
}

///|
pub fn calendar_free_busy_rows_wire(
  page : CalendarFreeBusyPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarFreeBusyIssue] {
  let columns = calendar_free_busy_column_names()
  let selected : Array[(String, Int)] = []
  for name in names {
    if selected.any(entry => entry.0 == name) {
      return Err(InvalidSelection(name))
    }
    let mut matched = None
    for index, column in columns {
      if column == name {
        matched = Some(index)
      }
    }
    guard matched is Some(index) else { return Err(InvalidSelection(name)) }
    selected.push((name, index))
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_array(writer)
    for row in page.rows {
      @encode.begin_object(writer)
      for (name, index) in selected {
        @encode.key(writer, name)
        @admitted.emit_checked_wire_value(row[index], writer)
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

///|
pub fn calendar_free_busy_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarFreeBusyIssue] {
  let fields = calendar_free_busy_column_names().map(name => {
    (
      name,
      @contract.primitive(
        if name == "calendar_id" {
          @contract.StringType
        } else {
          @contract.TimestampType
        },
        nullable=false,
      ),
    )
  })
  let object = match
    @contract.object_contract(
      fields,
      nullable=false,
      max_fields=3,
      max_name_bytes=64,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidResponse)
  }
  guard object.shape is @contract.Object(fields) else {
    return Err(InvalidResponse)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_ordered_object(writer)
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      @encode.ordered_key(writer, field.name)
      @contract.emit_checked(field.contract, writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn calendar_free_busy_facts_wire() -> String {
  // The existing facts Owner requires nonempty tuples whenever relation_keys
  // is present. Omit that evidence component for this keyless Source.
  "{}"
}
