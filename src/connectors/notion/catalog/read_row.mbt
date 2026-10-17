///|
pub(all) struct NotionReadRowLimits {
  values : @admitted.Limits
  max_columns : Int
  max_work : Int
}

///|
pub(all) enum NotionReadRowIssue {
  InvalidLimits
  ForeignOriginal
  InvalidColumn
  AlreadySupplied
  Incomplete
  BudgetExceeded
  Cell(NotionReadCellIssue)
  Property(NotionPropertyItemIssue)
  InvalidValue
  InvalidSystemField(String)
} derive(Eq, Debug)

///|
/// Local assembly under the same query row and complete original checked
/// property schema. This is not a Source/Run, installation or capacity issuer.
pub struct NotionReadRow {
  priv original_self : Ref[NotionReadRow?]
  priv binding : NotionDataSourceReadContracts
  priv row : OriginalNotionQueryRow
  priv limits : NotionReadRowLimits
  priv cells : Array[@admitted.CheckedValue?]
  priv mut nodes : Int
  priv mut text : Int
  priv mut work : Int
  priv mut complete : (@admitted.CheckedValue, Int, Int)?
}

///|
fn read_row_is_original(row : NotionReadRow) -> Bool {
  match row.original_self.val {
    Some(original) => physical_equal(row, original)
    None => false
  }
}

///|
fn read_row_spend(row : NotionReadRow, units : Int) -> Bool {
  if units < 0 || units > row.work {
    false
  } else {
    row.work -= units
    true
  }
}

///|
fn read_row_store(
  row : NotionReadRow,
  column : Int,
  value : (@admitted.CheckedValue, Int, Int),
) -> Result[Unit, NotionReadRowIssue] {
  let (checked, input_nodes, input_text) = value
  if !physical_equal(checked.contract, notion_row_column(row.binding, column).1) {
    return Err(ForeignOriginal)
  }
  if !read_row_spend(row, input_nodes) || !read_row_spend(row, input_text) {
    return Err(BudgetExceeded)
  }
  // Incoming wire usage and logical runtime usage are distinct. For example,
  // a Decimal source token includes a decimal point, but the retained logical
  // Value has an exact coefficient. Common measures that original Value; JS
  // never rounds/reparses it and input work is still charged above.
  guard @admitted.recheck_runtime_value_usage(checked.value, checked.contract, {
      ..row.limits.values,
      max_depth: row.limits.values.max_depth - 1,
    })
    is Some((_, nodes, text)) else {
    return Err(InvalidValue)
  }
  if nodes > row.limits.values.max_nodes - row.nodes ||
    text > row.limits.values.max_text_bytes - row.text ||
    !read_row_spend(row, nodes) ||
    !read_row_spend(row, text) {
    return Err(BudgetExceeded)
  }
  row.nodes += nodes
  row.text += text
  row.cells[column] = Some(checked)
  Ok(())
}

