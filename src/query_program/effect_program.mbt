///|
// A terminal declaration uses the already retained Result port. It does not
// append a row operator, perform I/O or create an approval/capture owner.
fn lower_update_effect(
  construction : Construction,
  clause : @query.UpdateEffectClause,
  default_port : String,
  retained : Array[RetainedResult],
  max_work : Int,
) -> @builder.Node raise Abort {
  // One terminal UPDATE has one stable Program-local identity. An authored
  // empty name is invalid, rather than an instruction to choose the default.
  let name = clause.name.map(part => part.value).unwrap_or("aql_update_effect")
  guard name != "" else { raise Abort(UnsupportedEffect) }
  let captures = retained.filter(result => result.update is Some(_))
  if captures.length() == 1 {
    let capture = captures[0]
    let (id, assignments) = capture.update.unwrap()
    return update_effect_node(
      construction,
      clause,
      retained_result_port(default_port, capture.port),
      id,
      assignments,
    )
  }
  guard clause.result is Some(selected) else { raise Abort(UnsupportedEffect) }
  let results = retained.filter(result => {
    same_name({ value: result.name, quoted: false, }, selected)
  })
  guard results.length() == 1 else { raise Abort(UnsupportedEffect) }
  let result = results[0]
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    if path.length() == 1 {
      result.fields
      .filter(field => same_name({ value: field, quoted: false, }, path[0]))
      .get(0)
    } else {
      None
    }
  }
  guard resolve([clause.id]) is Some(id) else { raise Abort(UnknownColumn) }
  let assignments : Array[(String, @builder.Node)] = []
  for (field, expression) in clause.set {
    if assignments.any(entry => {
        same_name({ value: entry.0, quoted: false, }, field)
      }) {
      raise Abort(DuplicateOutput)
    }
    let value = append_effect_value(construction, expression, resolve, max_work)
    assignments.push((field.value, value))
  }
  update_effect_node(
    construction,
    clause,
    if result.terminal {
      default_port
    } else {
      retained_result_port(default_port, result.port)
    },
    id,
    assignments,
  )
}

///|
fn update_effect_node(
  construction : Construction,
  clause : @query.UpdateEffectClause,
  port : String,
  id : String,
  assignments : Array[(String, @builder.Node)],
) -> @builder.Node raise Abort {
  let name = clause.name.map(part => part.value).unwrap_or("aql_update_effect")
  guard name != "" else { raise Abort(UnsupportedEffect) }
  construction.object([
    (
      name,
      construction.object([
        (
          "update",
          construction.object([
            ("target", construction.text(clause.target)),
            ("mapping", construction.text(clause.mapping.value)),
            ("from", construction.object([("result", construction.text(port))])),
            ("id", construction.text(id)),
            ("set", construction.object(assignments)),
          ]),
        ),
      ]),
    ),
  ])
}

///|
fn update_direct_value(expression : @query.Expression) -> Bool {
  let mut node = @query.expression_node(
    expression,
    @query.expression_root(expression),
  ).unwrap()
  while node.kind is Parenthesized(child) {
    node = @query.expression_node(expression, child).unwrap()
  }
  match node.kind {
    Reference(path) => path.length() == 1
    Null | Boolean(_) | Number(_) | StringLiteral(_) => true
    Unary("-" | "+", child) =>
      @query.expression_node(expression, child).unwrap().kind is Number(_)
    _ => false
  }
}

///|
// SET expressions are ordinary Relation expressions evaluated before the closed
// Result barrier. The existing Effect sees only their sealed fields/literals.
fn lower_update_capture(
  construction : Construction,
  clause : @query.UpdateEffectClause,
  producer : String,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  physical : Array[String],
  max_work : Int,
  reserved_bindings? : Array[String] = [],
  expression_columns? : Array[(String, String)]? = None,
  value_ranges? : Array[@query.NamePart] = [],
) -> (RetainedResult, Array[Array[(String, @builder.Node)]]) raise Abort {
  let expression_visible = expression_columns.unwrap_or(visible)
  let resolve = path => {
    pipe_expression_slot(path, expression_visible, ranges, value_ranges~)
  }
  guard pipe_slot([clause.id], visible, ranges) is Some(id) else {
    raise Abort(UnknownColumn)
  }
  let fields = [id]
  let reserved = physical.copy()
  let derives : Array[(String, @builder.Node)] = []
  let assignments : Array[(String, @builder.Node)] = []
  for (field, expression) in clause.set {
    if assignments.any(entry => {
        same_name({ value: entry.0, quoted: false, }, field)
      }) {
      raise Abort(DuplicateOutput)
    }
    let mut root = @query.expression_node(
      expression,
      @query.expression_root(expression),
    ).unwrap()
    while root.kind is Parenthesized(child) {
      root = @query.expression_node(expression, child).unwrap()
    }
    let direct = match root.kind {
      Reference(path) => resolve(path)
      _ => None
    }
    let value = if direct is Some(slot) {
      if !fields.contains(slot) {
        fields.push(slot)
      }
      construction.object([("field", construction.text(slot))])
    } else if update_direct_value(expression) && !(root.kind is Reference(_)) {
      append_effect_value(construction, expression, resolve, max_work)
    } else {
      let slot = pipe_physical_name(reserved, "aql_update_value_")
      reserved.push(slot)
      derives.push(
        (
          slot,
          append_pipe_expression(
            construction,
            expression,
            expression_visible,
            ranges,
            max_work,
            value_ranges~,
          ),
        ),
      )
      fields.push(slot)
      construction.object([("field", construction.text(slot))])
    }
    assignments.push((field.value, value))
  }
  let body : Array[Array[(String, @builder.Node)]] = []
  let start = [("from", construction.text(producer))]
  if !derives.is_empty() {
    start.push(("derive", construction.object(derives)))
    body.push(start)
  }
  let projection = if derives.is_empty() { start } else { [] }
  projection.push(
    (
      "select",
      construction.array(fields.map(field => construction.text(field))),
    ),
  )
  let capture = pipe_physical_name(
    reserved_bindings + [producer],
    "aql_update_capture_",
  )
  reserved_bindings.push(capture)
  projection.push(("as", construction.text(capture)))
  body.push(projection)
  (
    {
      name: "",
      port: "aql_private_update",
      from: capture,
      fields,
      terminal: false,
      carrier_complete: false,
      update: Some((id, assignments)),
    },
    body,
  )
}

///|
// EffectValue is a field or literal. Computation belongs in the ordinary
// pipeline before RESULT, never in a new Effect evaluator.
fn append_effect_value(
  construction : Construction,
  expression : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  max_work : Int,
) -> @builder.Node raise Abort {
  let mut root = @query.expression_node(
    expression,
    @query.expression_root(expression),
  ).unwrap()
  while root.kind is Parenthesized(child) {
    root = @query.expression_node(expression, child).unwrap()
  }
  match root.kind {
    Reference(path) => {
      guard resolve(path) is Some(slot) else { raise Abort(UnknownColumn) }
      construction.object([("field", construction.text(slot))])
    }
    Null | Boolean(_) | Number(_) | StringLiteral(_) =>
      match
        @expression.append(expression, resolve, construction.builder, max_work) {
        Ok(value) => value
        Err(error) => raise Abort(Expression(error))
      }
    Unary("-" | "+", child) => {
      guard @query.expression_node(expression, child).unwrap().kind is Number(_) else {
        raise Abort(UnsupportedEffect)
      }
      match
        @expression.append(expression, resolve, construction.builder, max_work) {
        Ok(value) => value
        Err(error) => raise Abort(Expression(error))
      }
    }
    _ => raise Abort(UnsupportedEffect)
  }
}
