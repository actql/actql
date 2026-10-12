///|
// NONE -> Relation generators use the existing common check-only prefix and
// binding owner. Schema, keys, ranges, arithmetic and bounds are not inferred
// here from literals, defaults or sampled data.
fn lower_script_relation_primary(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> (@query.Query, Array[Input]) raise Abort {
  guard @query.producer_primary(query) is Some(RelationGenerator(call)) else {
    return (query, known)
  }
  guard ["time_series", "calendar_series"].contains(call.operation) else { raise Abort(InvalidQuery) }
  let required = if call.operation == "calendar_series" { ["start", "end", "unit", "timezone"] } else { ["start", "end", "step"] }
  let allowed = if call.operation == "calendar_series" { required + ["week_start"] } else { required }
  if call.arguments.any(argument => !allowed.contains(argument.0)) ||
    required.any(name => !call.arguments.any(argument => argument.0 == name)) {
    raise Abort(InvalidQuery)
  }
  let construction = {
    ..construction,
    generated: @origin.range(@query.query_document(query), call.start, call.end).unwrap(),
  }
  let output = pipe_physical_name(reserved, "aql_with_relation_")
  reserved.push(output)
  let fields = call.arguments.map(argument => {
    (
      argument.0,
      script_traversal_argument(construction, argument.1, known, limits),
    )
  })
  steps.push(
    construction.object([
      (call.operation, construction.object(fields)),
      ("as", construction.text(output)),
    ]),
  )
  let carrier = script_prefix_carrier(
    construction, query, context, sources, limits, steps, output,
  )
  guard carrier is @carrier.Relation(_) else { raise Abort(InvalidQuery) }
  sources.carriers[output] = carrier
  let input : Input = {
    relation: [],
    name: output,
    source: StepReference,
    visible_fields: script_carrier_columns(carrier),
    graph_bindings: [],
  }
  let tail = @query.after_relation_generator(query, {
    value: output,
    quoted: true,
  }).unwrap()
  (tail, known + [input])
}
