///|
priv struct CellBudget {
  mut nodes : Int
  mut text_bytes : Int
  max_depth : Int
}

///|
fn admit_cell(
  cursor : @decode.Cursor,
  column : Column,
  budget : CellBudget,
) -> Result[@admitted.CheckedValue, ResponseIssue] {
  let (value, nodes, text) = match
    @admitted.admit_usage(column.contract, cursor, {
      max_nodes: budget.nodes,
      max_text_bytes: budget.text_bytes,
      max_depth: budget.max_depth,
    }) {
    Ok(value) => value
    Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) =>
      return Err(BudgetExceeded)
    Err(issue) => return Err(ValueAdmission(column.name, issue))
  }
  budget.nodes -= nodes
  budget.text_bytes -= text
  Ok(value)
}

///|
fn converted_cursor(
  node : @source.Node,
  column : Column,
  budget : CellBudget,
) -> Result[@admitted.CheckedValue, ResponseIssue] {
  let cursor = match
    @decode.admit(node, {
      max_nodes: budget.nodes,
      max_depth: budget.max_depth,
      max_string_bytes: budget.text_bytes,
      max_total_string_bytes: budget.text_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  admit_cell(cursor, column, budget)
}

///|
fn project_cell(
  cursor : @decode.Cursor,
  column : Column,
  budget : CellBudget,
) -> Result[@admitted.CheckedValue, ResponseIssue] {
  if @decode.is_null(cursor) {
    return admit_cell(cursor, column, budget)
  }
  // SQL API values are strings. Numeric JSON cells are not a convenient
  // substitute: doing so could silently lose the exact decimal spelling.
  guard @decode.text(cursor) is Ok(text) else {
    return Err(InvalidCell(column.name))
  }
  match column.native_type {
    "TEXT" | "text" => admit_cell(cursor, column, budget)
    "FIXED" | "fixed" => {
      guard column.precision is Some(precision) && column.scale is Some(scale) else {
        return Err(InvalidColumn(column.name))
      }
      let canonical = match
        @admitted.normalize_decimal_text(
          text,
          precision,
          scale,
          budget.text_bytes,
        ) {
        Ok(value) => value
        Err(InputLimit | InvalidLimits) => return Err(BudgetExceeded)
        Err(OutOfRange) => return Err(ValueOutOfRange(column.name))
        Err(BeyondScale) => return Err(ValueBeyondScale(column.name))
        Err(InvalidFormat) => return Err(InvalidCell(column.name))
      }
      converted_cursor(
        { value: String(canonical), span: @decode.cursor_span(cursor), },
        column,
        budget,
      )
    }
    "BOOLEAN" | "boolean" => {
      let flag = match text {
        "true" => true
        "false" => false
        _ => return Err(InvalidCell(column.name))
      }
      converted_cursor(
        { value: Bool(flag), span: @decode.cursor_span(cursor), },
        column,
        budget,
      )
    }
    "REAL" | "real" | "FLOAT" | "float" => {
      let node = match
        @source.parse_json_bytes_preserving(@utf8.encode(text), {
          max_input_bytes: budget.text_bytes,
          max_nodes: budget.nodes,
          max_depth: budget.max_depth,
        }) {
        Ok(value) => value
        Err(_) => return Err(InvalidCell(column.name))
      }
      guard node.value is Number(_) else {
        return Err(InvalidCell(column.name))
      }
      converted_cursor(node, column, budget)
    }
    "VARIANT" | "variant" | "OBJECT" | "object" | "ARRAY" | "array" => {
      let node = match
        @source.parse_json_bytes_preserving(@utf8.encode(text), {
          max_input_bytes: budget.text_bytes,
          max_nodes: budget.nodes,
          max_depth: budget.max_depth,
        }) {
        Ok(value) => value
        Err(_) => return Err(InvalidCell(column.name))
      }
      // OBJECT/ARRAY are declared vendor types, not arbitrary VARIANT values.
      if (column.native_type == "OBJECT" || column.native_type == "object") &&
        !(node.value is Object(_)) {
        return Err(InvalidCell(column.name))
      }
      if (column.native_type == "ARRAY" || column.native_type == "array") &&
        !(node.value is Array(_)) {
        return Err(InvalidCell(column.name))
      }
      converted_cursor(node, column, budget)
    }
    _ => Err(UnsupportedColumn(column.name, column.native_type))
  }
}

///|
fn project_rows(
  object : @decode.ObjectView,
  columns : Array[Column],
  expected_rows : Int64,
  limits : ResponseLimits,
) -> Result[Array[Array[@admitted.CheckedValue]], ResponseIssue] {
  guard @decode.lookup(object, "data") is Some(data) &&
    @decode.array_length(data) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  if count.to_int64() != expected_rows {
    return Err(InvalidPartition)
  }
  let rows = []
  let budget : CellBudget = {
    nodes: limits.max_nodes,
    text_bytes: limits.max_bytes,
    max_depth: limits.max_depth,
  }
  for index in 0..<count {
    let row = @decode.element_at(data, index).unwrap()
    guard @decode.array_length(row) is Some(width) && width == columns.length() else {
      return Err(WrongRowWidth)
    }
    let cells = []
    for ordinal in 0..<width {
      match
        project_cell(
          @decode.element_at(row, ordinal).unwrap(),
          columns[ordinal],
          budget,
        ) {
        Ok(value) => cells.push(value)
        Err(issue) => return Err(issue)
      }
    }
    rows.push(cells)
  }
  Ok(rows)
}
