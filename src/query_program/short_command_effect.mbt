///|
// Selection precedes expression lowering. The target value, input ID and
// payload cannot choose a different Command, installation or interpretation.
fn resolve_short_command_effect_target(
  clause : @query.ShortCommandEffectClause,
  publication : CommandTargetPublication?,
  max_work : Int,
) -> ResolvedCommandTarget raise Abort {
  guard publication is Some(publication) else { raise Abort(UnsupportedEffect) }
  let selected = match
    resolve_command_target_binding(publication, clause.operation, max_work) {
    Ok(value) => value
    Err(issue) => raise Abort(CommandTargetBinding(issue))
  }
  let needs_target = match resolved_command_target_binding(selected) {
    None => true
    Some(binding) =>
      @environment.published_command_binding_mode(binding) == Identifier
  }
  if needs_target != (clause.target is Some(_)) {
    raise Abort(InvalidQuery)
  }
  selected
}

///|
// The ordinary Relation lowerer evaluates computed values once before the
// closed private Result. This creates neither a target Reference nor a key
// proof; the original Command input owner checks their distinct obligations.
fn lower_short_command_capture(
  construction : Construction,
  clause : @query.ShortCommandEffectClause,
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
  let fields : Array[String] = []
  let reserved = physical.copy()
  let derives : Array[(String, @builder.Node)] = []
  let capture_value = fn(expression : @query.Expression) -> String raise Abort {
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
    let slot = match direct {
      Some(slot) => slot
      None => {
        let slot = pipe_physical_name(reserved, "aql_command_value_")
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
        slot
      }
    }
    if !fields.contains(slot) {
      fields.push(slot)
    }
    slot
  }
  // Retain the parser's original field-path expression. A nested property
  // uses the same checked Relation projection, not a reparsed/synthetic ID.
  let id = capture_value(clause.id_expression)
  let target = match clause.target {
    Some(expression) => Some(capture_value(expression))
    None => None
  }
  let assignments : Array[(String, @builder.Node)] = []
  for (field, expression) in clause.input {
    if assignments.any(entry => {
        same_name({ value: entry.0, quoted: false, }, field)
      }) {
      raise Abort(DuplicateOutput)
    }
    let slot = capture_value(expression)
    assignments.push(
      (field.value, construction.object([("field", construction.text(slot))])),
    )
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
    "aql_command_capture_",
  )
  reserved_bindings.push(capture)
  projection.push(("as", construction.text(capture)))
  body.push(projection)
  (
    {
      name: "",
      port: "aql_private_command",
      from: capture,
      fields,
      terminal: false,
      carrier_complete: false,
      update: None,
      store: false,
      command: Some((id, target, assignments)),
    },
    body,
  )
}

///|
fn lower_short_command_effect(
  construction : Construction,
  clause : @query.ShortCommandEffectClause,
  selected : ResolvedCommandTarget,
  default_port : String,
  retained : Array[RetainedResult],
) -> (String, @builder.Node) raise Abort {
  let captures = retained.filter(result => result.command is Some(_))
  guard captures.length() == 1 else { raise Abort(UnsupportedEffect) }
  let capture = captures[0]
  let (id, target_field, assignments) = capture.command.unwrap()
  let (target_ref, command_ref) = resolved_command_target(selected)
  let target = match resolved_command_target_binding(selected) {
    None => {
      guard target_field is Some(field) else { raise Abort(InvalidQuery) }
      construction.object([("field", construction.text(field))])
    }
    Some(binding) => {
      let fields = [("target_ref", construction.text(target_ref))]
      match @environment.published_command_binding_mode(binding) {
        Installation => if target_field is Some(_) { raise Abort(InvalidQuery) }
        Identifier => {
          guard target_field is Some(field) else { raise Abort(InvalidQuery) }
          fields.push(("identifier_field", construction.text(field)))
        }
      }
      construction.object([("published_command", construction.object(fields))])
    }
  }
  let name = clause.name.map(part => part.value).unwrap_or("aql_command_effect")
  guard name != "" else { raise Abort(UnsupportedEffect) }
  (
    name,
    construction.object([
      (
        "command",
        construction.object([
          (
            "from",
            construction.object([
              (
                "result",
                construction.text(
                  retained_result_port(default_port, capture.port),
                ),
              ),
            ]),
          ),
          ("target", target),
          ("contract", construction.text(command_ref)),
          ("input_key", construction.text(id)),
          ("input", construction.object(assignments)),
        ]),
      ),
    ]),
  )
}