///|
pub fn start_notion_read_row(
  binding : NotionDataSourceReadContracts,
  page : OriginalNotionQueryPage,
  row_index : Int,
  limits : NotionReadRowLimits,
) -> Result[NotionReadRow, NotionReadRowIssue] {
  if limits.values.max_nodes <= 0 ||
    limits.values.max_depth <= 0 ||
    limits.values.max_text_bytes < 0 ||
    limits.max_columns <= 0 ||
    limits.max_work <= 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(page.source, binding.source) {
    return Err(ForeignOriginal)
  }
  guard notion_query_page_row_at(page, row_index) is Some(original) else {
    return Err(InvalidColumn)
  }
  let count = notion_row_column_count(binding)
  if count > 0 && limits.values.max_depth <= 1 {
    return Err(BudgetExceeded)
  }
  if count > limits.max_columns ||
    count > limits.values.max_nodes - 1 ||
    count > limits.max_work {
    return Err(BudgetExceeded)
  }
  let original_self : Ref[NotionReadRow?] = Ref(None)
  let row = {
    original_self,
    binding,
    row: original,
    limits,
    cells: Array::make(count, None),
    nodes: 1,
    text: 0,
    work: limits.max_work - count,
    complete: None,
  }
  original_self.val = Some(row)
  let child_limits = {
    ..limits.values,
    max_depth: limits.values.max_depth - 1,
  }
  for index in 0..<count {
    let (name, contract) = notion_row_column(binding, index)
    // Charge each original name occurrence, including UTF-8 backing, before
    // retaining an output field. Field names count in the complete object.
    let name_bytes = @utf8.encode(name).length()
    if name_bytes > limits.values.max_text_bytes - row.text ||
      !read_row_spend(row, name_bytes) {
      return Err(BudgetExceeded)
    }
    row.text += name_bytes
    if index >= binding.columns.length() {
      // The same original response/decode graph remains held. Charge every
      // metadata occurrence scan before conversion, including aliased id/time.
      if !read_row_spend(row, page.raw.length()) {
        return Err(BudgetExceeded)
      }
      let value = match
        admit_notion_system_cell(original, name, contract, child_limits) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match read_row_store(row, index, value) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      continue
    }
    let column = binding.columns[index]
    if ["title", "rich_text", "people", "relation"].contains(
        column.property.kind,
      ) {
      continue
    }
    // Conservatively precharge a complete original page scan/lexeme bound for
    // every scalar. No hidden per-cell reset replenishes this row's work.
    if !read_row_spend(row, page.raw.length()) ||
      !read_row_spend(row, original.properties.length()) {
      return Err(BudgetExceeded)
    }
    let value = match
      admit_notion_property_read_cell(
        binding,
        original,
        index,
        child_limits,
        row.work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Cell(issue))
    }
    match read_row_store(row, index, value) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(row)
}

///|
/// Only actual completed property originals for this same row/column may fill
/// pending cells. A wire, equal value, same page id or another query observation
/// cannot stand in for the retained original occurrence.
pub fn complete_notion_read_row_property(
  row : NotionReadRow,
  column : Int,
  page : NotionPropertyItemPage,
) -> Result[Unit, NotionReadRowIssue] {
  if !read_row_is_original(row) ||
    !property_item_page_is_original(page) ||
    !physical_equal(page.request.row, row.row) {
    return Err(ForeignOriginal)
  }
  if column < 0 || column >= row.binding.columns.length() {
    return Err(InvalidColumn)
  }
  if row.complete is Some(_) || row.cells[column] is Some(_) {
    return Err(AlreadySupplied)
  }
  if !physical_equal(
      page.request.property.metadata,
      row.binding.columns[column].property,
    ) {
    return Err(ForeignOriginal)
  }
  if !read_row_spend(row, page.total_bytes) ||
    !read_row_spend(row, page.total_nodes) ||
    !read_row_spend(row, page.total_text) ||
    !read_row_spend(row, page.total_items) {
    return Err(BudgetExceeded)
  }
  let value = match
    admit_notion_completed_property(row.binding, page, column, {
      ..row.limits.values,
      max_depth: row.limits.values.max_depth - 1,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Property(issue))
  }
  read_row_store(row, column, value)
}

