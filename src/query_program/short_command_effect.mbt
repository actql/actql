///|
// Construction metadata for one closed Command input. The authored ID is
// correspondence, not mutation identity, a KeySet or permission to execute.
priv struct ShortCommandCapture {
  input_key : String
  target : String?
  input : Array[(String, String)]
}

///|
fn resolve_short_command_effect_target(
  clause : @query.ShortCommandEffectClause,
  publication : CommandTargetPublication?,
  max_work : Int,
) -> ResolvedCommandTarget raise Abort {
  guard publication is Some(publication) else { raise Abort(UnsupportedEffect) }
  let selected = match
    resolve_command_target_binding(publication, clause.operation, max_work) {
    Ok(selected) => selected
    Err(issue) => raise Abort(CommandTargetBinding(issue))
  }
  let target_required = match resolved_command_target_binding(selected) {
    Some(binding) =>
      @environment.published_command_binding_mode(binding) is Identifier
    None => true
  }
  if target_required != (clause.target is Some(_)) {
    raise Abort(InvalidQuery)
  }
  selected
}

///|
// Evaluate TARGET/INPUT through the ordinary Relation expression owner once,
// while the original immutable range scope is still present. Only demanded
// fields cross the private Result; no Ref or target identity is manufactured.
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
  guard pipe_slot(clause.id, visible, ranges) is Some(input_key) else {
    raise Abort(UnknownColumn)
  }
  let expression_visible = expression_columns.unwrap_or(visible)
  let resolve = path => {
    pipe_expression_slot(path, expression_visible, ranges, value_ranges~)
  }
  let fields = [input_key]
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
    let slot = match root.kind {
      Reference(path) => resolve(path)
      _ => None
    }
    let slot = match slot {
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
  let target = clause.target.map(expression => capture_value(expression))
  let input : Array[(String, String)] = []
  for (field, expression) in clause.input {
    if input.any(entry => same_name({ value: entry.0, quoted: false, }, field)) {
      raise Abort(DuplicateOutput)
    }
    input.push((field.value, capture_value(expression)))
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
      port: capture,
      from: capture,
      fields,
      terminal: false,
      carrier_complete: false,
      update: None,
      store: false,
      short_command: Some({ input_key, target, input, }),
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
  let captures = retained.filter(result => result.short_command is Some(_))
  guard captures.length() == 1 else { raise Abort(UnsupportedEffect) }
  let result = captures[0]
  let capture = result.short_command.unwrap()
  let (target_ref, contract) = resolved_command_target(selected)
  let target = match resolved_command_target_binding(selected) {
    Some(binding) => {
      let fields = [("target_ref", construction.text(target_ref))]
      match @environment.published_command_binding_mode(binding) {
        Installation =>
          if capture.target is Some(_) {
            raise Abort(InvalidQuery)
          }
        Identifier => {
          guard capture.target is Some(field) else { raise Abort(InvalidQuery) }
          fields.push(("identifier_field", construction.text(field)))
        }
      }
      construction.object([("published_command", construction.object(fields))])
    }
    None => {
      guard capture.target is Some(field) else { raise Abort(InvalidQuery) }
      construction.object([("field", construction.text(field))])
    }
  }
  let name = clause.name.map(part => part.value).unwrap_or("aql_command_effect")
  guard !name.is_empty() else { raise Abort(UnsupportedEffect) }
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
                  retained_result_port(default_port, result.port),
                ),
              ),
            ]),
          ),
          ("target", target),
          ("contract", construction.text(contract)),
          ("input_key", construction.text(capture.input_key)),
          (
            "input",
            construction.object(
              capture.input.map(entry => {
                (
                  entry.0,
                  construction.object([("field", construction.text(entry.1))]),
                )
              }),
            ),
          ),
        ]),
      ),
    ]),
  )
}
