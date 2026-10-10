///|
// A set operand's last pure column projection and its immediate alignment
// are one projection. Preserve the evaluated sources, output spelling/order
// and producer name; never move it across another operation or retained tap.
fn fold_script_set_terminal_select(
  construction : Construction,
  steps : Array[@builder.Node],
  first_step : Int,
  producer : String,
  fields : Array[String],
  matched : Array[String],
) -> Bool raise Abort {
  if steps.length() <= first_step || fields.length() != matched.length() {
    return false
  }
  let source = member_construct(
    @builder.snapshot(construction.builder, steps[steps.length() - 1]),
  )
  let cursor = @builder.cursor(source)
  if @wire.object_length(cursor) != Some(3) {
    return false
  }
  guard @wire.open_object(cursor) is Ok(object) else { return false }
  guard @wire.lookup(object, "as") is Some(name) else { return false }
  guard @wire.text(name) is Ok(name) && name == producer else { return false }
  guard @wire.lookup(object, "from") is Some(from) else { return false }
  guard @wire.text(from) is Ok(from) else { return false }
  guard @wire.lookup(object, "select") is Some(select) else { return false }
  guard @wire.array_length(select) is Some(count) else { return false }
  let columns : Map[String, String] = Map([])
  for index in 0..<count {
    let entry = @wire.element_at(select, index).unwrap()
    let (output, input) = match @wire.text(entry) {
      Ok(name) => (name, name)
      Err(_) => {
        if @wire.object_length(entry) != Some(1) {
          return false
        }
        guard @wire.field_at(entry, 0) is Some((output, input)) else {
          return false
        }
        guard @wire.text(input) is Ok(input) else { return false }
        (output, input)
      }
    }
    if columns.contains(output) {
      return false
    }
    columns[output] = input
  }
  let projected : Array[@builder.Node] = []
  for index in 0..<fields.length() {
    guard columns.get(matched[index]) is Some(input) else { return false }
    projected.push(
      if fields[index] == input {
        construction.text(input)
      } else {
        construction.object([(fields[index], construction.text(input))])
      },
    )
  }
  steps[steps.length() - 1] = construction.object([
    ("from", construction.text(from)),
    ("select", construction.array(projected)),
    ("as", construction.text(producer)),
  ])
  true
}

///|
fn set_operand_retains_result(query : @query.Query) -> Bool {
  for index in 0..<@query.operation_count(query) {
    if @query.operation_at(query, index) is Some(RetainResult(_)) {
      return true
    }
  }
  for index in 0..<@query.set_part_count(query) {
    if set_operand_retains_result(
        @query.set_part_at(query, index).unwrap().right,
      ) {
      return true
    }
  }
  for index in 0..<@query.cte_count(query) {
    if set_operand_retains_result(@query.cte_at(query, index).unwrap().query) {
      return true
    }
  }
  false
}

///|
// The set owner has already aligned its columns and removed hidden ORDER
// inputs. Bind that locally generated final producer without another SELECT.
// This only changes its structural name, never the operation or its arguments.
fn rebind_script_set_terminal_output(
  construction : Construction,
  steps : Array[@builder.Node],
  first_step : Int,
  producer : String,
  output : String,
) -> Bool raise Abort {
  if steps.length() <= first_step {
    return false
  }
  let source = member_construct(
    @builder.snapshot(construction.builder, steps[steps.length() - 1]),
  )
  let cursor = @builder.cursor(source)
  guard @wire.object_length(cursor) is Some(3) else { return false }
  guard @wire.open_object(cursor) is Ok(object) else { return false }
  guard @wire.lookup(object, "as") is Some(name) else { return false }
  guard @wire.text(name) is Ok(name) && name == producer else { return false }
  guard @wire.lookup(object, "from") is Some(from) else { return false }
  guard @wire.text(from) is Ok(_) else { return false }
  let allowed = [
    "append", "intersect", "except", "distinct", "sort", "take", "select",
  ]
  if !allowed.any(operation => @wire.lookup(object, operation) is Some(_)) {
    return false
  }
  steps[steps.length() - 1] = import_script_seed(construction, cursor, output)
  true
}
