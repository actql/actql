///|
pub(all) struct SlackUserListLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_cursor_bytes : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum SlackUserListIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidCursor
  InvalidSelection(String)
  DuplicateUser
  InvalidCell(String)
} derive(Eq, Debug)

///|
// This is one checked vendor page. It is not a workspace selection, token
// scope, complete paged Source, current authorization or custody receipt.
pub struct SlackUserListPage {
  response_sha256 : String
  next_cursor : String?
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
pub fn slack_user_list_column_names() -> Array[String] {
  [
    "id", "name", "real_name", "display_name", "email", "tz", "is_bot", "deleted",
  ]
}

///|
fn user_field_contract(name : String) -> @contract.Contract {
  @contract.primitive(
    if name == "is_bot" || name == "deleted" {
      @contract.BooleanType
    } else {
      @contract.StringType
    },
    nullable=name != "id",
  )
}

///|
pub fn project_slack_user_list(
  bytes : Bytes,
  limits : SlackUserListLimits,
) -> Result[SlackUserListPage, SlackUserListIssue] {
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
    Err(_) => return Err(InvalidResponse)
  }
  guard @decode.open_object(cursor) is Ok(root) &&
    @decode.lookup(root, "ok") is Some(ok) &&
    @decode.boolean(ok) is Ok(true) &&
    @decode.lookup(root, "error") is None &&
    @decode.lookup(root, "members") is Some(members) &&
    @decode.array_length(members) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  // Unknown bounded vendor fields are retained in the original response by
  // the physical owner. They are not interpreted as ActQL columns or grants.
  // An absent/empty next_cursor is terminal; null/wrong type is not terminal.
  let next = match @decode.field(root, "response_metadata") {
    Missing => None
    ExplicitNull => return Err(InvalidCursor)
    Present(metadata) => {
      guard @decode.open_object(metadata) is Ok(metadata) else {
        return Err(InvalidCursor)
      }
      match @decode.field(metadata, "next_cursor") {
        Missing => None
        ExplicitNull => return Err(InvalidCursor)
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
    let profile = match @decode.field(row, "profile") {
      Missing | ExplicitNull => None
      Present(value) =>
        match @decode.open_object(value) {
          Ok(value) => Some(value)
          Err(_) => return Err(InvalidCell("profile"))
        }
    }
    let values = []
    for name in slack_user_list_column_names() {
      // profile.real_name is the original profile value; the top-level
      // legacy copy is never a fallback or a key. Email absence is not a
      // users:read.email grant, and absent booleans are not fabricated false.
      let cell = if name == "real_name" ||
        name == "display_name" ||
        name == "email" {
        match profile {
          Some(profile) => @decode.lookup(profile, name)
          None => None
        }
      } else {
        @decode.lookup(row, name)
      }
      let contract = user_field_contract(name)
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
          let (value, used_nodes, used_text) = match
            @admitted.admit_usage(contract, cell, {
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
          value
        }
      }
      if name == "id" {
        guard value.value is @admitted.Text(id) && !id.is_empty() else {
          return Err(InvalidCell(name))
        }
        if ids.contains(id) {
          return Err(DuplicateUser)
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
pub fn slack_user_list_ids(page : SlackUserListPage) -> Array[String] {
  page.rows.map(row => {
    match row[0].value {
      @admitted.Text(id) => id
      _ => abort("checked Slack user identity invariant")
    }
  })
}

///|
pub fn slack_user_list_rows_wire(
  page : SlackUserListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackUserListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = slack_user_list_column_names()
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
pub fn slack_user_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackUserListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let object = match
    @contract.object_contract(
      slack_user_list_column_names().map(name => {
        (name, user_field_contract(name))
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
pub fn slack_user_list_facts_wire() -> String {
  "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"
}
