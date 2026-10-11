///|
fn current_script_graph(
  current : ScriptGraph?,
  query : @query.Query,
  graphs : Array[ScriptGraph],
) -> ScriptGraph? raise Abort {
  match current {
    Some(_) => current
    None => script_graph_input(query, graphs)
  }
}

///|
// A primary enters the existing constructor/generator owner once. Its syntax
// is not an admitted Carrier and never becomes a fabricated Relation input.
fn lower_script_primary(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  graphs : Array[ScriptGraph],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> ScriptGraph? raise Abort {
  guard @query.producer_primary(query) is Some(primary) else { return None }
  let output = pipe_physical_name(reserved, "aql_with_graph_")
  reserved.push(output)
  match primary {
    GraphValue(mapping) => {
      let producer_names : Map[String, String] = Map([])
      for
        path in mapping.nodes.map(node => node.producer) +
        mapping.edges.map(edge => edge.producer) {
        let input = property_mapping_input(path, known)
        if !producer_names.contains(input.name) {
          let bound = bind_script_input(
            construction, input, context, sources, steps, reserved,
          )
          producer_names[input.name] = bound.name
        }
      }
      steps.push(
        lower_graph_step(construction, mapping, known, output, producer_names~),
      )
      Some({
        name: { value: output, quoted: true, },
        producer: output,
        mapping,
        inputs: known.copy(),
      })
    }
    GraphGenerator(call) =>
      Some(
        lower_script_mean_generator(
          construction,
          @query.query_document(query),
          call,
          graphs,
          known,
          limits,
          steps,
          output,
        ),
      )
  }
}

///|
// Resolve a body before installing its name. Both output kinds share this
// binding owner, so a nearer binding shadows an outer one regardless of kind.
// A Graph continuation receives its actual producer explicitly; a generated
// physical name is never installed as an authored peer visible to SGA calls.
fn lower_script_bindings(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  graphs : Array[ScriptGraph],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> (Array[Input], Array[ScriptGraph]) raise Abort {
  let mut scoped = known.copy()
  let mut scoped_graphs = graphs.copy()
  for index in 0..<@query.query_binding_count(query) {
    let binding = @query.query_binding_at(query, index).unwrap()
    let (body_inputs, body_graphs) = lower_script_bindings(
      construction,
      binding.query,
      scoped,
      scoped_graphs,
      context,
      sources,
      limits,
      steps,
      reserved,
    )
    let body = @query.after_query_bindings(binding.query)
    let primary = lower_script_primary(
      construction, body, body_inputs, body_graphs, context, sources, limits, steps,
      reserved,
    )
    let body = @query.after_producer_primary(body)
    let graph = current_script_graph(primary, body, body_graphs)
    let body = if graph is Some(_) {
      @query.graph_source_query(body)
    } else {
      body
    }
    let matched = @query.graph_query(body)
      .map(value => value.pattern is Some(_))
      .unwrap_or(false)
    if graph is Some(graph) &&
      !matched &&
      !script_has_graph_rows(body) &&
      @query.set_part_count(body) == 0 {
      let bound = lower_script_graph_calls(
        construction,
        body,
        graph,
        limits,
        steps,
        reserved,
        known=body_inputs,
        graphs=body_graphs,
      )
      if @query.operation_count(@query.after_graph_calls(body)) != 0 ||
        has_retained_result(body) {
        raise Abort(UnsupportedGraph)
      }
      scoped_graphs = scoped_graphs.filter(graph => {
        !same_name(graph.name, binding.name)
      })
      scoped_graphs.push({ ..bound, name: binding.name, })
      scoped = scoped.filter(input => {
        !input_relation_matches([binding.name], input)
      })
      continue
    }
    let output = pipe_physical_name(reserved, "aql_script_cte_")
    reserved.push(output)
    let bound = if graph is Some(graph) && @query.set_part_count(body) == 0 {
      if matched {
        if has_retained_result(body) {
          raise Abort(UnsupportedResult)
        }
        lower_script_keyed_graph_query(
          construction,
          body,
          body_graphs,
          limits,
          steps,
          reserved,
          output,
          [],
          known=body_inputs,
          current=Some(graph),
        )
      } else {
        lower_script_graph_rows(
          construction,
          body,
          graph,
          limits,
          steps,
          reserved,
          output,
          known=body_inputs,
          graphs=body_graphs,
        )
      }
    } else {
      lower_script_relation(
        construction,
        body,
        body_inputs,
        context,
        sources,
        limits,
        steps,
        reserved,
        output,
        carry_ranges=binding.carry_ranges,
        retain_value_table=true,
        graphs=body_graphs,
      )
    }
    if !binding.carry_ranges &&
      sources.value_tables.get(bound.name) is Some(scope) {
      sources.value_tables[bound.name] = bind_value_table_scope(
        scope,
        binding.name,
      )
    }
    scoped = scoped.filter(input => {
      !input_relation_matches([binding.name], input)
    })
    scoped.push({ ..bound, relation: [binding.name], })
    scoped_graphs = scoped_graphs.filter(graph => {
      !same_name(graph.name, binding.name)
    })
  }
  (scoped, scoped_graphs)
}
