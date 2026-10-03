///|
/// An admitted Relation row with a finite schema and explicit field presence.
/// None means absent; Some(Null) means a present, explicitly null value.
/// Dense Relation consumers cannot accept this type without a checked projection.
struct ConditionalRow {
  schema : @schema.ConditionalSchema
  cells : Array[@admitted.CheckedValue?]
  usage : ValueUsage
}

///|
struct ConditionalRowBuilder {
  schema : @schema.ConditionalSchema
  cells : Array[@admitted.CheckedValue?]
  budget : ValueBudget
  mut open : Bool
}

///|
pub(all) enum ConditionalRowIssue {
  InvalidLimits
  Closed
  InvalidWidth
  MissingRequired(Int)
  ForeignValue(Int)
  Limit
} derive(Eq, Debug)

///|
pub(all) enum ConditionalRowWireIssue {
  InvalidLimits
  InputLimit
  ShapeLimit
  InvalidJson
  Decode(@decode.Issue)
  Value(Int, @admitted.Issue)
  Row(ConditionalRowIssue)
}

///|
pub fn prepare_conditional_row(
  schema : @schema.ConditionalSchema,
  limits : ValueLimits,
) -> Result[ConditionalRowBuilder, ConditionalRowIssue] {
  let budget = match value_budget(limits) {
    Ok(value) => value
    Err(_) => return Err(InvalidLimits)
  }
  if !charge_node(budget, 1) {
    return Err(Limit)
  }
  Ok({ schema, cells: [], budget, open: true, })
}

///|
/// Append exactly one schema-ordered cell. Presence itself is charged even
/// when a conditional field is absent; admitted values retain their contracts.
pub fn append_conditional_cell(
  builder : ConditionalRowBuilder,
  cell : @admitted.CheckedValue?,
) -> Result[Unit, ConditionalRowIssue] {
  if !builder.open {
    return Err(Closed)
  }
  let column = builder.cells.length()
  guard @schema.presence_field_at(builder.schema, column) is Some(field) else {
    cancel_conditional_row(builder) |> ignore
    return Err(InvalidWidth)
  }
  if !charge_node(builder.budget, 2) {
    cancel_conditional_row(builder) |> ignore
    return Err(Limit)
  }
  match cell {
    None =>
      if @schema.field_presence(field) == @schema.Required {
        cancel_conditional_row(builder) |> ignore
        return Err(MissingRequired(column))
      }
    Some(checked) => {
      if !physical_equal(
          @schema.presence_field_contract(field),
          checked.contract,
        ) {
        cancel_conditional_row(builder) |> ignore
        return Err(ForeignValue(column))
      }
      if !charge_text(
          builder.budget,
          @schema.reference_name(@schema.presence_field_name(field)),
        ) ||
        !measure(checked.value, 2, builder.budget) {
        cancel_conditional_row(builder) |> ignore
        return Err(Limit)
      }
    }
  }
  builder.cells.push(cell)
  Ok(())
}

///|
pub fn cancel_conditional_row(builder : ConditionalRowBuilder) -> Bool {
  if !builder.open {
    return false
  }
  builder.open = false
  builder.cells.clear()
  true
}

///|
pub fn finish_conditional_row(
  builder : ConditionalRowBuilder,
) -> Result[ConditionalRow, ConditionalRowIssue] {
  if !builder.open {
    return Err(Closed)
  }
  if builder.cells.length() != @schema.presence_field_count(builder.schema) {
    cancel_conditional_row(builder) |> ignore
    return Err(InvalidWidth)
  }
  builder.open = false
  Ok({
    schema: builder.schema,
    cells: builder.cells,
    usage: {
      nodes: builder.budget.nodes,
      text_bytes: builder.budget.text,
      work: builder.budget.work,
    },
  })
}

///|
pub fn conditional_row_cell(
  row : ConditionalRow,
  column : Int,
) -> @admitted.CheckedValue?? {
  row.cells.get(column)
}

///|
pub fn conditional_row_usage(row : ConditionalRow) -> ValueUsage {
  row.usage
}

///|
/// Read one guaranteed column without copying the row or a conditional field.
/// The caller must use required_projection_schema for the matching dense type.
pub fn conditional_required_cell(
  row : ConditionalRow,
  required_index : Int,
) -> @admitted.CheckedValue? {
  guard @schema.required_source_index(row.schema, required_index)
    is Some(column) else {
    return None
  }
  row.cells[column]
}

///|
/// Canonical field ordering follows the checked finite schema, not authored
/// insertion order. A missing field emits no key; present null emits JSON null.
pub fn emit_conditional_row(
  row : ConditionalRow,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for column in 0..<row.cells.length() {
    if row.cells[column] is Some(value) {
      let field = @schema.presence_field_at(row.schema, column).unwrap()
      @encode.key(
        writer,
        @schema.reference_name(@schema.presence_field_name(field)),
      )
      @admitted.emit_checked_wire_value(value, writer)
    }
  }
  @encode.end_object(writer)
}

///|
/// Re-admit one bounded retained row against the same checked presence
/// declaration. This is content validation, not completion or Store authority.
pub fn decode_conditional_row_wire(
  schema : @schema.ConditionalSchema,
  text : String,
  wire : RetainedRowDecodeLimits,
  values : ValueLimits,
) -> Result[ConditionalRow, ConditionalRowWireIssue] {
  if wire.max_bytes < 0 ||
    wire.max_nodes < 0 ||
    wire.max_text_bytes < 0 ||
    wire.max_depth < 0 ||
    wire.max_depth > 64 {
    return Err(InvalidLimits)
  }
  let bytes = match @scalar.admit_utf8_length(text, wire.max_bytes) {
    Ok(value) => value
    Err(_) => return Err(InputLimit)
  }
  if !preflight_retained_row(text, wire) {
    return Err(ShapeLimit)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: bytes,
      max_nodes: wire.max_nodes,
      max_depth: wire.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidJson)
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: wire.max_nodes,
      max_depth: wire.max_depth,
      max_string_bytes: wire.max_text_bytes,
      max_total_string_bytes: wire.max_text_bytes,
    }) {
    Ok(cursor) => cursor
    Err(issue) => return Err(Decode(issue))
  }
  let width = @schema.presence_field_count(schema)
  guard @decode.object_length(cursor) is Some(count) &&
    width <= wire.max_nodes &&
    count <= width &&
    count <= wire.max_nodes else {
    return Err(ShapeLimit)
  }
  let names = Array::makei(width, column => {
    let field = @schema.presence_field_at(schema, column).unwrap()
    @schema.reference_name(@schema.presence_field_name(field))
  })
  let object = match @decode.closed_object(cursor, names) {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let builder = match prepare_conditional_row(schema, values) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  for column in 0..<width {
    let field = @schema.presence_field_at(schema, column).unwrap()
    let checked = match @decode.lookup(object, names[column]) {
      None => None
      Some(cell) => {
        let admitted = match
          @admitted.admit(@schema.presence_field_contract(field), cell, {
            max_nodes: wire.max_nodes,
            max_text_bytes: wire.max_text_bytes,
            max_depth: wire.max_depth,
          }) {
          Ok(value) => value
          Err(issue) => {
            cancel_conditional_row(builder) |> ignore
            return Err(Value(column, issue))
          }
        }
        Some(admitted)
      }
    }
    match append_conditional_cell(builder, checked) {
      Ok(_) => ()
      Err(issue) => {
        cancel_conditional_row(builder) |> ignore
        return Err(Row(issue))
      }
    }
  }
  match finish_conditional_row(builder) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Row(issue))
  }
}
