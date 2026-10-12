///|
// Bind candidate relations with the same WITH/capture owner used by FROM.
// References retain their own names even when they share a physical producer.
fn bind_script_nearest_inputs(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  selected : Input,
  input : Input,
  context : Context,
  sources : ScriptSources,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> Array[Input] raise Abort {
  let bound = [input]
  for candidate in nearest_dependencies(query, known) {
    if same_relation_path(candidate.relation, selected.relation) &&
      candidate.name == selected.name {
      continue
    }
    bound.push(
      bind_script_input(
        construction, candidate, context, sources, steps, reserved,
      ),
    )
  }
  bound
}

///|
// Inspect admitted candidate Carriers, not names or sampled data. Pass only
// intrinsic Vectors roles to the ordinary Relation Pipe compiler; its current
// scope, predicate, projections and limits remain owned by compile_steps.
fn script_nearest_vector_inputs(
  construction : Construction,
  query : @query.Query,
  inputs : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
) -> Array[(String, @carrier.Vectors)] raise Abort {
  let vectors = []
  for input in nearest_dependencies(query, inputs) {
    let carrier = script_nearest_carrier(
      construction, query, input, context, sources, limits, steps,
    )
    if carrier is @carrier.VectorValue(value) {
      vectors.push((input.name, value))
    }
  }
  vectors
}
