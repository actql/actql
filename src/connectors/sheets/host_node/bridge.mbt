// Pure provider projection. The common Host owns admission, credentials,
// attempts, capture, approval and cleanup; no bridge entry performs I/O.

///|
fn issue_json(issue : @catalog.Issue) -> Json {
  match issue {
    CellError(row~, column~) =>
      { "kind": "CellError", "row": row.to_json(), "column": column.to_json() }
    MissingEffectiveValue(row~, column~) =>
      {
        "kind": "MissingEffectiveValue",
        "row": row.to_json(),
        "column": column.to_json(),
      }
    RequiredCell(row~, column~) =>
      {
        "kind": "RequiredCell",
        "row": row.to_json(),
        "column": column.to_json(),
      }
    InvalidCell(row~, column~) =>
      {
        "kind": "InvalidCell",
        "row": row.to_json(),
        "column": column.to_json(),
      }
    UnrepresentableWrite(column) =>
      { "kind": "UnrepresentableWrite", "column": column.to_json() }
    InvalidLimits => { "kind": "InvalidLimits" }
    BudgetExceeded => { "kind": "BudgetExceeded" }
    InvalidRange => { "kind": "InvalidRange" }
    InvalidSchema => { "kind": "InvalidSchema" }
    InvalidResponse => { "kind": "InvalidResponse" }
    ForeignSpreadsheet => { "kind": "ForeignSpreadsheet" }
    ForeignSheet => { "kind": "ForeignSheet" }
    ForeignRange => { "kind": "ForeignRange" }
  }
}

///|
fn parse_wire(text : String, limits : @catalog.Limits) -> @decode.Cursor? {
  guard @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(parsed) else {
    return None
  }
  match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn columns_of(
  text : String,
  limits : @catalog.Limits,
) -> Array[@catalog.Column]? {
  guard parse_wire(text, limits) is Some(root) &&
    @decode.elements(root) is Ok(items) &&
    items.length() > 0 &&
    items.length() <= 64 else {
    return None
  }
  let columns : Array[@catalog.Column] = []
  let names = []
  for item in items {
    guard @decode.closed_object(item, ["name", "type", "nullable"])
      is Ok(object) &&
      @decode.lookup(object, "name") is Some(name) &&
      @decode.text(name) is Ok(name) &&
      !name.is_empty() &&
      name.length() <= 255 &&
      !names.contains(name) &&
      @decode.lookup(object, "nullable") is Some(nullable) &&
      @decode.boolean(nullable) is Ok(nullable) &&
      @decode.lookup(object, "type") is Some(kind) &&
      @decode.text(kind) is Ok(kind) else {
      return None
    }
    let cell_type : @catalog.CellType = match kind {
      "string" => Text
      "number" => Number
      "boolean" => Boolean
      _ => return None
    }
    names.push(name)
    columns.push({ name, cell_type, nullable, })
  }
  Some(columns)
}

///|
#export_name("sheetsGridRequestJson")
pub fn sheets_grid_request_json(
  columns : String,
  sheet_id : Int,
  start_row : Int,
  end_row : Int,
  start_column : Int,
  end_column : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> String {
  let limits : @catalog.Limits = { max_bytes, max_nodes, max_depth, max_cells, }
  guard columns_of(columns, limits) is Some(columns) else {
    return ({ "refused": issue_json(InvalidSchema) } : Json).stringify()
  }
  let result : Json = match
    @catalog.read_request(
      { sheet_id, start_row, end_row, start_column, end_column, },
      columns,
      limits,
    ) {
    Ok(body) => { "body": body.to_json() }
    Err(issue) => { "refused": issue_json(issue) }
  }
  result.stringify()
}

///|
#export_name("sheetsGridPageJson")
pub fn sheets_grid_page_json(
  body : Bytes,
  spreadsheet_id : String,
  columns : String,
  sheet_id : Int,
  start_row : Int,
  end_row : Int,
  start_column : Int,
  end_column : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> String {
  let limits : @catalog.Limits = { max_bytes, max_nodes, max_depth, max_cells, }
  guard columns_of(columns, limits) is Some(columns) else {
    return ({ "refused": issue_json(InvalidSchema) } : Json).stringify()
  }
  let result : Json = match
    @catalog.project_grid(
      body,
      spreadsheet_id,
      { sheet_id, start_row, end_row, start_column, end_column, },
      columns,
      limits,
    ) {
    Ok(page) =>
      {
        "page": {
          "rows": Json::array(@catalog.page_rows(page)),
          "excludedBlankRows": @catalog.excluded_blank_rows(page).to_json(),
        },
      }
    Err(issue) => { "refused": issue_json(issue) }
  }
  result.stringify()
}

///|
#export_name("sheetsAppendRequestJson")
pub fn sheets_append_request_json(
  columns : String,
  row : String,
  sheet_id : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> String {
  let limits : @catalog.Limits = { max_bytes, max_nodes, max_depth, max_cells, }
  guard columns_of(columns, limits) is Some(columns) &&
    parse_wire(row, limits) is Some(root) &&
    @decode.closed_object(root, columns.map(column => column.name))
    is Ok(object) &&
    @decode.object_length(root) == Some(columns.length()) else {
    return ({ "refused": issue_json(InvalidSchema) } : Json).stringify()
  }
  let values = []
  for column in columns {
    guard @decode.lookup(object, column.name) is Some(value) else {
      return (
        { "refused": issue_json(UnrepresentableWrite(column.name)) } : Json).stringify()
    }
    let scalar : Json = match @decode.view(value) {
      NullValue => Json::null()
      TextValue(text) => text.to_json()
      NumberValue(number) => number.to_json()
      BoolValue(boolean) => boolean.to_json()
      _ =>
        return (
          { "refused": issue_json(UnrepresentableWrite(column.name)) } : Json).stringify()
    }
    values.push(scalar)
  }
  let result : Json = match
    @catalog.append_request(sheet_id, columns, values, limits) {
    Ok(body) => { "body": body.to_json() }
    Err(issue) => { "refused": issue_json(issue) }
  }
  result.stringify()
}

///|
#export_name("sheetsAppendOutcomeJson")
pub fn sheets_append_outcome_json(
  status : Int,
  body : Bytes,
  spreadsheet_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> String {
  let result : Json = match
    @catalog.classify_append(status, body, spreadsheet_id, {
      max_bytes,
      max_nodes,
      max_depth,
      max_cells,
    }) {
    Applied => { "outcome": "Applied" }
    Unknown => { "outcome": "Unknown" }
  }
  result.stringify()
}

///|
#export_name("sheetsTargetJson")
pub fn sheets_target_json(
  body : Bytes,
  spreadsheet_id : String,
  columns : String,
  sheet_id : Int,
  start_row : Int,
  end_row : Int,
  start_column : Int,
  end_column : Int,
  append_sheet_id : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> String {
  let limits : @catalog.Limits = { max_bytes, max_nodes, max_depth, max_cells, }
  guard columns_of(columns, limits) is Some(columns) else {
    return ({ "refused": issue_json(InvalidSchema) } : Json).stringify()
  }
  let result : Json = match
    @catalog.check_target(
      body,
      spreadsheet_id,
      { sheet_id, start_row, end_row, start_column, end_column, },
      append_sheet_id,
      columns,
      limits,
    ) {
    Ok(_) => { "checked": true }
    Err(issue) => { "refused": issue_json(issue) }
  }
  result.stringify()
}
