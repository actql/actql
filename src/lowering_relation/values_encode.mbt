///|
/// Bounded, owner-bound values emission material, not executable admission.
struct PreparedValues {
  owner : BoundPrepared
  node : PreparedNode
  values : @values.CheckedValues
}

///|
pub(all) enum ValuesIssue {
  InvalidValuesLimits
  MissingValuesNode
  ValuesLimit
  MissingValuesParameter(String)
  InvalidValuesRow
}

///|
pub fn prepare_values_node(
  owner : BoundPrepared,
  index : Int,
  max_rows~ : Int,
  max_cells~ : Int,
) -> Result[PreparedValues, ValuesIssue] {
  if max_rows < 0 || max_cells < 0 {
    return Err(InvalidValuesLimits)
  }
  guard node_at(owner.prepared, index) is Some(node) else {
    return Err(MissingValuesNode)
  }
  guard node.payload is Values(values) else { return Err(MissingValuesNode) }
  let count = @values.row_count(values)
  let schema = @values.output_schema(values)
  let width = @schema.field_count(schema)
  if count > max_rows {
    return Err(ValuesLimit)
  }
  let mut cells = 0
  for i = 0; i < count; i = i + 1 {
    if width > max_cells - cells {
      return Err(ValuesLimit)
    }
    cells += width
    let row = @values.row_at(values, i).unwrap()
    for j = 0; j < width; j = j + 1 {
      guard @values.cell_at(row, j) is Some(cell) else {
        return Err(InvalidValuesRow)
      }
      match cell {
        Literal(_, ..) => ()
        Parameter(name, ..) =>
          if parameter_value(owner, name) is None {
            return Err(MissingValuesParameter(name))
          }
      }
    }
  }
  Ok({ owner, node, values, })
}

///|
/// REL.values execution params pinned by main dab50b1. Cells are ordinary typed
/// wire values: no source quotation wrappers or recursive Parameter dispatch.
pub fn emit_values_params(
  prepared : PreparedValues,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let schema = @values.output_schema(prepared.values)
  let width = @schema.field_count(schema)
  @encode.begin_object(out)
  @encode.key(out, "rows")
  @encode.begin_array(out)
  for i = 0; i < @values.row_count(prepared.values); i = i + 1 {
    let row = @values.row_at(prepared.values, i).unwrap()
    @encode.begin_object(out)
    for j = 0; j < width; j = j + 1 {
      let field = @schema.field_at(schema, j).unwrap()
      @encode.key(out, @schema.reference_name(field.name))
      let checked = match @values.cell_at(row, j).unwrap() {
        Literal(value, ..) => value
        Parameter(name, ..) => parameter_value(prepared.owner, name).unwrap()
      }
      emit_wire_value(checked.value, out)
    }
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "schema")
  @encode.begin_object(out)
  for j = 0; j < width; j = j + 1 {
    let field = @schema.field_at(schema, j).unwrap()
    @encode.key(out, @schema.reference_name(field.name))
    @contract.emit_checked(field.contract, out)
  }
  @encode.end_object(out)
  @encode.end_object(out)
}

///|
pub fn emit_values_node(
  prepared : PreparedValues,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "REL.values")
  @encode.key(out, "params")
  emit_values_params(prepared, out)
  @encode.end_object(out)
}
