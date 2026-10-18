///|
pub(all) struct NotionUserListLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_cursor_bytes : Int
  max_identity_bytes : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum NotionUserListIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidCursor
  DuplicateUser
  InvalidCell(String)
  InvalidSelection(String)
} derive(Eq, Debug)

///|
/// One checked vendor page, not a token, workspace issuer, complete Source,
/// physical response retirement receipt or permission to fetch another page.
pub struct NotionUserListPage {
  response_sha256 : String
  next_cursor : String?
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
pub fn notion_user_list_column_names() -> Array[String] {
  ["id", "name", "type", "email"]
}

///|
fn user_contract(name : String) -> @contract.Contract {
  @contract.primitive(@contract.StringType, nullable=name != "id")
}

///|
fn text_is(view : @decode.ObjectView, name : String, expected : String) -> Bool {
  @decode.lookup(view, name).map(value => @decode.text(value) == Ok(expected)) ==
  Some(true)
}

///|
pub fn project_notion_user_list(
  bytes : Bytes,
  limits : NotionUserListLimits,
) -> Result[NotionUserListPage, NotionUserListIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_rows < 0 ||
    limits.max_cursor_bytes <= 0 ||
    limits.max_identity_bytes <= 0 ||
    limits.max_value_nodes < 0 ||
    limits.max_value_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let source = match
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
    @decode.admit(source, {
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
    text_is(root, "object", "list") &&
    text_is(root, "type", "user") &&
    @decode.lookup(root, "user") is Some(details) &&
    @decode.open_object(details) is Ok(_) &&
    @decode.lookup(root, "results") is Some(results) &&
    @decode.array_length(results) is Some(count) &&
    @decode.lookup(root, "has_more") is Some(more) &&
    @decode.boolean(more) is Ok(has_more) else {
    return Err(InvalidResponse)
  }
  if count > 100 {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let next = match @decode.field(root, "next_cursor") {
    ExplicitNull if !has_more => None
    Present(value) if has_more => {
      guard @decode.text(value) is Ok(text) && !text.is_empty() else {
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
        Ok(_) => Some(text)
        Err(_) => return Err(BudgetExceeded)
      }
    }
    _ => return Err(InvalidCursor)
  }
  let rows = []
  let ids : Map[String, Bool] = Map([])
  let mut nodes = limits.max_value_nodes
  let mut text_bytes = limits.max_value_text_bytes
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(results, index).unwrap())
      is Ok(row) &&
      text_is(row, "object", "user") else {
      return Err(InvalidResponse)
    }
    let kind = match @decode.field(row, "type") {
      Missing | ExplicitNull => None
      Present(value) =>
        match @decode.text(value) {
          Ok("person") => Some("person")
          Ok("bot") => Some("bot")
          _ => return Err(InvalidCell("type"))
        }
    }
    let person = match kind {
      Some("person") => {
        guard @decode.lookup(row, "person") is Some(value) &&
          @decode.open_object(value) is Ok(person) else {
          return Err(InvalidCell("person"))
        }
        Some(person)
      }
      Some("bot") => {
        guard @decode.lookup(row, "bot") is Some(value) &&
          @decode.open_object(value) is Ok(_) else {
          return Err(InvalidCell("bot"))
        }
        None
      }
      _ => None
    }
    let cells = []
    for name in notion_user_list_column_names() {
      // A person.email belongs only to the actual person variant. Do not
      // infer a user kind or permission from a similarly shaped extra object.
      let cell = if name == "email" {
        match person {
          Some(person) => @decode.lookup(person, "email")
          None => None
        }
      } else {
        @decode.lookup(row, name)
      }
      let contract = user_contract(name)
      let value = match cell {
        None => {
          if name == "id" {
            return Err(InvalidCell(name))
          }
          if nodes == 0 {
            return Err(BudgetExceeded)
          }
          nodes -= 1
          @admitted.checked_null_value(contract).unwrap()
        }
        Some(cell) => {
          let allowance = if name == "id" {
            text_bytes.min(limits.max_identity_bytes)
          } else {
            text_bytes
          }
          let (value, used_nodes, used_text) = match
            @admitted.admit_usage(contract, cell, {
              max_nodes: nodes,
              max_depth: limits.max_depth,
              max_text_bytes: allowance,
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
      cells.push(value)
    }
    rows.push(cells)
  }
  Ok({ response_sha256: @sha.hex(bytes), next_cursor: next, rows, })
}

///|
pub fn notion_user_list_ids(page : NotionUserListPage) -> Array[String] {
  page.rows.map(row => {
    match row[0].value {
      @admitted.Text(id) => id
      _ => abort("checked Notion user identity invariant")
    }
  })
}

///|
pub fn notion_user_list_row_count(page : NotionUserListPage) -> Int {
  page.rows.length()
}

///|
pub fn notion_user_list_metadata_wire(
  page : NotionUserListPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionUserListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "nextCursor")
    match page.next_cursor {
      Some(cursor) => @encode.string_value(writer, cursor)
      None => @encode.null_value(writer)
    }
    @encode.ordered_key(writer, "rowCount")
    @encode.number_value(writer, page.rows.length().to_double())
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
pub fn notion_user_list_rows_wire(
  page : NotionUserListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionUserListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = notion_user_list_column_names()
  let selected : Array[(String, Int)] = []
  for name in names {
    if selected.any(entry => entry.0 == name) {
      return Err(InvalidSelection(name))
    }
    let index = columns.search(name)
    guard index is Some(index) else { return Err(InvalidSelection(name)) }
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
pub fn notion_user_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionUserListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let object = match
    @contract.object_contract(
      notion_user_list_column_names().map(name => (name, user_contract(name))),
      nullable=false,
      max_fields=4,
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
/// The original reader rejects duplicate ids within and across response pages.
/// This declaration does not issue a Reference or mutation identity.
pub fn notion_user_list_facts_wire() -> String {
  "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"
}
