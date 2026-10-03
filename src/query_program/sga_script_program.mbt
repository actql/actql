///|
// Use the existing DATA naming rule and its separate Graph namespace. A
// Graph is never fabricated as an Input with Relation columns.
fn script_graph_input(
  query : @query.Query,
  graphs : Array[ScriptGraph],
) -> ScriptGraph? raise Abort {
  let relation = @query.relation(query)
  if relation.length() != 1 {
    return None
  }
  let matches = graphs.filter(graph => same_name(graph.name, relation[0]))
  if matches.length() > 1 {
    raise Abort(AmbiguousRelation)
  }
  matches.get(0)
}

///|
// Normalize retains the admitted definition, properties, labels and identity
// domain. Its logical step is not a copy, source read or materialization.
// Other SGA outputs require their adapted common Carrier/schema contract;
// do not borrow legacy scalar-ID schemas to approximate those outputs.
fn lower_script_graph_calls(
  construction : Construction,
  query : @query.Query,
  input : ScriptGraph,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> ScriptGraph raise Abort {
  if @query.cte_count(query) > 0 ||
    @query.set_part_count(query) > 0 ||
    @query.join_part_count(query) > 0 ||
    @query.relation_alias(query) is Some(_) {
    raise Abort(UnsupportedGraph)
  }
  let mut current = input.producer
  for index in 0..<@query.operation_count(query) {
    guard @query.operation_at(query, index) is Some(GraphCall(call)) else {
      break
    }
    // The existing normalize body is true; it has no user-supplied options.
    // Do not ignore unknown or duplicate input arguments to produce that body.
    if call.operation != "normalize_graph" || !call.arguments.is_empty() {
      raise Abort(UnsupportedGraph)
    }
    let output = pipe_physical_name(reserved, "aql_sga_")
    reserved.push(output)
    steps.push(
      construction.object([
        ("from", construction.text(current)),
        ("normalize_graph", construction.add(Bool(true))),
        ("as", construction.text(output)),
      ]),
    )
    current = output
  }
  { ..input, producer: current, }
}
