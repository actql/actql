///|
pub(all) struct CalendarListLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_cursor_units : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum CalendarListIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidCursor
  InvalidSelection(String)
  DuplicateCalendar(String)
  InvalidCell(String)
} derive(Eq, Debug)

///|
// A bounded observation in the Calendar runtime, not a Source receipt or a
// capability inferred from accessRole. Keep original body identity for custody.
pub struct CalendarListPage {
  response_sha256 : String
  next_page_token : String?
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
fn calendar_list_columns() -> Array[(String, String)] {
  [
    ("id", "id"),
    ("summary", "summary"),
    ("time_zone", "timeZone"),
    ("access_role", "accessRole"),
  ]
}

///|
fn calendar_list_limits_valid(limits : CalendarListLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_rows > 0 &&
  limits.max_cursor_units > 0 &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0
}

///|
pub fn project_calendar_list(
  bytes : Bytes,
  limits : CalendarListLimits,
) -> Result[CalendarListPage, CalendarListIssue] {
  if !calendar_list_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
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
    @decode.text(kind) is Ok("calendar#calendarList") else {
    return Err(InvalidResponse)
  }
  let next_page_token = match @decode.field(root, "nextPageToken") {
    Missing => None
    ExplicitNull => return Err(InvalidCursor)
    Present(value) => {
      guard @decode.text(value) is Ok(token) &&
        !token.is_empty() &&
        token.length() <= limits.max_cursor_units else {
        return Err(InvalidCursor)
      }
      Some(token)
    }
  }
  let list = match @decode.field(root, "items") {
    Missing =>
      return Ok({ response_sha256: @sha.hex(bytes), next_page_token, rows: [], })
    ExplicitNull => return Err(InvalidResponse)
    Present(value) => value
  }
  guard @decode.array_length(list) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let rows = []
  let ids : Map[String, Bool] = Map([])
  let contract = @contract.primitive(@contract.StringType, nullable=false)
  let mut nodes = limits.max_value_nodes
  let mut text_bytes = limits.max_value_text_bytes
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(list, index).unwrap())
      is Ok(row) else {
      return Err(InvalidResponse)
    }
    // The physical request excludes deleted entries. Do not turn a tombstone
    // into a current calendar or silently filter it before key validation.
    match @decode.field(row, "deleted") {
      Missing => ()
      Present(value) if @decode.boolean(value) is Ok(false) => ()
      _ => return Err(InvalidResponse)
    }
    let values = []
    for (name, native_name) in calendar_list_columns() {
      guard @decode.lookup(row, native_name) is Some(value) &&
        @decode.text(value) is Ok(text) else {
        return Err(InvalidCell(name))
      }
      if name == "id" {
        if text.is_empty() {
          return Err(InvalidCell(name))
        }
        if ids.contains(text) {
          return Err(DuplicateCalendar(text))
        }
        ids[text] = true
      }
      // All declared fields are checked before any selected projection. No
      // schema inference, provider type table or permission comes from values.
      let (checked, used_nodes, used_text) = match
        @admitted.admit_usage(contract, value, {
          max_nodes: nodes,
          max_depth: limits.max_depth,
          max_text_bytes: text_bytes,
        }) {
        Ok(value) => value
        Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) =>
          return Err(BudgetExceeded)
        Err(_) => return Err(InvalidCell(name))
      }
      nodes -= used_nodes
      text_bytes -= used_text
      values.push(checked)
    }
    rows.push(values)
  }
  Ok({ response_sha256: @sha.hex(bytes), next_page_token, rows, })
}

///|
pub fn calendar_list_row_count(page : CalendarListPage) -> Int {
  page.rows.length()
}

///|
// Source key observation is independent of requested columns. The physical
// sequencer also rejects repeated original keys across response pages.
pub fn calendar_list_ids(page : CalendarListPage) -> Array[String] {
  page.rows.map(row => {
    match row[0].value {
      @admitted.Text(value) => value
      _ => abort("checked Calendar string invariant")
    }
  })
}

///|
pub fn calendar_list_rows_wire(
  page : CalendarListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = calendar_list_columns()
  let selected : Array[(String, Int)] = []
  for name in names {
    if selected.any(entry => entry.0 == name) {
      return Err(InvalidSelection(name))
    }
    let mut matched = None
    for index, column in columns {
      if column.0 == name {
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
pub fn calendar_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_ordered_object(writer)
    // The full fixed declared field map is ordered by Common's wire rule.
    for name in ["access_role", "id", "summary", "time_zone"] {
      @encode.ordered_key(writer, name)
      @contract.emit_checked(
        @contract.primitive(@contract.StringType, nullable=false),
        writer,
      )
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
pub fn calendar_list_facts_wire() -> String {
  "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"
}