///|
pub fn notion_read_row_pending_wire(
  row : NotionReadRow,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionReadRowIssue] {
  if !read_row_is_original(row) {
    return Err(ForeignOriginal)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_array(writer)
    for index in 0..<row.cells.length() {
      if row.cells[index] is None {
        @encode.number_value(writer, index.to_double())
      }
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
pub fn finish_notion_read_row(
  row : NotionReadRow,
) -> Result[(@admitted.CheckedValue, Int, Int), NotionReadRowIssue] {
  if !read_row_is_original(row) {
    return Err(ForeignOriginal)
  }
  if row.complete is Some(value) {
    return Ok(value)
  }
  if row.cells.any(cell => cell is None) {
    return Err(Incomplete)
  }
  if !read_row_spend(row, row.nodes) || !read_row_spend(row, row.text) {
    return Err(BudgetExceeded)
  }
  guard row.binding.schema.shape is @contract.Object(fields) &&
    @admitted.prepare_contract_object_value(row.binding.schema) is Some(output) else {
    return Err(InvalidValue)
  }
  for index in 0..<@contract.field_count(fields) {
    let field = @contract.field_at(fields, index).unwrap()
    let mut selected = None
    for column in 0..<row.cells.length() {
      if !read_row_spend(row, 1) ||
        !read_row_spend(row, field.name.length()) ||
        !read_row_spend(row, notion_row_column(row.binding, column).0.length()) {
        @admitted.cancel_object_value(output) |> ignore
        return Err(BudgetExceeded)
      }
      if notion_row_column(row.binding, column).0 == field.name {
        selected = row.cells[column]
        break
      }
    }
    guard selected is Some(value) &&
      physical_equal(value.contract, field.contract) &&
      @admitted.append_contract_object_field(output, index, value.value) else {
      @admitted.cancel_object_value(output) |> ignore
      return Err(ForeignOriginal)
    }
  }
  guard @admitted.finish_object_value(output) is Some(value) &&
    @admitted.recheck_runtime_value_usage(
      value,
      row.binding.schema,
      row.limits.values,
    )
    is Some(checked) else {
    return Err(InvalidValue)
  }
  row.complete = Some(checked)
  Ok(checked)
}

///|
pub fn notion_read_row_wire(
  row : NotionReadRow,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionReadRowIssue] {
  let (value, _, _) = match finish_notion_read_row(row) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @admitted.emit_checked_wire_value(value, writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
/// Aggregate every original row, including the outer array node/depth, in the
/// existing Common Value/Encoder. Per-row bounds alone never bound a full page.
pub fn notion_read_page_rows_wire(
  binding : NotionDataSourceReadContracts,
  page : OriginalNotionQueryPage,
  rows : Array[NotionReadRow],
  limits : @admitted.Limits,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionReadRowIssue] {
  if limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_text_bytes < 0 ||
    max_work <= 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(page.source, binding.source) ||
    rows.length() != page.rows.length() {
    return Err(ForeignOriginal)
  }
  if rows.length() > max_work || rows.length() > limits.max_nodes - 1 {
    return Err(BudgetExceeded)
  }
  guard @admitted.prepare_array_value(rows.length()) is Some(output) else {
    return Err(BudgetExceeded)
  }
  let mut work = max_work - rows.length()
  let mut nodes = 1
  let mut text = 0
  for index in 0..<rows.length() {
    let row = rows[index]
    if !read_row_is_original(row) ||
      !physical_equal(row.binding, binding) ||
      !physical_equal(row.row, page.rows[index]) {
      @admitted.cancel_array_value(output) |> ignore
      return Err(ForeignOriginal)
    }
    let (value, child_nodes, child_text) = match finish_notion_read_row(row) {
      Ok(value) => value
      Err(issue) => {
        @admitted.cancel_array_value(output) |> ignore
        return Err(issue)
      }
    }
    if child_nodes > limits.max_nodes - nodes ||
      child_text > limits.max_text_bytes - text ||
      child_nodes > work {
      @admitted.cancel_array_value(output) |> ignore
      return Err(BudgetExceeded)
    }
    work -= child_nodes
    if child_text > work {
      @admitted.cancel_array_value(output) |> ignore
      return Err(BudgetExceeded)
    }
    work -= child_text
    nodes += child_nodes
    text += child_text
    if !@admitted.append_array_item(output, value.value) {
      @admitted.cancel_array_value(output) |> ignore
      return Err(InvalidValue)
    }
  }
  guard @admitted.finish_array_value(output) is Some(value) &&
    @contract.array_contract(binding.schema, nullable=false) is Some(contract) &&
    @admitted.recheck_runtime_value_usage(value, contract, limits)
    is Some((checked, _, _)) else {
    return Err(BudgetExceeded)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @admitted.emit_checked_wire_value(checked, writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
