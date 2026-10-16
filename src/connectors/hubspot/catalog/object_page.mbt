///|
pub(all) struct ObjectPageLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_columns : Int
  max_cursor_units : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum ObjectPageIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  DuplicateSelection(String)
  Property(PropertyIssue)
  DuplicateRecord(String)
  ArchivedRecord
  MissingProperty(String)
  InvalidCell(String)
  DecimalCell(String, @admitted.DecimalTextIssue)
  ValueAdmission(String, @admitted.Issue)
  InvalidCursor
} derive(Eq, Debug)

///|
/// Observed provider identity and Common-admitted cells, not a Relation,
/// acquisition receipt, writable target or fresh authorization.
pub struct ObjectRow {
  id : String
  priv values : Array[@admitted.CheckedValue]
}

///|
pub struct ObjectPage {
  object_type : String
  response_sha256 : String
  next_after : String?
  priv names : Array[String]
  priv rows : Array[ObjectRow]
}

///|
priv struct ObjectValueBudget {
  mut nodes : Int
  mut text_bytes : Int
  depth : Int
}

///|
fn object_page_limits_valid(limits : ObjectPageLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_rows > 0 &&
  limits.max_columns > 0 &&
  limits.max_cursor_units > 0 &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0
}

///|
// Normalize the provider's documented UTC/millisecond spellings through the
// existing Common epoch conversion. No local timezone or binary64 conversion.
fn hubspot_temporal(text : String, date : Bool) -> String? {
  if date && text.length() == 10 && text[4] == '-' && text[7] == '-' {
    return Some(text)
  }
  let utc = if text.has_suffix("+00:00") {
    text[:text.length() - 6].to_owned() + "Z"
  } else if text.has_suffix("+0000") {
    text[:text.length() - 5].to_owned() + "Z"
  } else {
    text
  }
  let timestamp = if utc.has_suffix("Z") {
    match utc.length() {
      20 => utc[:19].to_owned() + ".000Z"
      22 => utc[:21].to_owned() + "00Z"
      23 => utc[:22].to_owned() + "0Z"
      24 => utc
      _ => return None
    }
  } else {
    let start = if text.has_prefix("-") { 1 } else { 0 }
    if start == text.length() {
      return None
    }
    for index in start..<text.length() {
      if text[index] < '0' || text[index] > '9' {
        return None
      }
    }
    let milliseconds : Int64 = @string.from_str(text) catch { _ => return None }
    guard @admitted.epoch_milliseconds_timestamp(milliseconds) is Some(value) else {
      return None
    }
    value
  }
  guard @admitted.timestamp_epoch_milliseconds(timestamp) is Some(_) else {
    return None
  }
  if date {
    if timestamp.has_suffix("T00:00:00.000Z") {
      Some(timestamp[:10].to_owned())
    } else {
      None
    }
  } else {
    Some(timestamp)
  }
}

///|
fn object_cell_source(
  cursor : @decode.Cursor,
  property : PropertyMetadata,
  budget : ObjectValueBudget,
  max_input_units : Int,
) -> Result[@source.Value, ObjectPageIssue] {
  if @decode.is_null(cursor) {
    return Ok(Null)
  }
  guard @decode.text(cursor) is Ok(value) else {
    return Err(InvalidCell(property.name))
  }
  match property.native_type {
    "number" => {
      if value.is_empty() {
        return Ok(Null)
      }
      match @admitted.normalize_decimal_text(value, 38, 10, max_input_units) {
        Ok(value) => Ok(String(value))
        Err(issue) => Err(DecimalCell(property.name, issue))
      }
    }
    "bool" =>
      match value {
        "" => Ok(Null)
        "true" => Ok(Bool(true))
        "false" => Ok(Bool(false))
        _ => Err(InvalidCell(property.name))
      }
    "date" | "datetime" => {
      if value.is_empty() {
        return Ok(Null)
      }
      match hubspot_temporal(value, property.native_type == "date") {
        Some(value) => Ok(String(value))
        None => Err(InvalidCell(property.name))
      }
    }
    "enumeration" if property.field_type == "checkbox" => {
      if value.is_empty() {
        return Ok(Array([]))
      }
      // Bound the array before split allocates its elements. Each output item
      // consumes a Common value node in addition to the array itself.
      let mut count = 1
      for unit in value {
        if unit == ';' {
          if count >= budget.nodes {
            return Err(BudgetExceeded)
          }
          count += 1
        }
      }
      if count >= budget.nodes {
        return Err(BudgetExceeded)
      }
      let values : Array[@source.Node] = []
      for item in value.split(";") {
        if item.is_empty() {
          return Err(InvalidCell(property.name))
        }
        values.push({
          value: String(item.to_owned()),
          span: @decode.cursor_span(cursor),
        })
      }
      Ok(Array(values))
    }
    "enumeration" => if value.is_empty() { Ok(Null) } else { Ok(String(value)) }
    _ => Ok(String(value))
  }
}

