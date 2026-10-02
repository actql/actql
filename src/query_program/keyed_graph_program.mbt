///|
priv struct ScriptGraph {
  name : @query.NamePart
  producer : String
  mapping : @query.PropertyGraphConstructor
  inputs : Array[Input]
}

///|
// This is schema-name projection, not Graph admission. The common owner
// still validates global property types, label sets, keys and identities.
fn keyed_node_fields(
  definition : @query.PropertyNodeDefinition,
  node : @query.GraphNodePattern,
  input : Input,
) -> Array[String] raise Abort {
  let labels = match node.label {
    Some(name) => definition.labels.filter(label => same_name(label.name, name))
    None => definition.labels
  }
  if labels.is_empty() {
    raise Abort(UnknownColumn)
  }
  let selected : Array[String] = []
  for label in labels {
    let fields = match label.properties {
      AllColumns => columns(input)
      NoProperties => []
      AllColumnsExcept(names) => {
        let excluded = names.map(name => property_mapping_column(name, input))
        columns(input).filter(field => !excluded.contains(field))
      }
      Columns(pairs) =>
        pairs.map(pair => {
          ignore(property_mapping_column(pair.0, input))
          pair.1.value
        })
    }
    for field in fields {
      if !selected.contains(field) {
        selected.push(field)
      }
    }
  }
  selected
}

///|
fn keyed_start_match(
  construction : Construction,
  graph : ScriptGraph,
  definition : @query.PropertyNodeDefinition,
  node : @query.GraphNodePattern,
  fields : Array[String],
  identity : String,
  output : String,
  limits : Limits,
) -> @builder.Node raise Abort {
  // Label membership belongs to match_nodes. Never replace it by a
  // comparison with a property, even if a property has the same name.
  let predicate = match
    graph_node_predicate(
      construction,
      { label_field: None, pattern: None, },
      { ..node, label: None, },
      fields,
      "",
      limits.max_expression_work,
    ) {
    Some(predicate) => predicate
    None => construction.object([("literal", construction.add(Bool(true)))])
  }
  let params = [
    ("definition", construction.text(definition.name.value)),
    ("where", predicate),
    (
      "bindings",
      construction.object([("identity", construction.text(identity))]),
    ),
    (
      "fields",
      construction.array(
        ([identity] + fields).map(field => construction.text(field)),
      ),
    ),
  ]
  if node.label is Some(label) {
    params.push(("label", construction.text(label.value)))
  }
  construction.object([
    ("from", construction.text(graph.producer)),
    ("match_nodes", construction.object(params)),
    ("as", construction.text(output)),
  ])
}

