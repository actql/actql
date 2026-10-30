///|
pub(all) struct SheetTabsLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum SheetTabsIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  ForeignSpreadsheet
  DuplicateSheet(Int)
  InvalidCell(String)
  InvalidSelection(String)
} derive(Eq, Debug)

///|
/// Typed provider DATA, not a published Source, Account decision or read grant.
/// The shared Reader retains the original physical body and cleanup duties.
pub struct SheetTabsPage {
  spreadsheet_id : String
  response_sha256 : String
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
pub fn sheet_tabs_column_names() -> Array[String] {
  ["id", "title", "index", "row_count", "column_count"]
}

///|
fn sheet_tabs_contract(name : String) -> @contract.Contract {
  @contract.primitive(
    if name == "title" { @contract.StringType } else { @contract.Signed64Type },
    nullable=name == "row_count" || name == "column_count",
  )
}

///|
// Read the complete original numeric token before converting the documented
// nonnegative int32 provider field to a logical Signed64. Never round a JSON
// binary64 placeholder into a sheet key, position or grid extent.
fn sheet_tabs_integer(bytes : Bytes, cursor : @decode.Cursor, max_bytes : Int) -> Int? {
  guard @decode.view(cursor) is @decode.NumberValue(_) else { return None }
  let span = @decode.cursor_span(cursor)
  guard span.start_byte >= 0 &&
    span.end_byte > span.start_byte &&
    span.end_byte <= bytes.length() else { return None }
  let raw = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
    _ => return None
  }
  guard @admitted.normalize_decimal_text(raw, 10, 0, max_bytes) is Ok(text) &&
    @scalar.read_decimal_int64(text) is Ok(value) &&
    value >= 0L && value <= 2147483647L else { return None }
  Some(value.to_int())
}

///|
pub fn project_sheet_tabs(
  bytes : Bytes,
  spreadsheet_id : String,
  limits : SheetTabsLimits,
) -> Result[SheetTabsPage, SheetTabsIssue] {
  if limits.max_bytes <= 0 || limits.max_nodes <= 0 || limits.max_depth <= 0 ||
    limits.max_rows <= 0 || limits.max_value_nodes <= 0 ||
    limits.max_value_text_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if spreadsheet_id.is_empty() || spreadsheet_id.length() > 128 ||
    !spreadsheet_id.iter().all(c => (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_') {
    return Err(ForeignSpreadsheet)
  }
  let cursor = match admit(bytes, {
    max_bytes: limits.max_bytes, max_nodes: limits.max_nodes,
    max_depth: limits.max_depth, max_cells: 1,
  }) {
    Ok(cursor) => cursor
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(_) => return Err(InvalidResponse)
  }
  guard @decode.open_object(cursor) is Ok(root) &&
    @decode.lookup(root, "spreadsheetId") is Some(id) &&
    @decode.text(id) == Ok(spreadsheet_id) &&
    array_default(root, "sheets") is Some(sheets) else {
    return Err(ForeignSpreadsheet)
  }
  if sheets.length() > limits.max_rows { return Err(BudgetExceeded) }
  let rows = []
  let ids : Map[Int, Bool] = Map([])
  let mut nodes = limits.max_value_nodes
  let mut text_bytes = limits.max_value_text_bytes
  for sheet in sheets {
    guard @decode.open_object(sheet) is Ok(sheet) &&
      @decode.lookup(sheet, "properties") is Some(properties) &&
      @decode.open_object(properties) is Ok(properties) else {
      return Err(InvalidResponse)
    }
    let kind = match @decode.field(properties, "sheetType") {
      Missing => "GRID"
      Present(value) => match @decode.text(value) {
        Ok("GRID") => "GRID"
        Ok("OBJECT") => "OBJECT"
        Ok("DATA_SOURCE") => "DATA_SOURCE"
        _ => return Err(InvalidResponse)
      }
      ExplicitNull => return Err(InvalidResponse)
    }
    let grid = match @decode.field(properties, "gridProperties") {
      Missing if kind == "OBJECT" => None
      Present(value) if kind != "OBJECT" => match @decode.open_object(value) {
        Ok(grid) => Some(grid)
        Err(_) => return Err(InvalidResponse)
      }
      _ => return Err(InvalidResponse)
    }
    let values = []
    for name in sheet_tabs_column_names() {
      let contract = sheet_tabs_contract(name)
      let value_limits : @admitted.Limits = {
        max_nodes: nodes, max_depth: limits.max_depth, max_text_bytes: text_bytes,
      }
      let result = if name == "title" {
        guard @decode.lookup(properties, "title") is Some(value) else {
          return Err(InvalidCell(name))
        }
        match @admitted.admit_usage(contract, value, value_limits) {
          Ok(result) => result
          Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) => return Err(BudgetExceeded)
          Err(_) => return Err(InvalidCell(name))
        }
      } else {
        let value : @admitted.Value = if (name == "row_count" || name == "column_count") &&
          kind == "OBJECT" {
          guard @admitted.checked_null_value(contract) is Some(value) else {
            return Err(InvalidCell(name))
          }
          value.value
        } else {
          let selected = if name == "id" || name == "index" {
            @decode.lookup(properties, if name == "id" { "sheetId" } else { "index" })
          } else {
            @decode.lookup(grid.unwrap(), if name == "row_count" { "rowCount" } else { "columnCount" })
          }
          guard selected is Some(cell) &&
            sheet_tabs_integer(bytes, cell, limits.max_bytes) is Some(integer) else {
            return Err(InvalidCell(name))
          }
          if name == "id" {
            if ids.contains(integer) { return Err(DuplicateSheet(integer)) }
            ids[integer] = true
          }
          @admitted.signed64_value(integer.to_int64())
        }
        guard @admitted.recheck_runtime_value_usage(value, contract, value_limits) is Some(result) else {
          return Err(BudgetExceeded)
        }
        result
      }
      let (value, used_nodes, used_text) = result
      nodes -= used_nodes
      text_bytes -= used_text
      values.push(value)
    }
    rows.push(values)
  }
  Ok({ spreadsheet_id, response_sha256: @sha.hex(bytes), rows, })
}

///|
pub fn sheet_tabs_row_count(page : SheetTabsPage) -> Int {
  page.rows.length()
}

///|
pub fn sheet_tabs_rows_wire(
  page : SheetTabsPage, names : Array[String],
  max_bytes : Int, max_nodes : Int, max_depth : Int,
) -> Result[String, SheetTabsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 { return Err(InvalidLimits) }
  let columns = sheet_tabs_column_names()
  let selected : Array[(String, Int)] = []
  for name in names {
    if selected.any(entry => entry.0 == name) { return Err(InvalidSelection(name)) }
    let mut position = None
    for index, column in columns { if column == name { position = Some(index) } }
    guard position is Some(index) else { return Err(InvalidSelection(name)) }
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
    _ => { @encode.cancel_writer(writer); Err(BudgetExceeded) }
  }
}

///|
pub fn sheet_tabs_schema_wire(
  max_bytes : Int, max_nodes : Int, max_depth : Int,
) -> Result[String, SheetTabsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 { return Err(InvalidLimits) }
  let contract = match @contract.object_contract(
    sheet_tabs_column_names().map(name => (name, sheet_tabs_contract(name))),
    nullable=false, max_fields=5, max_name_bytes=64,
  ) {
    Ok(contract) => contract
    Err(_) => return Err(InvalidResponse)
  }
  guard contract.shape is @contract.Object(fields) else { return Err(InvalidResponse) }
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
    _ => { @encode.cancel_writer(writer); Err(BudgetExceeded) }
  }
}
