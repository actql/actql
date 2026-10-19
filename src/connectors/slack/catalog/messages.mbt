///|
pub(all) struct SlackMessagePageLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_cursor_bytes : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum SlackMessagePageIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidPagination
  InvalidSelection(String)
  InvalidCell(String)
  DuplicateMessage
  ForeignHistoryRequest
  HistoryUnavailable
  ForeignRepliesRequest
  InconsistentThread
} derive(Eq, Debug)

///|
// One original bounded vendor page, not a complete history/thread selection,
// current workspace, authenticated acquisition, grant or retirement receipt.
pub struct SlackMessagePage {
  response_sha256 : String
  next_cursor : String?
  has_more : Bool
  history_limited : Bool
  priv rows : Array[Array[@admitted.CheckedValue]]
  priv history_request : SlackMessageHistoryRequest?
  priv facts : Array[SlackMessageFacts]
}

///|
// Presence belongs to the original parsed occurrence, not its nullable output.
// Reaction users may themselves be omitted inside a present reaction array.
priv struct SlackMessageFacts {
  established : Array[Bool]
  reaction_users : Array[Bool]
}

///|
fn message_facts(
  row : @decode.ObjectView,
  original_history : SlackMessageHistoryRequest?,
) -> SlackMessageFacts {
  let established = slack_message_column_names().map(name => {
    match name {
      "id" | "channel" | "ts" | "posted_at" => true
      "reply_count" =>
        !(@decode.field(row, name) is Missing) ||
        (original_history is Some(_) && ordinary_history_without_thread(row))
      _ => !(@decode.field(row, name) is Missing)
    }
  })
  let reaction_users = []
  if @decode.field(row, "reactions") is Present(reactions) &&
    @decode.array_length(reactions) is Some(count) {
    for index in 0..<count {
      // Called only after the same occurrence's complete value admission.
      let item = @decode.open_object(
        @decode.element_at(reactions, index).unwrap(),
      ).unwrap()
      reaction_users.push(!(@decode.field(item, "users") is Missing))
    }
  }
  { established, reaction_users, }
}

///|
pub fn slack_message_column_names() -> Array[String] {
  [
    "id", "channel", "ts", "user", "text", "thread_ts", "reply_count", "reactions",
    "edited", "files", "posted_at",
  ]
}

///|
fn message_field_contract(name : String) -> @contract.Contract {
  let string = @contract.primitive(@contract.StringType, nullable=false)
  match name {
    "reply_count" => @contract.primitive(@contract.Signed64Type, nullable=true)
    "edited" | "posted_at" =>
      @contract.primitive(@contract.TimestampType, nullable=name != "posted_at")
    "files" => @contract.array_contract(string, nullable=true).unwrap()
    "reactions" => {
      let reaction = @contract.object_contract(
        [
          ("name", string),
          ("count", @contract.primitive(@contract.Signed64Type, nullable=false)),
          ("users", @contract.array_contract(string, nullable=true).unwrap()),
        ],
        nullable=false,
        max_fields=3,
        max_name_bytes=32,
      ).unwrap()
      @contract.array_contract(reaction, nullable=true).unwrap()
    }
    _ =>
      @contract.primitive(
        @contract.StringType,
        nullable=name != "id" && name != "channel" && name != "ts",
      )
  }
}

///|
fn message_text(
  cell : @decode.Cursor,
  name : String,
) -> Result[String, SlackMessagePageIssue] {
  match @decode.text(cell) {
    Ok(text) => Ok(text)
    Err(_) => Err(InvalidCell(name))
  }
}

///|
fn message_integer(
  bytes : Bytes,
  cell : @decode.Cursor,
  name : String,
  max_bytes : Int,
) -> Result[@admitted.Value, SlackMessagePageIssue] {
  // The same existing Catalog helper reads the retained numeric-token span;
  // the JSON parser's Number placeholder never supplies an exact count.
  guard channel_original_integer(bytes, cell, max_bytes) is Some(integer) &&
    integer >= 0L else {
    return Err(InvalidCell(name))
  }
  Ok(@admitted.signed64_value(integer))
}

