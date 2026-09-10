///|
// Unlike equality keys, unpivot columns may retain any admitted value contract.
fn unpivot_columns(
  b : Budget,
  source : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  unique~ : Bool,
) -> Array[KeyField] raise Stop {
  let items = decoded(@decode.elements(source), source)
  spend(b, source, count=items.length())
  let fields : Array[KeyField] = []
  let seen : Map[String, Bool] = Map([])
  for item in items {
    let name = decoded(@decode.text(item), item)
    let field = input_reference(b, item, name, visible)
    if unique && seen.contains(name) {
      fail(item, DuplicateOutput(name))
    }
    seen[name] = true
    fields.push({ field, source: item, })
  }
  fields
}

///|
fn check_unpivot(
  b : Budget,
  body : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
) -> (Reshape, Array[(@schema.FieldName, @contract.Contract)]) raise Stop {
  let obj = decoded(
    @decode.closed_object(body, [
      "columns", "keep", "name_column", "value_column",
    ]),
    body,
  )
  let source = decoded(@decode.required(obj, "columns"), body)
  let columns = unpivot_columns(b, source, visible, unique=false)
  if columns.is_empty() {
    fail(source, EmptyBody)
  }
  let selected = visible.get(@schema.reference_name(columns[0].field)).unwrap().0
  for i in 1..<columns.length() {
    let column = columns[i]
    let name = @schema.reference_name(column.field)
    let contract = visible.get(name).unwrap().0
    // Bound and debit the recursive equality walk; do not reset a per-column
    // comparison limit without charging the shared operation budget.
    let before = b.work
    preflight(b, column.source, contract)
    let pairs = before - b.work
    spend(b, column.source, count=pairs)
    let equal = @contract.type_equal(selected, contract, pairs) catch {
      _ => fail(column.source, BudgetExceeded)
    }
    if !equal {
      fail(column.source, IncompatibleColumn(name))
    }
  }
  let keep = match @decode.lookup(obj, "keep") {
    None => []
    Some(s) => unpivot_columns(b, s, visible, unique=true)
  }
  let fields : Array[(@schema.FieldName, @contract.Contract)] = []
  let names : Map[String, Bool] = Map([])
  for key in keep {
    let name = @schema.reference_name(key.field)
    names[name] = true
    fields.push((key.field, visible.get(name).unwrap().0))
  }
  let generated : Array[String] = []
  for key in ["name_column", "value_column"] {
    let s = decoded(@decode.required(obj, key), body)
    let name = decoded(@decode.text(s), s)
    field_name(b, s, name)
    if names.contains(name) {
      fail(s, DuplicateOutput(name))
    }
    names[name] = true
    generated.push(name)
  }
  fields.push(
    (
      @schema.Unqualified(generated[0]),
      @contract.primitive(StringType, nullable=false),
    ),
  )
  fields.push((@schema.Unqualified(generated[1]), selected))
  (
    Unpivot(
      columns~,
      keep~,
      name_column=generated[0],
      value_column=generated[1],
    ),
    fields,
  )
}