///|
fn object_cell(
  cursor : @decode.Cursor,
  property : PropertyMetadata,
  contract : @contract.Contract,
  budget : ObjectValueBudget,
  max_input_units : Int,
) -> Result[@admitted.CheckedValue, ObjectPageIssue] {
  let value = match
    object_cell_source(cursor, property, budget, max_input_units) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let converted = match
    @decode.admit({ value, span: @decode.cursor_span(cursor), }, {
      max_nodes: budget.nodes,
      max_depth: budget.depth,
      max_string_bytes: budget.text_bytes,
      max_total_string_bytes: budget.text_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  let (checked, nodes, text) = match
    @admitted.admit_usage(contract, converted, {
      max_nodes: budget.nodes,
      max_depth: budget.depth,
      max_text_bytes: budget.text_bytes,
    }) {
    Ok(value) => value
    Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) =>
      return Err(BudgetExceeded)
    Err(issue) => return Err(ValueAdmission(property.name, issue))
  }
  budget.nodes -= nodes
  budget.text_bytes -= text
  Ok(checked)
}

///|
fn object_page_after(
  root : @decode.ObjectView,
  max_units : Int,
) -> Result[String?, ObjectPageIssue] {
  match @decode.field(root, "paging") {
    Missing => Ok(None)
    ExplicitNull => Err(InvalidCursor)
    Present(cursor) => {
      guard @decode.open_object(cursor) is Ok(paging) else {
        return Err(InvalidCursor)
      }
      match @decode.field(paging, "next") {
        Missing => Ok(None)
        ExplicitNull => Err(InvalidCursor)
        Present(cursor) => {
          guard @decode.open_object(cursor) is Ok(next) &&
            text(next, "after") is Some(after) &&
            !after.is_empty() &&
            after.length() <= max_units else {
            return Err(InvalidCursor)
          }
          // Never follow the response's link/host. The physical caller builds
          // the next request on the same authenticated object endpoint.
          Ok(Some(after))
        }
      }
    }
  }
}

///|
pub fn project_object_page(
  bytes : Bytes,
  catalog : PropertyCatalog,
  names : Array[String],
  limits : ObjectPageLimits,
) -> Result[ObjectPage, ObjectPageIssue] {
  if !object_page_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes || names.length() > limits.max_columns {
    return Err(BudgetExceeded)
  }
  let selected = []
  let seen : Map[String, Bool] = Map([])
  for name in names {
    if seen.contains(name) {
      return Err(DuplicateSelection(name))
    }
    let contract = match property_contract(catalog, name) {
      Ok(value) => value
      Err(issue) => return Err(Property(issue))
    }
    selected.push((property_named(catalog, name).unwrap(), contract))
    seen[name] = true
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
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(root) is Ok(root) &&
    @decode.lookup(root, "results") is Some(list) &&
    @decode.array_length(list) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let next_after = match object_page_after(root, limits.max_cursor_units) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let budget : ObjectValueBudget = {
    nodes: limits.max_value_nodes,
    text_bytes: limits.max_value_text_bytes,
    depth: limits.max_depth,
  }
  let rows = []
  let ids : Map[String, Bool] = Map([])
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(list, index).unwrap())
      is Ok(row) &&
      text(row, "id") is Some(id) &&
      !id.is_empty() &&
      flag(row, "archived") is Ok(Some(archived)) &&
      @decode.lookup(row, "properties") is Some(properties) &&
      @decode.open_object(properties) is Ok(properties) else {
      return Err(InvalidResponse)
    }
    if archived {
      return Err(ArchivedRecord)
    }
    if ids.contains(id) {
      return Err(DuplicateRecord(id))
    }
    ids[id] = true
    // IDs are retained too, under the same output text/node budget.
    let id_contract = @contract.primitive(@contract.StringType, nullable=false)
    let id_property : PropertyMetadata = {
      name: "id",
      native_type: "string",
      field_type: "text",
      options: [],
      unique: true,
      writable: Some(false),
    }
    match
      object_cell(
        @decode.lookup(row, "id").unwrap(),
        id_property,
        id_contract,
        budget,
        limits.max_bytes,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let values = []
    for (property, contract) in selected {
      guard @decode.lookup(properties, property.name) is Some(cursor) else {
        return Err(MissingProperty(property.name))
      }
      match object_cell(cursor, property, contract, budget, limits.max_bytes) {
        Ok(value) => values.push(value)
        Err(issue) => return Err(issue)
      }
    }
    rows.push({ id, values, })
  }
  Ok({
    object_type: catalog.object_type,
    response_sha256: @sha.hex(bytes),
    next_after,
    names: names.copy(),
    rows,
  })
}

///|
pub fn object_page_rows(page : ObjectPage) -> Array[ObjectRow] {
  page.rows.copy()
}

///|
pub fn object_page_columns(page : ObjectPage) -> Array[String] {
  page.names.copy()
}

///|
pub fn object_row_values(row : ObjectRow) -> Array[@admitted.CheckedValue] {
  row.values.copy()
}
