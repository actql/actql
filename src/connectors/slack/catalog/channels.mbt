///|
pub(all) struct SlackChannelListLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_cursor_bytes : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum SlackChannelListIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidCursor
  InvalidSelection(String)
  DuplicateChannel
  InvalidCell(String)
} derive(Eq, Debug)

///|
// This is one checked conversation vendor page. It is not a workspace selection, token
// scope, complete paged Source, current authorization or custody receipt.
pub struct SlackChannelListPage {
  response_sha256 : String
  next_cursor : String?
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
pub fn slack_channel_list_column_names() -> Array[String] {
  [
    "id", "name", "topic", "purpose", "member_count", "is_private", "is_archived",
    "created",
  ]
}

///|
fn channel_field_contract(name : String) -> @contract.Contract {
  @contract.primitive(
    match name {
      "member_count" => @contract.Signed64Type
      "created" => @contract.TimestampType
      "is_private" | "is_archived" => @contract.BooleanType
      _ => @contract.StringType
    },
    nullable=name != "id",
  )
}

///|
// Read the exact numeric token from this response's original span. The source
// parser's binary64 placeholder never supplies a count or timestamp identity.
// Exact integral decimal/exponent spellings are normalized without rounding.
fn channel_original_integer(
  bytes : Bytes,
  cursor : @decode.Cursor,
  max_bytes : Int,
) -> Int64? {
  guard @decode.view(cursor) is @decode.NumberValue(_) else { return None }
  let span = @decode.cursor_span(cursor)
  guard span.start_byte >= 0 &&
    span.end_byte > span.start_byte &&
    span.end_byte <= bytes.length() else {
    return None
  }
  let raw = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
    _ => return None
  }
  guard @admitted.normalize_decimal_text(raw, 19, 0, max_bytes) is Ok(canonical) else {
    return None
  }
  match @scalar.read_decimal_int64(canonical) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
pub fn project_slack_channel_list(
  bytes : Bytes,
  limits : SlackChannelListLimits,
) -> Result[SlackChannelListPage, SlackChannelListIssue] {
  project_channel_list(bytes, limits, false)
}

///|
// History enumeration explicitly requests channels, IMs and multi-party IMs.
// The ordinary channels Source keeps its narrower response admission. Neither
// reader infers conversation kinds from identifier prefixes or invents fields
// that Slack omitted from a particular conversation kind.
pub fn project_slack_history_conversation_list(
  bytes : Bytes,
  limits : SlackChannelListLimits,
) -> Result[SlackChannelListPage, SlackChannelListIssue] {
  project_channel_list(bytes, limits, true)
}

///|
fn project_channel_list(
  bytes : Bytes,
  limits : SlackChannelListLimits,
  allow_direct_messages : Bool,
) -> Result[SlackChannelListPage, SlackChannelListIssue] {
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
    @decode.lookup(root, "channels") is Some(members) &&
    @decode.array_length(members) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  // Unknown bounded vendor fields are retained in the original response by
  // the physical owner. They are not interpreted as ActQL columns or grants.
  // Slack documents absent, empty and null next_cursor as terminal. The
  // containing metadata must still be an object; other cursor types refuse.
  let next = match @decode.field(root, "response_metadata") {
    Missing => None
    ExplicitNull => return Err(InvalidCursor)
    Present(metadata) => {
      guard @decode.open_object(metadata) is Ok(metadata) else {
        return Err(InvalidCursor)
      }
      match @decode.field(metadata, "next_cursor") {
        Missing | ExplicitNull => None
        Present(value) => {
          guard @decode.text(value) is Ok(text) else {
            return Err(InvalidCursor)
          }
          match
            @admitted.admit_usage(
              @contract.primitive(@contract.StringType, nullable=false),
              value,
              {
                max_nodes: 1,
                max_depth: 1,
                max_text_bytes: limits.max_cursor_bytes,
              },
            ) {
            Err(_) => return Err(BudgetExceeded)
            Ok(_) => ()
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
  let rows = []
  let ids : Map[String, Bool] = Map([])
  let mut nodes = limits.max_value_nodes
  let mut text_bytes = limits.max_value_text_bytes
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(members, index).unwrap())
      is Ok(row) else {
      return Err(InvalidResponse)
    }
    // Always check present kind discriminants, even when the selected output
    // omits every field except id. The broader history request admits actual
    // IM/MPIM records; the ordinary channel request still refuses them.
    for flag in ["is_im", "is_mpim"] {
      if @decode.lookup(row, flag) is Some(value) {
        match @decode.boolean(value) {
          Ok(false) => ()
          Ok(true) =>
            if !allow_direct_messages {
              return Err(InvalidCell(flag))
            }
          Err(_) => return Err(InvalidCell(flag))
        }
      }
    }
    let values = []
    for name in slack_channel_list_column_names() {
      // All columns are checked even when the eventual projection omits them.
      // Missing vendor observations stay NULL; never invent count zero,
      // empty topic/purpose, false flags or a creation instant.
      let cell = match name {
        "topic" | "purpose" =>
          match @decode.field(row, name) {
            Missing | ExplicitNull => None
            Present(value) => {
              guard @decode.open_object(value) is Ok(nested) else {
                return Err(InvalidCell(name))
              }
              @decode.lookup(nested, "value")
            }
          }
        "member_count" => @decode.lookup(row, "num_members")
        _ => @decode.lookup(row, name)
      }
      let contract = channel_field_contract(name)
      let value = match cell {
        None => {
          if name == "id" {
            return Err(InvalidCell(name))
          }
          if nodes < 1 {
            return Err(BudgetExceeded)
          }
          nodes -= 1
          @admitted.checked_null_value(contract).unwrap()
        }
        Some(cell) => {
          let value_limits : @admitted.Limits = {
            max_nodes: nodes,
            max_depth: limits.max_depth,
            max_text_bytes: text_bytes,
          }
          let (value, used_nodes, used_text) = if !@decode.is_null(cell) &&
            (name == "member_count" || name == "created") {
            let integer = match
              channel_original_integer(bytes, cell, limits.max_bytes) {
              Some(value) => value
              None => return Err(InvalidCell(name))
            }
            if integer < 0L {
              return Err(InvalidCell(name))
            }
            let runtime = if name == "member_count" {
              @admitted.signed64_value(integer)
            } else {
              if integer > 9223372036854775L {
                return Err(InvalidCell(name))
              }
              guard @admitted.epoch_milliseconds_timestamp(integer * 1000L)
                is Some(text) else {
                return Err(InvalidCell(name))
              }
              guard @admitted.checked_timestamp_value(
                  text,
                  @contract.with_nullability(contract, false),
                )
                is Some(checked) else {
                return Err(InvalidCell(name))
              }
              // Recheck the DATA under the original nullable column contract below.
              checked.value
            }
            guard @admitted.recheck_runtime_value_usage(
                runtime, contract, value_limits,
              )
              is Some(result) else {
              return Err(BudgetExceeded)
            }
            result
          } else {
            match @admitted.admit_usage(contract, cell, value_limits) {
              Ok(value) => value
              Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) =>
                return Err(BudgetExceeded)
              Err(_) => return Err(InvalidCell(name))
            }
          }
          nodes -= used_nodes
          text_bytes -= used_text
          value
        }
      }
      if name == "id" {
        guard value.value is @admitted.Text(id) && !id.is_empty() else {
          return Err(InvalidCell(name))
        }
        if ids.contains(id) {
          return Err(DuplicateChannel)
        }
        ids[id] = true
      }
      values.push(value)
    }
    rows.push(values)
  }
  Ok({ response_sha256: @sha.hex(bytes), next_cursor: next, rows, })
}

///|
pub fn slack_channel_list_ids(page : SlackChannelListPage) -> Array[String] {
  page.rows.map(row => {
    match row[0].value {
      @admitted.Text(id) => id
      _ => abort("checked Slack channel identity invariant")
    }
  })
}

///|
pub fn slack_channel_list_row_count(page : SlackChannelListPage) -> Int {
  page.rows.length()
}

///|
pub fn slack_channel_list_rows_wire(
  page : SlackChannelListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackChannelListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = slack_channel_list_column_names()
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
pub fn slack_channel_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackChannelListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let object = match
    @contract.object_contract(
      slack_channel_list_column_names().map(name => {
        (name, channel_field_contract(name))
      }),
      nullable=false,
      max_fields=8,
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
// This declares id within the selected workspace. A physical paged reader
// must still validate the whole selected input and original workspace; one
// page cannot prove that the next page has no duplicate id or repeated cursor.
pub fn slack_channel_list_facts_wire() -> String {
  "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"
}
