///|
// Inspect admitted parameter contracts, never the rows, to establish a value
// table's visible STRUCT fields even when the input is empty or NULL.
fn unnest_parameter_element(
  expression : @query.Expression,
  declarations : @parameters.Declarations?,
  max_work : Int,
) -> @contract.Contract? raise Abort {
  guard declarations is Some(declarations) else { return None }
  let origin = @query.expression_origin(expression, @query.expression_root(expression))
  let mut remaining = max_work
  let spend = fn() -> Unit raise Abort {
    if remaining <= 0 {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin, }))
    }
    remaining -= 1
  }
  // Follow only declared parameter/property contracts. This is not expression
  // inference: computed receivers and unknown fields keep ordinary admission.
  let properties : Array[String] = []
  let mut root = @query.expression_root(expression)
  while true {
    spend()
    match @query.expression_node(expression, root) {
      Some({ kind: Parenthesized(child), .. }) => root = child
      Some({ kind: Property(child, name), .. }) => {
        properties.push(name.value)
        root = child
      }
      _ => break
    }
  }
  guard @query.expression_node(expression, root)
    is Some({ kind: ParameterReference(name), .. }) else {
    return None
  }
  for declaration in @parameters.declarations(declarations) {
    spend()
    if declaration.name == name {
      let mut contract = declaration.parameter_type.contract
      while properties.pop() is Some(property) {
        guard contract.shape is @contract.Object(fields) else { return None }
        let mut selected : @contract.Contract? = None
        for index in 0..<@contract.field_count(fields) {
          spend()
          let field = @contract.field_at(fields, index).unwrap()
          // Match the common property's exact declared name; do not apply
          // Relation alias rules or infer a field from a parameter value.
          if field.name == property {
            selected = Some(field.contract)
            break
          }
        }
        guard selected is Some(next) else { return None }
        contract = next
      }
      return match contract.shape {
        @contract.Array(element, ..) => Some(element)
        _ => None
      }
    }
  }
  None
}

///|
// A STRUCT value-table range denotes its original value, but is not an extra
// visible column. Current columns take precedence over a bare range name.
fn unnest_expression_columns(
  visible : Array[(String, String)],
  receivers : Array[(@query.NamePart, String)],
) -> Array[(String, String)] {
  let columns = visible.copy()
  for (name, slot) in receivers {
    if !pipe_name_exists(columns, name) {
      columns.push((name.value, slot))
    }
  }
  columns
}
