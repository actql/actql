///|
pub(all) struct GmailThreadLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_messages : Int
  max_labels : Int
  max_headers : Int
  max_header_units : Int
  max_comment_depth : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum GmailThreadIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidCell(String)
  ForeignThread
  DuplicateMessage
  UnsupportedDate
  InvalidSelection(String)
} derive(Eq, Debug)

///|
// Projection DATA retains the same list occurrence. The physical receiver
// must separately retain its original request, metadata format and response
// custody; a hash, matching ID or this record does not establish those facts.
pub struct GmailThreadProjection {
  response_sha256 : String
  priv targets : GmailThreadListPage
  priv target_index : Int
  priv values : Array[@admitted.CheckedValue]
}

///|
pub fn gmail_thread_column_names() -> Array[String] {
  ["id", "labels", "last_message_date", "message_count", "subject"]
}

///|
fn gmail_thread_contracts() -> Array[@contract.Contract] {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  [
    text,
    @contract.array_contract(text, nullable=false).unwrap(),
    @contract.primitive(@contract.TimestampType, nullable=true),
    @contract.primitive(@contract.Signed64Type, nullable=false),
    @contract.primitive(@contract.StringType, nullable=true),
  ]
}

///|
fn gmail_thread_text(
  object : @decode.ObjectView,
  name : String,
) -> Result[String, GmailThreadIssue] {
  guard @decode.field(object, name) is Present(value) &&
    @decode.text(value) is Ok(text) else {
    return Err(InvalidCell(name))
  }
  Ok(text)
}

///|
fn gmail_thread_message_date(
  date : String?,
  internal_date : Int64?,
  limits : GmailThreadLimits,
) -> Result[String, GmailThreadIssue] {
  if date is Some(text) {
    match
      gmail_header_date(text, limits.max_header_units, limits.max_comment_depth) {
      Ok(utc) => return Ok(utc)
      Err(Unsupported) => return Err(UnsupportedDate)
      Err(BudgetExceeded) => return Err(BudgetExceeded)
      Err(Malformed) => ()
    }
  }
  guard internal_date is Some(milliseconds) else {
    return Err(InvalidCell("internalDate"))
  }
  guard @admitted.epoch_milliseconds_timestamp(milliseconds) is Some(utc) else {
    return Err(UnsupportedDate)
  }
  Ok(utc)
}

///|
fn gmail_thread_limits_valid(limits : GmailThreadLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_messages >= 0 &&
  limits.max_labels >= 0 &&
  limits.max_headers >= 0 &&
  limits.max_header_units >= 0 &&
  limits.max_comment_depth >= 0 &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes >= 0
}

