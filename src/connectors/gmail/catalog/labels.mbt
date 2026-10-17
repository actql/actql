///|
pub(all) struct GmailLabelListLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum GmailLabelListIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidSelection(String)
  DuplicateLabel
  InvalidCell(String)
} derive(Eq, Debug)

///|
// A bounded Gmail label observation, not a Source receipt, mailbox identity,
// OAuth scope or permission inferred from a label type. The physical owner
// retains the original mailbox/request/response relationship and raw custody.
pub struct GmailLabelListPage {
  response_sha256 : String
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
fn gmail_label_list_columns() -> Array[(String, String)] {
  [("id", "id"), ("name", "name"), ("type", "type")]
}

///|
pub fn gmail_label_list_column_names() -> Array[String] {
  gmail_label_list_columns().map(entry => entry.0)
}

///|
fn gmail_label_list_limits_valid(limits : GmailLabelListLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_rows > 0 &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0
}

///|
pub fn project_gmail_label_list(
  bytes : Bytes,
  limits : GmailLabelListLimits,
) -> Result[GmailLabelListPage, GmailLabelListIssue] {
  if !gmail_label_list_limits_valid(limits) {
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
  guard @decode.closed_object(cursor, ["labels"]) is Ok(root) else {
    return Err(InvalidResponse)
  }
  // This endpoint is a complete unpaged label list. Only the empty response
  // object can omit labels; a foreign messages/error/pagination envelope is
  // not an empty mailbox and must not silently complete the Source.
  let list = match @decode.field(root, "labels") {
    Missing => return Ok({ response_sha256: @sha.hex(bytes), rows: [], })
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
    let values = []
    for (name, native_name) in gmail_label_list_columns() {
      guard @decode.lookup(row, native_name) is Some(value) &&
        @decode.text(value) is Ok(text) else {
        return Err(InvalidCell(name))
      }
      if name == "id" {
        if text.is_empty() {
          return Err(InvalidCell(name))
        }
        if ids.contains(text) {
          return Err(DuplicateLabel)
        }
        ids[text] = true
      }
      if name == "type" && text != "system" && text != "user" {
        return Err(InvalidCell(name))
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
  Ok({ response_sha256: @sha.hex(bytes), rows, })
}

///|
pub fn gmail_label_list_row_count(page : GmailLabelListPage) -> Int {
  page.rows.length()
}

///|
// Key evidence belongs to this declared mailbox Source and is checked over
// the complete unpaged response, even when id is projected away later.
pub fn gmail_label_list_ids(page : GmailLabelListPage) -> Array[String] {
  page.rows.map(row => {
    match row[0].value {
      @admitted.Text(value) => value
      _ => abort("checked Gmail label string invariant")
    }
  })
}

///|
pub fn gmail_label_list_rows_wire(
  page : GmailLabelListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, GmailLabelListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = gmail_label_list_columns()
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
pub fn gmail_label_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, GmailLabelListIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let object = match
    @contract.object_contract(
      gmail_label_list_column_names().map(name => {
        (name, @contract.primitive(@contract.StringType, nullable=false))
      }),
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
    // The full fixed declared field map is ordered by Common's wire rule.
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
pub fn gmail_label_list_facts_wire() -> String {
  "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"
}