///|
fn message_users(
  cell : @decode.Cursor,
  max_bytes : Int,
) -> Result[@admitted.Value, SlackMessagePageIssue] {
  guard @decode.array_length(cell) is Some(count) else {
    return Err(InvalidCell("reactions.users"))
  }
  let values = []
  for index in 0..<count {
    match
      message_text(@decode.element_at(cell, index).unwrap(), "reactions.users") {
      Ok(text) => values.push(@admitted.text_value(text, max_bytes).unwrap())
      Err(issue) => return Err(issue)
    }
  }
  // Preserve the observed order/repetitions. This list is explicitly allowed
  // to be incomplete at Slack; it is not the reaction's total count.
  Ok(@admitted.array_value(values))
}

///|
fn message_reactions(
  bytes : Bytes,
  cell : @decode.Cursor,
  max_bytes : Int,
) -> Result[@admitted.Value, SlackMessagePageIssue] {
  guard @decode.array_length(cell) is Some(count) else {
    return Err(InvalidCell("reactions"))
  }
  let values = []
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(cell, index).unwrap())
      is Ok(item) &&
      @decode.lookup(item, "name") is Some(name) &&
      @decode.lookup(item, "count") is Some(count) else {
      return Err(InvalidCell("reactions"))
    }
    let name = match message_text(name, "reactions.name") {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let count = match
      message_integer(bytes, count, "reactions.count", max_bytes) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let users = match @decode.field(item, "users") {
      Missing | ExplicitNull => @admitted.null_value()
      Present(value) =>
        match message_users(value, max_bytes) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
    }
    values.push(
      @admitted.object_value([
        ("name", @admitted.text_value(name, max_bytes).unwrap()),
        ("count", count),
        ("users", users),
      ]).unwrap(),
    )
  }
  Ok(@admitted.array_value(values))
}

///|
fn message_files(
  cell : @decode.Cursor,
  max_bytes : Int,
) -> Result[@admitted.Value, SlackMessagePageIssue] {
  guard @decode.array_length(cell) is Some(count) else {
    return Err(InvalidCell("files"))
  }
  let values = []
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(cell, index).unwrap())
      is Ok(item) &&
      @decode.lookup(item, "id") is Some(id) &&
      @decode.text(id) is Ok(id) &&
      !id.is_empty() else {
      return Err(InvalidCell("files"))
    }
    // A file id remains String DATA. It cannot fabricate ResourceRef, version,
    // content bytes or a Content reference from the vendor's descriptive object.
    values.push(@admitted.text_value(id, max_bytes).unwrap())
  }
  Ok(@admitted.array_value(values))
}

///|
fn message_runtime_text(
  text : String,
  max_bytes : Int,
) -> Result[@admitted.Value, SlackMessagePageIssue] {
  match @admitted.text_value(text, max_bytes) {
    Some(value) => Ok(value)
    None => Err(BudgetExceeded)
  }
}

///|
fn message_runtime_cell(
  bytes : Bytes,
  row : @decode.ObjectView,
  name : String,
  channel : String,
  ts : String,
  max_bytes : Int,
  max_text_bytes : Int,
  original_history : SlackMessageHistoryRequest?,
) -> Result[@admitted.Value, SlackMessagePageIssue] {
  match name {
    "id" => return message_runtime_text(channel + ":" + ts, max_text_bytes)
    "channel" => return message_runtime_text(channel, max_text_bytes)
    "ts" => return message_runtime_text(ts, max_text_bytes)
    "posted_at" => {
      guard message_epoch_timestamp(ts) is Some(text) else {
        return Err(InvalidCell("ts"))
      }
      return Ok(
        @admitted.checked_timestamp_value(
          text,
          @contract.primitive(@contract.TimestampType, nullable=false),
        ).unwrap().value,
      )
    }
    _ => ()
  }
  if name == "reply_count" &&
    original_history is Some(_) &&
    ordinary_history_without_thread(row) {
    return Ok(@admitted.signed64_value(0L))
  }
  let cell = match @decode.field(row, name) {
    Missing | ExplicitNull => return Ok(@admitted.null_value())
    Present(value) => value
  }
  match name {
    "reply_count" => message_integer(bytes, cell, name, max_bytes)
    "reactions" => message_reactions(bytes, cell, max_bytes)
    "files" => message_files(cell, max_bytes)
    "edited" => {
      guard @decode.open_object(cell) is Ok(edited) &&
        @decode.lookup(edited, "ts") is Some(ts) &&
        @decode.text(ts) is Ok(ts) &&
        message_epoch_timestamp(ts) is Some(text) else {
        return Err(InvalidCell("edited"))
      }
      Ok(
        @admitted.checked_timestamp_value(
          text,
          @contract.primitive(@contract.TimestampType, nullable=false),
        ).unwrap().value,
      )
    }
    _ =>
      match message_text(cell, name) {
        Ok(text) => message_runtime_text(text, max_text_bytes)
        Err(issue) => Err(issue)
      }
  }
}

