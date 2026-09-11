///|
pub enum PivotFill {
  Null(source~ : @decode.Cursor)
  Literal(@value.CheckedValue, source~ : @decode.Cursor)
  Parameter(String, contract~ : @contract.Contract, source~ : @decode.Cursor)
}

///|
struct CheckedPivot {
  index : Array[KeyField]
  column : KeyField
  value : KeyField
  function : AggregateFunction
  values : Array[String]
  columns : Array[String]
  fill : PivotFill?
  result : @contract.Contract
}

///|
pub fn pivot(value : CheckedOperation) -> CheckedPivot? {
  value.pivot
}

///|
/// Empty generated values with index groups enumerate first occurrences.
/// Reads retained metadata without copying either authored axis.
pub fn pivot_uses_first_occurrence(value : CheckedOperation) -> Bool {
  match value.pivot {
    Some(p) => p.values.is_empty() && !p.index.is_empty()
    None => false
  }
}

///|
pub fn pivot_index(value : CheckedPivot) -> Array[KeyField] {
  value.index.copy()
}

///|
pub fn pivot_column(value : CheckedPivot) -> KeyField {
  value.column
}

///|
pub fn pivot_value(value : CheckedPivot) -> KeyField {
  value.value
}

///|
pub fn pivot_function(value : CheckedPivot) -> AggregateFunction {
  value.function
}

///|
/// Authored sequence, including its identity-relevant order.
pub fn pivot_values(value : CheckedPivot) -> Array[String] {
  value.values.copy()
}

///|
/// Generated columns in canonical string order, excluding index fields.
pub fn pivot_columns(value : CheckedPivot) -> Array[String] {
  value.columns.copy()
}

///|
pub fn pivot_fill(value : CheckedPivot) -> PivotFill? {
  value.fill
}

///|
pub fn pivot_result(value : CheckedPivot) -> @contract.Contract {
  value.result
}

///|
fn pivot_field(
  b : Budget,
  source : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
) -> KeyField raise Stop {
  let name = decoded(@decode.text(source), source)
  { field: input_reference(b, source, name, visible), source, }
}

///|
fn pivot_literal(
  b : Budget,
  source : @decode.Cursor,
  target : @contract.Contract,
) -> PivotFill raise Stop {
  if @decode.is_null(source) {
    spend(b, source)
    if !target.nullable {
      fail(source, InvalidFill)
    }
    // NULL is not reference evidence or construction of a reference value.
    return Null(source~)
  }
  // Preflight both structures and reserve a conservative second traversal for
  // value admission. Its own bounded node/text counters cannot reset a shared
  // pipeline budget or depend on the number of generated pivot columns.
  preflight(b, source, target)
  let (work, nodes, text) = (b.work, b.nodes, b.text)
  row_source(b, source)
  let (work, nodes, text) = (work - b.work, nodes - b.nodes, text - b.text)
  spend(b, source, count=work)
  if nodes > b.nodes || text > b.text {
    fail(source, BudgetExceeded)
  }
  b.nodes -= nodes
  b.text -= text
  let checked = match
    @value.admit(target, source, {
      max_nodes: nodes,
      max_depth: b.limits.max_depth,
      max_text_bytes: text,
    }) {
    Ok(c) => c
    Err(issue) => fail(source, FillValue(issue))
  }
  Literal(checked, source~)
}

