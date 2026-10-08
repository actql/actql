///|
// Bind candidate relations with the same DATA/capture owner used by FROM.
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
