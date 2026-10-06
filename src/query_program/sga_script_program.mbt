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
  script_graph_named_input(relation[0], graphs)
}

///|
fn script_graph_named_input(
  name : @query.NamePart,
  graphs : Array[ScriptGraph],
) -> ScriptGraph? raise Abort {
  let matches = graphs.filter(graph => same_name(graph.name, name))
  if matches.length() > 1 {
    raise Abort(AmbiguousRelation)
  }
  matches.get(0)
}

///|
// Normalize, Subgraph and Delta application retain the admitted definitions,
// properties, labels and identity domain. A binding is not a copy, source read
// or materialization.
// Other SGA outputs require their adapted common Carrier/schema contract;
// do not borrow legacy scalar-ID schemas to approximate those outputs.
fn lower_script_graph_calls(
  construction : Construction,
  query : @query.Query,
  input : ScriptGraph,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  known? : Array[Input] = [],
  graphs? : Array[ScriptGraph] = [],
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
    if call.operation == "union_graphs" || call.operation == "subtract_graphs" {
      current = lower_script_graph_composition(
        construction, query, call, current, graphs, known, limits, steps, reserved,
      )
      continue
    }
    if call.operation == "subgraph" {
      current = lower_script_subgraph(
        construction, query, call, current, known, limits, steps, reserved,
      )
      continue
    }
    if call.operation == "apply_graph_delta" {
      current = lower_script_graph_delta(
        construction, query, call, current, known, limits, steps, reserved,
      )
      continue
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