///|
// Keyed Graphs enter their existing definition-scoped match and traversal
// owners. There is no tuple-identity join, deduplication, implicit sort,
// Graph-to-legacy conversion or frontend path evaluator here.
fn lower_script_keyed_graph_query(
  construction : Construction,
  query : @query.Query,
  graphs : Array[ScriptGraph],
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  output : String,
  retained : Array[RetainedResult],
) -> Input raise Abort {
  guard @query.graph_query(query) is Some(pattern_query) &&
    pattern_query.pattern is Some(pattern) else {
    raise Abort(UnsupportedGraph)
  }
  let relation = @query.relation(query)
  guard relation.length() == 1 else { raise Abort(UnknownRelation) }
  guard script_graph_input(query, graphs) is Some(input_graph) else {
    raise Abort(UnknownRelation)
  }
  let graph = lower_script_graph_calls(
    construction, query, input_graph, steps, reserved,
  )
  let query = @query.after_graph_calls(query)
  let mut projected = false
  for index in 0..<@query.operation_count(query) {
    if @query.operation_at(query, index) is Some(Select(_, _)) {
      projected = true
    }
  }
  // Implicit Graph element-value export has no adapted source contract yet.
  // Do not manufacture an empty Relation or export physical pattern slots.
  if !projected {
    raise Abort(UnsupportedProjection)
  }
  if graph.mapping.nodes.length() != 1 ||
    pattern.nodes.is_empty() ||
    pattern_query.label_field is Some(_) ||
    @query.cte_count(query) > 0 ||
    @query.set_part_count(query) > 0 ||
    @query.join_part_count(query) > 0 {
    raise Abort(UnsupportedGraph)
  }
  let definition = graph.mapping.nodes[0]
  let input = property_mapping_input(definition.producer, graph.inputs)
  let fields = keyed_node_fields(definition, pattern.nodes[0], input)
  let identity = pipe_physical_name(fields, "aql_keyed_identity_")
  let seeds = pipe_physical_name(reserved, "aql_keyed_seeds_")
  reserved.push(seeds)
  steps.push(
    keyed_start_match(
      construction,
      graph,
      definition,
      pattern.nodes[0],
      fields,
      identity,
      seeds,
      limits,
    ),
  )
  let bindings : Array[GraphBinding] = []
  let names : Array[@query.NamePart] = []
  for node in pattern.nodes {
    if node.variable is Some(name) {
      if names.any(previous => same_name(previous, name)) {
        // Full keyed identities are currently JSON contracts, which ordinary
        // relational equality joins do not admit. Do not stringify them or
        // use an endpoint tuple to bypass that common-contract boundary.
        raise Abort(UnsupportedGraph)
      }
      names.push(name)
    }
  }
  let (source, visible) = if pattern.edges.is_empty() {
    if pattern.path_name is Some(_) {
      raise Abort(UnsupportedGraph)
    }
    if pattern.nodes[0].variable is Some(variable) {
      bindings.push({
        variable,
        prefix: "",
        fields,
        kind: PropertyNode(identity),
        hops: 0,
        label_field: None,
      })
    }
    // Only declared properties are visible. The full identity slot is
    // available through NODE_ID, never through a guessed physical name.
    (seeds, fields)
  } else {
    let bounded = pattern.edges.length() == 1 && pattern.edges[0].quantified
    if pattern.nodes.length() != pattern.edges.length() + 1 ||
      pattern.edges.any(edge => {
        edge.variable is Some(_) || edge.constraint is Some(_)
      }) ||
      (pattern.edges.any(edge => edge.quantified) && !bounded) {
      raise Abort(UnsupportedGraph)
    }
    for index in 1..<pattern.nodes.length() {
      let node = pattern.nodes[index]
      ignore(keyed_node_fields(definition, node, input))
      if node.constraint is Some(_) {
        // Endpoint and intermediate predicates require a definition-scoped
        // binding, not an equality join on the JSON identity carrier.
        raise Abort(UnsupportedGraph)
      }
    }
    let mode = match pattern.mode {
      Walk => "walk"
      Trail => "trail"
      Acyclic => "acyclic"
    }
    let params = [
      (
        "start",
        construction.object([
          ("from", construction.text(seeds)),
          ("id", construction.text(identity)),
        ]),
      ),
      ("path_mode", construction.text(mode)),
      ("emit", construction.text("paths")),
    ]
    if bounded {
      let edge = pattern.edges[0]
      params.push(("direction", construction.text(edge.direction)))
      params.push(
        ("min_hops", construction.add(Number(edge.min_hops.to_double()))),
      )
      params.push(
        ("max_hops", construction.add(Number(edge.max_hops.to_double()))),
      )
      if edge.label is Some(label) {
        params.push(
          ("edge_types", construction.array([construction.text(label.value)])),
        )
      }
    } else {
      params.push(
        (
          "hops",
          construction.array(
            pattern.edges.map(edge => {
              let hop = [("direction", construction.text(edge.direction))]
              if edge.label is Some(label) {
                hop.push(
                  (
                    "edge_types",
                    construction.array([construction.text(label.value)]),
                  ),
                )
              }
              construction.object(hop)
            }),
          ),
        ),
      )
    }
    let paths = pipe_physical_name(reserved, "aql_keyed_paths_")
    reserved.push(paths)
    steps.push(
      construction.object([
        ("from", construction.text(graph.producer)),
        ("traverse", construction.object(params)),
        ("as", construction.text(paths)),
      ]),
    )
    if pattern.path_name is Some(variable) {
      if names.any(name => same_name(name, variable)) {
        raise Abort(AmbiguousColumn)
      }
      bindings.push({
        variable,
        prefix: "",
        fields: ["hop_count"],
        kind: Path,
        hops: 0,
        label_field: None,
      })
    }
    // Traversal's physical columns are not Graph pattern variables. Closed
    // macros reference them internally; an explicit SELECT creates columns.
    (paths, [])
  }
  let selected : Input = {
    relation,
    name: source,
    source: StepReference,
    visible_fields: visible,
    graph_bindings: bindings,
  }
  let (body, output_fields) = compile_steps(
    construction,
    query,
    selected,
    visible,
    limits.max_expression_work,
    limits.max_collection_items,
    limits.max_collection_bytes,
    0,
    false,
    output,
    graph_bindings_only=true,
    retained=Some(retained),
  )
  steps.append(body)
  {
    relation: [],
    name: if body.is_empty() {
      source
    } else {
      output
    },
    source: StepReference,
    visible_fields: output_fields,
    graph_bindings: [],
  }
}