///|
pub fn project_gmail_thread(
  bytes : Bytes,
  targets : GmailThreadListPage,
  target_index : Int,
  limits : GmailThreadLimits,
) -> Result[GmailThreadProjection, GmailThreadIssue] {
  if !gmail_thread_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  guard gmail_thread_list_id_at(targets, target_index) is Some(expected_id) else {
    return Err(ForeignThread)
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
  guard @decode.open_object(cursor) is Ok(root) else {
    return Err(InvalidResponse)
  }
  let id = match gmail_thread_text(root, "id") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if id != expected_id {
    return Err(ForeignThread)
  }
  guard @decode.field(root, "messages") is Present(messages) &&
    @decode.array_length(messages) is Some(count) else {
    return Err(InvalidCell("messages"))
  }
  if count > limits.max_messages {
    return Err(BudgetExceeded)
  }
  let ids : Map[String, Bool] = Map([])
  let labels : Array[@admitted.Value] = []
  let label_ids : Map[String, Bool] = Map([])
  let mut label_work = 0
  let mut header_work = 0
  let mut subject : String? = None
  let mut latest : String? = None
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(messages, index).unwrap())
      is Ok(message) else {
      return Err(InvalidResponse)
    }
    let message_id = match gmail_thread_text(message, "id") {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if message_id.is_empty() {
      return Err(InvalidCell("id"))
    }
    if ids.contains(message_id) {
      return Err(DuplicateMessage)
    }
    ids[message_id] = true
    let thread_id = match gmail_thread_text(message, "threadId") {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if thread_id != id {
      return Err(ForeignThread)
    }
    // Retain exact supplied int64 even when a valid Date wins. A malformed
    // known internalDate field is not hidden by the selected header.
    let internal_date = match @decode.field(message, "internalDate") {
      Missing => None
      ExplicitNull => return Err(InvalidCell("internalDate"))
      Present(value) =>
        match @decode.decimal_int64(value) {
          Ok(value) => Some(value)
          Err(_) => return Err(InvalidCell("internalDate"))
        }
    }
    guard @decode.field(message, "labelIds") is Present(message_labels) &&
      @decode.array_length(message_labels) is Some(label_count) else {
      return Err(InvalidCell("labelIds"))
    }
    if label_count > limits.max_labels - label_work {
      return Err(BudgetExceeded)
    }
    label_work += label_count
    for label_index in 0..<label_count {
      guard @decode.text(
          @decode.element_at(message_labels, label_index).unwrap(),
        )
        is Ok(label) &&
        !label.is_empty() else {
        return Err(InvalidCell("labelIds"))
      }
      if !label_ids.contains(label) {
        label_ids[label] = true
        guard @admitted.text_value(label, limits.max_value_text_bytes)
          is Some(value) else {
          return Err(BudgetExceeded)
        }
        labels.push(value)
      }
    }
    guard @decode.field(message, "payload") is Present(payload) &&
      @decode.open_object(payload) is Ok(payload) &&
      @decode.field(payload, "headers") is Present(headers) &&
      @decode.array_length(headers) is Some(header_count) else {
      return Err(InvalidCell("payload.headers"))
    }
    if header_count > limits.max_headers - header_work {
      return Err(BudgetExceeded)
    }
    header_work += header_count
    let mut date : String? = None
    let mut found_subject = false
    for header_index in 0..<header_count {
      guard @decode.open_object(
          @decode.element_at(headers, header_index).unwrap(),
        )
        is Ok(header) else {
        return Err(InvalidCell("payload.headers"))
      }
      let name = match gmail_thread_text(header, "name") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let value = match gmail_thread_text(header, "value") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if name.is_empty() {
        return Err(InvalidCell("payload.headers.name"))
      }
      for unit in name.iter() {
        if unit.to_int() < 33 || unit.to_int() > 126 || unit == ':' {
          return Err(InvalidCell("payload.headers.name"))
        }
      }
      match name.to_lower() {
        "subject" if index == 0 => {
          if found_subject {
            return Err(InvalidCell("subject"))
          }
          found_subject = true
          subject = Some(value)
        }
        "date" => {
          if date is Some(_) {
            return Err(InvalidCell("date"))
          }
          date = Some(value)
        }
        _ => ()
      }
    }
    let utc = match gmail_thread_message_date(date, internal_date, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match latest {
      None => latest = Some(utc)
      Some(previous) => {
        guard @admitted.compare_timestamp_text(utc, previous) is Some(order) else {
          return Err(UnsupportedDate)
        }
        if order > 0 {
          latest = Some(utc)
        }
      }
    }
  }
  let contracts = gmail_thread_contracts()
  let date_value = match latest {
    None => @admitted.null_value()
    Some(utc) => {
      // The generated scalar constructor requires a non-null Timestamp.
      // The ordinary final recheck below binds it to this nullable column.
      guard @admitted.checked_timestamp_value(
          utc,
          @contract.primitive(@contract.TimestampType, nullable=false),
        )
        is Some(checked) else {
        return Err(UnsupportedDate)
      }
      checked.value
    }
  }
  let subject_value = match subject {
    None => @admitted.null_value()
    Some(text) =>
      match @admitted.text_value(text, limits.max_value_text_bytes) {
        Some(value) => value
        None => return Err(BudgetExceeded)
      }
  }
  guard @admitted.text_value(id, limits.max_value_text_bytes) is Some(id_value) else {
    return Err(BudgetExceeded)
  }
  let values = []
  let mut nodes = limits.max_value_nodes
  let mut text_bytes = limits.max_value_text_bytes
  for
    index, value in [
      id_value,
      @admitted.array_value(labels),
      date_value,
      @admitted.signed64_value(count.to_int64()),
      subject_value,
    ] {
    guard @admitted.recheck_runtime_value_usage(value, contracts[index], {
        max_nodes: nodes,
        max_depth: limits.max_depth,
        max_text_bytes: text_bytes,
      })
      is Some((checked, used_nodes, used_text)) else {
      return Err(BudgetExceeded)
    }
    nodes -= used_nodes
    text_bytes -= used_text
    values.push(checked)
  }
  Ok({ response_sha256: @sha.hex(bytes), targets, target_index, values, })
}

///|
pub fn gmail_thread_value_at(
  thread : GmailThreadProjection,
  index : Int,
) -> @admitted.CheckedValue? {
  if index < 0 || index >= thread.values.length() {
    None
  } else {
    Some(thread.values[index])
  }
}

///|
pub fn gmail_thread_rows_wire(
  thread : GmailThreadProjection,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, GmailThreadIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = gmail_thread_column_names()
  let selected : Array[(String, Int)] = []
  for name in names {
    if selected.any(entry => entry.0 == name) {
      return Err(InvalidSelection(name))
    }
    let mut found = None
    for index, column in columns {
      if name == column {
        found = Some(index)
      }
    }
    guard found is Some(index) else { return Err(InvalidSelection(name)) }
    selected.push((name, index))
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_array(writer)
    @encode.begin_object(writer)
    for (name, index) in selected {
      @encode.key(writer, name)
      @admitted.emit_checked_wire_value(thread.values[index], writer)
    }
    @encode.end_object(writer)
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
pub fn gmail_thread_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, GmailThreadIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = gmail_thread_column_names()
  let contracts = gmail_thread_contracts()
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_ordered_object(writer)
    for index, name in columns {
      @encode.ordered_key(writer, name)
      @contract.emit_checked(contracts[index], writer)
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