///|
fn read_pivot_fill(
  b : Budget,
  source : @decode.Cursor,
  target : @contract.Contract,
  parameters : Map[String, @contract.Contract],
  pending : Array[PendingValidation],
) -> PivotFill raise Stop {
  spend(b, source)
  if @decode.view(source) is ObjectValue(obj) {
    let names = @decode.object_field_names(source).unwrap()
    if names.length() == 1 {
      if names[0] == "literal" {
        return pivot_literal(b, @decode.lookup(obj, "literal").unwrap(), target)
      }
      if names[0] == "$param" {
        let s = @decode.lookup(obj, "$param").unwrap()
        let name = decoded(@decode.text(s), s)
        charge(b, s, name)
        let c = match parameters.get(name) {
          Some(c) => c
          None => fail(s, UnknownParameter(name))
        }
        let before = b.work
        preflight(b, source, c)
        preflight(b, source, target)
        let pairs = before - b.work
        spend(b, source, count=pairs)
        let compatible = @contract.assignable(c, target, pairs) catch {
          _ => fail(source, BudgetExceeded)
        }
        if !compatible {
          fail(source, InvalidFill)
        }
        pending.push({ kind: BoundFill(name), source, })
        return Parameter(name, contract=c, source~)
      }
    }
  }
  pivot_literal(b, source, target)
}

///|
fn check_pivot(
  b : Budget,
  body : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  parameter_types : Map[String, @contract.Contract],
  pending : Array[PendingValidation],
) -> (CheckedPivot, Array[(@schema.FieldName, @contract.Contract)]) raise Stop {
  let obj = decoded(
    @decode.closed_object(body, [
      "index", "column", "values", "value", "aggregate", "fill",
    ]),
    body,
  )
  let index = row_keys(
    b,
    decoded(@decode.required(obj, "index"), body),
    visible,
    unique=false,
  )
  let column = pivot_field(
    b,
    decoded(@decode.required(obj, "column"), body),
    visible,
  )
  let column_type = visible.get(@schema.reference_name(column.field)).unwrap().0
  if !(column_type.shape is @contract.Text(_)) {
    fail(column.source, InvalidAggregateArgument("string pivot column"))
  }
  let value = pivot_field(
    b,
    decoded(@decode.required(obj, "value"), body),
    visible,
  )
  let input = visible.get(@schema.reference_name(value.field)).unwrap().0
  let function_source = decoded(@decode.required(obj, "aggregate"), body)
  let function = aggregate_function_name(function_source)
  match function {
    Sum | Avg | Count | Min | Max | First => ()
    _ => fail(function_source, InvalidAggregate("pivot function"))
  }
  let mut result = aggregate_output(b, value.source, function, Some(input))
  let names : Map[String, Bool] = Map([])
  let fields : Array[(@schema.FieldName, @contract.Contract)] = []
  for key in index {
    spend(b, key.source)
    let name = @schema.reference_name(key.field)
    if !names.contains(name) {
      names[name] = true
      fields.push((key.field, visible.get(name).unwrap().0))
    }
  }
  let source = decoded(@decode.required(obj, "values"), body)
  let items = decoded(@decode.elements(source), source)
  spend(b, source, count=items.length())
  let values : Array[String] = []
  for s in items {
    let name = decoded(@decode.text(s), s)
    field_name(b, s, name)
    if names.contains(name) {
      fail(s, DuplicateOutput(name))
    }
    names[name] = true
    values.push(name)
  }
  let columns = values.copy()
  columns.sort_by(@canonical.compare_utf16)
  let fill = match @decode.lookup(obj, "fill") {
    None => None
    Some(s) => {
      let fill = read_pivot_fill(b, s, result, parameter_types, pending)
      let nullable = match fill {
        Null(..) => true
        Literal(_, ..) => false
        Parameter(_, contract~, ..) => contract.nullable
      }
      result = @contract.with_nullability(result, result.nullable && nullable)
      Some(fill)
    }
  }
  for name in columns {
    fields.push((@schema.Unqualified(name), result))
  }
  pending.push({ kind: PivotPartitioning, source: body, })
  pending.push({ kind: AggregateDemand, source: body, })
  pending.push({ kind: AggregateEnvelope, source: body, })
  if function is First {
    pending.push({ kind: StableInputOrder, source: body, })
  }
  if (function is Sum || function is Avg) && input.shape is @contract.Number {
    pending.push({ kind: NumericAggregateObservation, source: body, })
  }
  ({ index, column, value, function, values, columns, fill, result, }, fields)
}
