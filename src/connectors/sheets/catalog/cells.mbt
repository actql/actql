// Sheets codecs are pure provider semantics. They neither issue credentials
// nor decide authorization, retry, capture, or Effect settlement.

///|
pub(all) enum CellType {
  Text
  Number
  Boolean
} derive(Eq, Debug)

///|
pub(all) struct Column {
  name : String
  cell_type : CellType
  nullable : Bool
} derive(Eq, Debug)

///|
pub(all) struct GridRange {
  sheet_id : Int
  start_row : Int
  end_row : Int
  start_column : Int
  end_column : Int
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_cells : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidRange
  InvalidSchema
  InvalidResponse
  ForeignSpreadsheet
  ForeignSheet
  ForeignRange
  CellError(row~ : Int, column~ : String)
  MissingEffectiveValue(row~ : Int, column~ : String)
  RequiredCell(row~ : Int, column~ : String)
  InvalidCell(row~ : Int, column~ : String)
  UnrepresentableWrite(String)
} derive(Eq, Debug)

///|
pub struct Page {
  rows : Array[Json]
  excluded_blank_rows : Int
}

///|
/// Validate the publication's immutable spreadsheet and numeric sheet IDs.
/// Titles are not identity, and missing or non-grid sheets are not substituted.
pub fn check_target(
  body : Bytes,
  spreadsheet_id : String,
  range : GridRange,
  append_sheet_id : Int,
  columns : Array[Column],
  limits : Limits,
) -> Result[Unit, Issue] {
  match check_range(range, columns, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if append_sheet_id < 0 {
    return Err(InvalidRange)
  }
  let root = match parse_response_body(body, limits) {
    Ok(root) => root
    Err(issue) => return Err(issue)
  }
  guard acknowledgement_object(root) is Some(object) &&
    object.get("spreadsheetId") is Some(id) &&
    acknowledgement_text(id) == Some(spreadsheet_id) &&
    object.get("sheets") is Some(sheets) &&
    acknowledgement_array(sheets) is Some(sheets) else {
    return Err(ForeignSpreadsheet)
  }
  let ids = []
  let mut read_found = false
  let mut append_found = false
  for sheet in sheets {
    guard acknowledgement_object(sheet) is Some(sheet) &&
      sheet.get("properties") is Some(properties) &&
      acknowledgement_object(properties) is Some(properties) else {
      return Err(InvalidResponse)
    }
    let id = match properties.get("sheetId") {
      Some(value) =>
        match acknowledgement_int32(value) {
          Some(id) if id >= 0 => id
          _ => return Err(InvalidResponse)
        }
      None => 0
    }
    if ids.contains(id) {
      return Err(InvalidResponse)
    }
    ids.push(id)
    if id != range.sheet_id && id != append_sheet_id {
      continue
    }
    // The API defines an omitted sheetType as GRID.
    match properties.get("sheetType") {
      None => ()
      Some(kind) if acknowledgement_text(kind) == Some("GRID") => ()
      _ => return Err(InvalidResponse)
    }
    guard properties.get("gridProperties") is Some(grid) &&
      acknowledgement_object(grid) is Some(grid) &&
      grid.get("rowCount") is Some(rows) &&
      acknowledgement_int32(rows) is Some(rows) &&
      rows >= 0 &&
      grid.get("columnCount") is Some(width) &&
      acknowledgement_int32(width) is Some(width) &&
      width >= 0 else {
      return Err(InvalidResponse)
    }
    if id == range.sheet_id {
      if rows < range.end_row || width < range.end_column {
        return Err(ForeignRange)
      }
      read_found = true
    }
    if id == append_sheet_id {
      if width < columns.length() {
        return Err(ForeignRange)
      }
      append_found = true
    }
  }
  if !read_found || !append_found {
    Err(ForeignSheet)
  } else {
    Ok(())
  }
}

///|
pub fn page_rows(page : Page) -> Array[Json] {
  page.rows.copy()
}

///|
pub fn excluded_blank_rows(page : Page) -> Int {
  page.excluded_blank_rows
}

///|
fn check_limits(limits : Limits) -> Result[Unit, Issue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_cells < 1 {
    Err(InvalidLimits)
  } else {
    Ok(())
  }
}

///|
fn check_columns(columns : Array[Column]) -> Bool {
  if columns.is_empty() || columns.length() > 64 {
    return false
  }
  let names = []
  for column in columns {
    if column.name.is_empty() ||
      column.name.length() > 255 ||
      names.contains(column.name) {
      return false
    }
    names.push(column.name)
  }
  true
}

///|
fn check_range(
  range : GridRange,
  columns : Array[Column],
  limits : Limits,
) -> Result[Unit, Issue] {
  match check_limits(limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !check_columns(columns) {
    return Err(InvalidSchema)
  }
  if range.sheet_id < 0 ||
    range.start_row < 0 ||
    range.start_column < 0 ||
    range.end_row <= range.start_row ||
    range.end_column <= range.start_column ||
    range.end_column - range.start_column != columns.length() {
    return Err(InvalidRange)
  }
  // Division avoids overflowing before the finite rectangular bound check.
  if range.end_row - range.start_row > limits.max_cells / columns.length() {
    return Err(BudgetExceeded)
  }
  Ok(())
}

///|
fn parse_response_body(
  body : Bytes,
  limits : Limits,
) -> Result[@source.Node, Issue] {
  match check_limits(limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if body.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(body, {
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
  Ok(parsed)
}

///|
fn admit(body : Bytes, limits : Limits) -> Result[@decode.Cursor, Issue] {
  let parsed = match parse_response_body(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => Ok(value)
    Err(issue) =>
      Err(
        if issue.kind is @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
}

///|
// Only fresh, private parser results reach these target/acknowledgement projections.
// The Source owner already checked the entire tree, exact duplicate keys,
// Unicode, nodes/depth and byte spelling. Decoded key/value UTF8 totals cannot
// exceed that same original JSON input, so no second full index is needed.
// These views borrow nodes; they neither admit caller Nodes nor escape here.
fn acknowledgement_object(node : @source.Node) -> Map[String, @source.Node]? {
  guard node.value is @source.Object(fields) else { return None }
  let output : Map[String, @source.Node] = Map([])
  for field in fields {
    output[field.key] = field.value
  }
  Some(output)
}

///|
fn acknowledgement_array(node : @source.Node) -> Array[@source.Node]? {
  match node.value {
    @source.Array(items) => Some(items)
    _ => None
  }
}

///|
fn acknowledgement_object_length(node : @source.Node) -> Int? {
  match node.value {
    @source.Object(fields) => Some(fields.length())
    _ => None
  }
}

///|
fn acknowledgement_text(node : @source.Node) -> String? {
  match node.value {
    @source.String(text) => Some(text)
    _ => None
  }
}

///|
fn acknowledgement_int32(node : @source.Node) -> Int? {
  match node.value {
    @source.Number(number) =>
      @scalar.read_finite_number(number).bind(@scalar.read_int32)
    _ => None
  }
}

///|
fn integer_default(object : @decode.ObjectView, name : String) -> Int? {
  match @decode.field(object, name) {
    Missing => Some(0)
    Present(value) =>
      match @decode.int32(value) {
        Ok(number) if number >= 0 => Some(number)
        _ => None
      }
    ExplicitNull => None
  }
}

///|
fn array_default(
  object : @decode.ObjectView,
  name : String,
) -> Array[@decode.Cursor]? {
  match @decode.field(object, name) {
    Missing => Some([])
    Present(value) =>
      match @decode.elements(value) {
        Ok(elements) => Some(elements)
        _ => None
      }
    ExplicitNull => None
  }
}

///|
// None means an API-observed blank, not null, zero, false, or empty text.
fn effective_cell(
  cursor : @decode.Cursor,
  row : Int,
  column : Column,
) -> Result[Json?, Issue] {
  guard @decode.open_object(cursor) is Ok(cell) else {
    return Err(InvalidCell(row~, column=column.name))
  }
  let effective = match @decode.field(cell, "effectiveValue") {
    Missing =>
      // A supplied formula/literal without a reported effective value is not
      // proof of a blank. Formatting-only cells remain blanks.
      match @decode.field(cell, "userEnteredValue") {
        Missing => return Ok(None)
        Present(value) => {
          guard @decode.open_object(value) is Ok(_) &&
            @decode.object_length(value) is Some(0) else {
            return Err(MissingEffectiveValue(row~, column=column.name))
          }
          return Ok(None)
        }
        ExplicitNull => return Err(InvalidCell(row~, column=column.name))
      }
    Present(value) => value
    ExplicitNull => return Err(InvalidCell(row~, column=column.name))
  }
  guard @decode.open_object(effective) is Ok(value) else {
    return Err(InvalidCell(row~, column=column.name))
  }
  // ExtendedValue is a tagged union. A present empty value does not prove
  // an evaluated formula result, unlike an omitted effectiveValue on a blank.
  if @decode.object_length(effective) is Some(0) {
    return Err(MissingEffectiveValue(row~, column=column.name))
  }
  if @decode.lookup(value, "errorValue") is Some(_) {
    return Err(CellError(row~, column=column.name))
  }
  guard @decode.object_length(effective) is Some(1) else {
    return Err(InvalidCell(row~, column=column.name))
  }
  let result = match column.cell_type {
    Text =>
      match @decode.lookup(value, "stringValue") {
        Some(text) =>
          match @decode.text(text) {
            Ok(value) => Some(value.to_json())
            _ => None
          }
        None => None
      }
    Number =>
      match @decode.lookup(value, "numberValue") {
        Some(number) =>
          match @decode.finite_number(number) {
            Ok(value) => Some(value.to_json())
            _ => None
          }
        None => None
      }
    Boolean =>
      match @decode.lookup(value, "boolValue") {
        Some(boolean) =>
          match @decode.boolean(boolean) {
            Ok(value) => Some(value.to_json())
            _ => None
          }
        None => None
      }
  }
  match result {
    Some(value) => Ok(Some(value))
    None => Err(InvalidCell(row~, column=column.name))
  }
}

///|
/// One GridRange addressed by immutable sheet ID, not an A1 title. Callers
/// also request only spreadsheetId, sheetId, start offsets and typed values.
pub fn read_request(
  range : GridRange,
  columns : Array[Column],
  limits : Limits,
) -> Result[String, Issue] {
  match check_range(range, columns, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = read_request_document(range).stringify()
  match admit(@utf8.encode(body), limits) {
    Ok(_) => Ok(body)
    Err(issue) => Err(issue)
  }
}

///|
/// Original immutable read document. Validation remains in read_request;
/// constructor geometry shares this exact body, not another wire template.
pub fn read_request_document(range : GridRange) -> Json {
  {
    "dataFilters": [
      {
        "gridRange": {
          "sheetId": range.sheet_id.to_json(),
          "startRowIndex": range.start_row.to_json(),
          "endRowIndex": range.end_row.to_json(),
          "startColumnIndex": range.start_column.to_json(),
          "endColumnIndex": range.end_column.to_json(),
        },
      },
    ],
    "includeGridData": true,
  }
}

///|
/// Exclude only rows whose declared cells are all API-observed blanks.
/// Trailing omitted cells/rows are blank; declared partial rows must satisfy
/// nullability. Row order and duplicate rows survive projection unchanged.
pub fn project_grid(
  body : Bytes,
  spreadsheet_id : String,
  range : GridRange,
  columns : Array[Column],
  limits : Limits,
) -> Result[Page, Issue] {
  match check_range(range, columns, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let root = match admit(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "spreadsheetId") is Some(id) &&
    @decode.text(id) is Ok(answered) else {
    return Err(InvalidResponse)
  }
  if answered != spreadsheet_id {
    return Err(ForeignSpreadsheet)
  }
  guard array_default(object, "sheets") is Some(sheets) &&
    sheets.length() == 1 &&
    @decode.open_object(sheets[0]) is Ok(sheet) &&
    @decode.lookup(sheet, "properties") is Some(properties) &&
    @decode.open_object(properties) is Ok(props) &&
    integer_default(props, "sheetId") is Some(sheet_id) else {
    return Err(InvalidResponse)
  }
  if sheet_id != range.sheet_id {
    return Err(ForeignSheet)
  }
  guard array_default(sheet, "data") is Some(blocks) && blocks.length() <= 1 else {
    return Err(InvalidResponse)
  }
  let rows = if blocks.is_empty() {
    []
  } else {
    guard @decode.open_object(blocks[0]) is Ok(block) &&
      integer_default(block, "startRow") is Some(start_row) &&
      integer_default(block, "startColumn") is Some(start_column) else {
      return Err(InvalidResponse)
    }
    if start_row != range.start_row || start_column != range.start_column {
      return Err(ForeignRange)
    }
    guard array_default(block, "rowData") is Some(rows) else {
      return Err(InvalidResponse)
    }
    rows
  }
  let row_count = range.end_row - range.start_row
  if rows.length() > row_count {
    return Err(ForeignRange)
  }
  let output = []
  let mut excluded = row_count - rows.length()
  for index, row in rows {
    guard @decode.open_object(row) is Ok(object) &&
      array_default(object, "values") is Some(cells) else {
      return Err(InvalidResponse)
    }
    if cells.length() > columns.length() {
      return Err(ForeignRange)
    }
    let values = []
    let mut present = false
    for column_index, column in columns {
      let value = if column_index < cells.length() {
        match
          effective_cell(cells[column_index], range.start_row + index, column) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      } else {
        None
      }
      if value is Some(_) {
        present = true
      }
      values.push(value)
    }
    if !present {
      excluded += 1
      continue
    }
    let fields : Map[String, Json] = Map([])
    for column_index, column in columns {
      fields[column.name] = match values[column_index] {
        Some(value) => value
        None => {
          if !column.nullable {
            return Err(
              RequiredCell(row=range.start_row + index, column=column.name),
            )
          }
          Json::null()
        }
      }
    }
    output.push(Json::object(fields))
  }
  Ok({ rows: output, excluded_blank_rows: excluded, })
}

///|
/// Encode one row as literal typed cells. Null and empty text are refused:
/// this profile does not claim their distinction survives a Sheets write.
pub fn append_request(
  sheet_id : Int,
  columns : Array[Column],
  values : Array[Json],
  limits : Limits,
) -> Result[String, Issue] {
  match check_limits(limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !check_columns(columns) ||
    sheet_id < 0 ||
    values.length() != columns.length() {
    return Err(InvalidSchema)
  }
  if columns.length() > limits.max_cells {
    return Err(BudgetExceeded)
  }
  let cells = match literal_cells(columns, values) {
    Ok(cells) => cells
    Err(issue) => return Err(issue)
  }
  let body = append_request_document(sheet_id, cells).stringify()
  if @utf8.encode(body).length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  // Reuse the common bounded validator for the complete outgoing tree.
  match admit(@utf8.encode(body), limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(body)
}

///|
/// The original literal append document, after the caller has checked its
/// cells. This pure document builder admits no row or write. Constructor
/// geometry uses the same fixed document rather than a second wire template.
pub fn append_request_document(sheet_id : Int, cells : Array[Json]) -> Json {
  {
    "requests": [
      {
        "appendCells": {
          "sheetId": sheet_id.to_json(),
          "rows": [{ "values": Json::array(cells) }],
          "fields": "userEnteredValue",
        },
      },
    ],
  }
}

///|
fn literal_cells(
  columns : Array[Column],
  values : Array[Json],
) -> Result[Array[Json], Issue] {
  if values.length() != columns.length() {
    return Err(InvalidSchema)
  }
  let cells : Array[Json] = []
  for index, column in columns {
    match literal_cell_document(column.cell_type, values[index]) {
      Some(cell) => cells.push(cell)
      None => return Err(UnrepresentableWrite(column.name))
    }
  }
  Ok(cells)
}

///|
/// Original scalar cell representation, shared by the actual request builder
/// and its constructor geometry. It carries no row identity or write grant.
pub fn literal_cell_document(cell_type : CellType, value : Json) -> Json? {
  let extended : Json = match (cell_type, value) {
    (Text, String(value)) if !value.is_empty() =>
      { "stringValue": value.to_json() }
    (Number, Number(value, ..)) if !value.is_nan() && !value.is_inf() =>
      { "numberValue": value.to_json() }
    (Boolean, True) => { "boolValue": true }
    (Boolean, False) => { "boolValue": false }
    _ => return None
  }
  Some({ "userEnteredValue": extended })
}

///|
/// Overwrite exactly one complete rectangle with literal scalar values.
/// Sheets clears masked cells when a range has fewer supplied cells, so a
/// partial rectangle is refused rather than interpreted as a clear operation.
/// Coordinates identify this operation's range, never a stable row identity.
pub fn update_request(
  range : GridRange,
  columns : Array[Column],
  rows : Array[Array[Json]],
  limits : Limits,
) -> Result[String, Issue] {
  match check_range(range, columns, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if rows.length() != range.end_row - range.start_row {
    return Err(InvalidRange)
  }
  let encoded_rows : Array[Json] = []
  for row in rows {
    let cells = match literal_cells(columns, row) {
      Ok(cells) => cells
      Err(issue) => return Err(issue)
    }
    encoded_rows.push({ "values": Json::array(cells) })
  }
  let body = update_request_document(range, encoded_rows).stringify()
  if @utf8.encode(body).length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  // Account for the complete request envelope, not only the input cells.
  match admit(@utf8.encode(body), limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(body)
}

///|
/// Exact original literal update document after cell checking. Constructor
/// geometry borrows this fixed shape and never supplies accepted row data.
pub fn update_request_document(
  range : GridRange,
  encoded_rows : Array[Json],
) -> Json {
  {
    "requests": [
      {
        "updateCells": {
          "range": {
            "sheetId": range.sheet_id.to_json(),
            "startRowIndex": range.start_row.to_json(),
            "endRowIndex": range.end_row.to_json(),
            "startColumnIndex": range.start_column.to_json(),
            "endColumnIndex": range.end_column.to_json(),
          },
          "rows": Json::array(encoded_rows),
          "fields": "userEnteredValue",
        },
      },
    ],
  }
}

///|
pub(all) enum AppendOutcome {
  Applied
  Unknown
} derive(Eq, Debug)

///|
/// A batch acknowledgement is not a row ID or a physical row coordinate.
/// Unclassified HTTP failures and malformed/foreign acknowledgements remain
/// unknown. This function never authorizes retry or content-based lookup.
pub fn classify_append(
  status : Int,
  body : Bytes,
  spreadsheet_id : String,
  limits : Limits,
) -> AppendOutcome {
  if status != 200 {
    return Unknown
  }
  guard parse_response_body(body, limits) is Ok(root) &&
    acknowledgement_object(root) is Some(object) &&
    object.get("spreadsheetId") is Some(id) &&
    acknowledgement_text(id) is Some(answered) &&
    answered == spreadsheet_id &&
    object.get("replies") is Some(replies) &&
    acknowledgement_array(replies) is Some(items) &&
    items.length() == 1 &&
    acknowledgement_object_length(items[0]) is Some(0) else {
    return Unknown
  }
  Applied
}
