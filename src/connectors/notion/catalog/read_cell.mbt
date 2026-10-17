///|
pub(all) enum NotionReadCellIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOriginal
  InvalidColumn
  InvalidCell(String)
  UnsupportedProperty(String)
  PropertyCompletionRequired(String)
  Decimal(@admitted.DecimalTextIssue)
  Admission(@admitted.Issue)
} derive(Eq, Debug)

///|
fn notion_read_scalar_json(
  property : OriginalNotionProperty,
  cursor : @decode.Cursor,
  max_bytes : Int,
) -> Result[String, NotionReadCellIssue] {
  let span = @decode.cursor_span(cursor)
  if span.start_byte < 0 ||
    span.end_byte < span.start_byte ||
    span.end_byte > property.raw.length() {
    return Err(ForeignOriginal)
  }
  if span.end_byte - span.start_byte > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(property.raw[span.start_byte:span.end_byte])) catch {
    _ => Err(InvalidCell(property.metadata.id))
  }
}

///|
fn notion_read_scalar_value(
  binding : NotionDataSourceReadContracts,
  column : NotionPropertyReadColumn,
  property : OriginalNotionProperty,
  max_input_units : Int,
) -> Result[@source.Value, NotionReadCellIssue] {
  let name = column.property.id
  if max_input_units <= 0 {
    return Err(BudgetExceeded)
  }
  let mut cursor = property.value
  let kind = column.property.kind
  if ["title", "rich_text", "people", "relation"].contains(kind) {
    return Err(PropertyCompletionRequired(name))
  }
  if kind == "formula" || kind == "rollup" {
    guard @decode.open_object(cursor) is Ok(computed) else {
      return Err(InvalidCell(name))
    }
    let expected = match column.contract.shape {
      Text(_) => "string"
      Boolean => "boolean"
      Decimal(..) => "number"
      Date | Timestamp => "date"
      _ => return Err(UnsupportedProperty(name))
    }
    guard text_is(computed, "type", expected) &&
      @decode.lookup(computed, expected) is Some(value) else {
      return Err(InvalidCell(name))
    }
    cursor = value
  }
  if @decode.is_null(cursor) {
    if [
        "checkbox", "created_time", "last_edited_time", "created_by", "last_edited_by",
        "unique_id",
      ].contains(kind) {
      return Err(InvalidCell(name))
    }
    return Ok(Null)
  }
  match column.contract.shape {
    Decimal(precision~, scale~) => {
      guard @decode.finite_number(cursor) is Ok(_) else {
        return Err(InvalidCell(name))
      }
      let lexeme = match
        notion_read_scalar_json(property, cursor, max_input_units) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        @admitted.normalize_decimal_text(
          lexeme, precision, scale, max_input_units,
        ) {
        Ok(value) => Ok(String(value))
        Err(issue) => Err(Decimal(issue))
      }
    }
    Boolean =>
      match @decode.boolean(cursor) {
        Ok(value) => Ok(Bool(value))
        Err(_) => Err(InvalidCell(name))
      }
    Text(_) => {
      if !["url", "email", "phone_number", "formula", "rollup"].contains(kind) {
        // Select options, unique ids and flattened rich text have their own
        // complete vendor projections; a native object never becomes text.
        return Err(UnsupportedProperty(name))
      }
      match @decode.text(cursor) {
        Ok(value) =>
          if value.length() <= max_input_units {
            Ok(String(value))
          } else {
            Err(BudgetExceeded)
          }
        Err(_) => Err(InvalidCell(name))
      }
    }
    Date | Timestamp => {
      if kind == "created_time" || kind == "last_edited_time" {
        guard @decode.text(cursor) is Ok(text) &&
          @admitted.normalize_timestamp_text(text, max_input_units)
          is Some(text) else {
          return Err(InvalidCell(name))
        }
        return Ok(String(text))
      }
      guard @decode.open_object(cursor) is Ok(date) &&
        @decode.field(date, "time_zone") is ExplicitNull else {
        // Named-zone material needs its actual admitted TZDB owner. It is
        // never interpreted through process-local timezone/offset defaults.
        return Err(InvalidCell(name))
      }
      if binding.columns.length() > max_input_units {
        return Err(BudgetExceeded)
      }
      let field = if column.projection == Start { "start" } else { "end" }
      if column.projection == Start &&
        !binding.columns.any(c => {
          physical_equal(c.property, column.property) && c.projection == End
        }) &&
        !(@decode.field(date, "end") is ExplicitNull) {
        // A scalar start-only binding cannot discard a supplied range end.
        return Err(InvalidCell(name))
      }
      guard @decode.lookup(date, field) is Some(value) else {
        return Err(InvalidCell(name))
      }
      if @decode.is_null(value) {
        return Ok(Null)
      }
      guard @decode.text(value) is Ok(text) else {
        return Err(InvalidCell(name))
      }
      match column.contract.shape {
        Date => Ok(String(text))
        Timestamp =>
          match @admitted.normalize_timestamp_text(text, max_input_units) {
            Some(text) => Ok(String(text))
            None => Err(InvalidCell(name))
          }
        _ => Err(InvalidCell(name))
      }
    }
    _ => Err(UnsupportedProperty(name))
  }
}

///|
/// Admit a non-paginated scalar from the same original query row/property and
/// declared Contract. Returned usage is charged by the enclosing row/page owner;
/// it does not issue a Source, current installation, Reference or capacity.
pub fn admit_notion_property_read_cell(
  binding : NotionDataSourceReadContracts,
  row : OriginalNotionQueryRow,
  column_index : Int,
  limits : @admitted.Limits,
  max_work : Int,
) -> Result[(@admitted.CheckedValue, Int, Int), NotionReadCellIssue] {
  if limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_text_bytes < 0 ||
    max_work <= 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(row.source, binding.source) {
    return Err(ForeignOriginal)
  }
  guard notion_data_source_read_column_at(binding, column_index) is Some(column) else {
    return Err(InvalidColumn)
  }
  let mut selected = None
  let mut remaining = max_work
  for property in row.properties {
    if remaining == 0 {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    if physical_equal(property.metadata, column.property) {
      selected = Some(property)
      break
    }
  }
  guard selected is Some(property) else { return Err(ForeignOriginal) }
  let value = match
    notion_read_scalar_value(binding, column, property, remaining) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let cursor = match
    @decode.admit({ value, span: @decode.cursor_span(property.value), }, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_text_bytes,
      max_total_string_bytes: limits.max_text_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  match @admitted.admit_usage(column.contract, cursor, limits) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Admission(issue))
  }
}