///|
fn ordinary_history_without_thread(row : @decode.ObjectView) -> Bool {
  // Only actual absent keys support the adopted non-thread projection. An
  // explicit count wins, including a positive count without thread metadata.
  if !(@decode.field(row, "reply_count") is Missing) ||
    !(@decode.field(row, "thread_ts") is Missing) {
    return false
  }
  // A known ordinary bot message is not partial merely because its subtype
  // is present. Unknown, null and thread/event subtypes supply no such proof.
  let ordinary_subtype = match @decode.field(row, "subtype") {
    Missing => true
    Present(value) => @decode.text(value) == Ok("bot_message")
    ExplicitNull => false
  }
  if !ordinary_subtype {
    return false
  }
  guard @decode.lookup(row, "text") is Some(text) && @decode.text(text) is Ok(_) else {
    return false
  }
  for
    name in [
      "event_ts", "message", "previous_message", "deleted_ts", "root", "reply_users",
      "reply_users_count", "latest_reply", "replies", "parent_user_id", "assistant_thread",
      "is_thread_broadcast",
    ] {
    if !(@decode.field(row, name) is Missing) {
      return false
    }
  }
  true
}

///|
pub fn project_slack_message_page(
  bytes : Bytes,
  channel : String,
  limits : SlackMessagePageLimits,
) -> Result[SlackMessagePage, SlackMessagePageIssue] {
  // Generic/partial/thread DATA cannot declare the original history context.
  project_message_page(bytes, channel, limits, None)
}

///|
fn project_message_page(
  bytes : Bytes,
  channel : String,
  limits : SlackMessagePageLimits,
  original_history : SlackMessageHistoryRequest?,
) -> Result[SlackMessagePage, SlackMessagePageIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_rows <= 0 ||
    limits.max_cursor_bytes <= 0 ||
    limits.max_value_nodes <= 0 ||
    limits.max_value_text_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if channel.is_empty() ||
    @scalar.admit_utf8_length(channel, limits.max_value_text_bytes) is Err(_) {
    return Err(InvalidCell("channel"))
  }
  let node = match
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
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind == @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
  guard @decode.open_object(cursor) is Ok(root) &&
    @decode.lookup(root, "ok") is Some(ok) &&
    @decode.boolean(ok) is Ok(true) &&
    @decode.lookup(root, "error") is None &&
    @decode.lookup(root, "messages") is Some(messages) &&
    @decode.array_length(messages) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  guard @decode.lookup(root, "has_more") is Some(more) &&
    @decode.boolean(more) is Ok(has_more) else {
    return Err(InvalidPagination)
  }
  let history_limited = match @decode.field(root, "is_limited") {
    Missing => false
    ExplicitNull => return Err(InvalidPagination)
    Present(value) =>
      match @decode.boolean(value) {
        Ok(value) => value
        Err(_) => return Err(InvalidPagination)
      }
  }
  let next = match @decode.field(root, "response_metadata") {
    Missing => None
    ExplicitNull => return Err(InvalidPagination)
    Present(value) => {
      guard @decode.open_object(value) is Ok(metadata) else {
        return Err(InvalidPagination)
      }
      match @decode.field(metadata, "next_cursor") {
        Missing | ExplicitNull => None
        Present(value) => {
          guard @decode.text(value) is Ok(text) else {
            return Err(InvalidPagination)
          }
          if @scalar.admit_utf8_length(text, limits.max_cursor_bytes) is Err(_) {
            return Err(BudgetExceeded)
          }
          if text.is_empty() {
            None
          } else {
            Some(text)
          }
        }
      }
    }
  }
  if has_more && next is None && count == 0 {
    return Err(InvalidPagination)
  }
  let columns = slack_message_column_names().map(name => {
    (name, message_field_contract(name))
  })
  let rows = []
  let facts = []
  let ids : Map[String, Bool] = Map([])
  let mut nodes = limits.max_value_nodes
  let mut text_bytes = limits.max_value_text_bytes
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(messages, index).unwrap())
      is Ok(row) &&
      @decode.lookup(row, "type") is Some(kind) &&
      @decode.text(kind) is Ok("message") &&
      @decode.lookup(row, "ts") is Some(ts) &&
      @decode.text(ts) is Ok(ts) else {
      return Err(InvalidResponse)
    }
    // Do not treat a change/delete event or mismatched response channel as a
    // current message. Hidden change events are not ordinary history records.
    if @decode.lookup(row, "channel") is Some(observed) &&
      @decode.text(observed) != Ok(channel) {
      return Err(InvalidCell("channel"))
    }
    if @decode.lookup(row, "hidden") is Some(hidden) &&
      @decode.boolean(hidden) != Ok(false) {
      return Err(InvalidCell("hidden"))
    }
    if @decode.lookup(row, "subtype") is Some(subtype) {
      guard @decode.text(subtype) is Ok(subtype) else {
        return Err(InvalidCell("subtype"))
      }
      if ["message_changed", "message_deleted", "message_replied"].contains(
          subtype,
        ) {
        return Err(InvalidCell("subtype"))
      }
    }
    let values = []
    for (name, contract) in columns {
      let runtime = match
        message_runtime_cell(
          bytes,
          row,
          name,
          channel,
          ts,
          limits.max_bytes,
          limits.max_value_text_bytes,
          original_history,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard @admitted.recheck_runtime_value_usage(runtime, contract, {
          max_nodes: nodes,
          max_depth: limits.max_depth,
          max_text_bytes: text_bytes,
        })
        is Some((value, used_nodes, used_text)) else {
        return Err(BudgetExceeded)
      }
      nodes -= used_nodes
      text_bytes -= used_text
      values.push(value)
    }
    guard values[0].value is @admitted.Text(id) else {
      return Err(InvalidCell("id"))
    }
    if ids.contains(id) {
      return Err(DuplicateMessage)
    }
    ids[id] = true
    rows.push(values)
    facts.push(message_facts(row, original_history))
  }
  Ok({
    response_sha256: @sha.hex(bytes),
    next_cursor: next,
    has_more,
    history_limited,
    rows,
    history_request: original_history,
    facts,
  })
}

///|
pub fn slack_message_page_ids(page : SlackMessagePage) -> Array[String] {
  page.rows.map(row => {
    match row[0].value {
      @admitted.Text(id) => id
      _ => abort("checked Slack message id")
    }
  })
}

///|
pub fn slack_message_page_row_count(page : SlackMessagePage) -> Int {
  page.rows.length()
}

///|
pub fn slack_message_page_rows_wire(
  page : SlackMessagePage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackMessagePageIssue] {
  message_rows_wire(page.rows, names, max_bytes, max_nodes, max_depth)
}

///|
fn message_rows_wire(
  rows : Array[Array[@admitted.CheckedValue]],
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackMessagePageIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = slack_message_column_names()
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
    for row in rows {
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
// A selected messages acquisition still checks its whole original response
// prefix and coalesces repeated thread observations before publishing rows.
pub fn slack_message_facts_wire() -> String {
  "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"
}

///|
pub fn slack_message_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackMessagePageIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let object = @contract.object_contract(
    slack_message_column_names().map(name => {
      (name, message_field_contract(name))
    }),
    nullable=false,
    max_fields=11,
    max_name_bytes=96,
  ).unwrap()
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
