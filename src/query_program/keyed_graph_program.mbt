///|
priv struct ScriptGraph {
  name : @query.NamePart
  producer : String
  mapping : @query.GraphConstructor
  inputs : Array[Input]
}

///|
fn keyed_start_definitions(
  mapping : @query.GraphConstructor,
  node : @query.GraphNodePattern,
) -> Array[@query.GraphNodeDefinition] raise Abort {
  let selected = match node.label {
    Some(name) =>
      mapping.nodes.filter(definition => {
        definition.labels.any(label => same_name(label.name, name))
      })
    None => mapping.nodes
  }
  if selected.is_empty() {
    raise Abort(UnknownColumn)
  }
  selected
}

///|
// This is schema-name projection, not Graph admission. The common owner
// still validates global property types, label sets, keys and identities.
fn keyed_label_fields(
  labels : Array[@query.GraphLabel],
  requested_label : @query.NamePart?,
  input : Input,
) -> Array[String] raise Abort {
  // The common constructor retains the first spelling of each property in
  // this definition, including across label-specific property selections.
  // Lookup is case-insensitive; the checked output field still has that name.
  let canonical : Map[String, String] = Map([])
  let seen : Map[String, Bool] = Map([])
  let selected : Array[String] = []
  let mut matched = false
  for label in labels {
    let selected_label = match requested_label {
      Some(name) => same_name(label.name, name)
      None => true
    }
    matched = matched || selected_label
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
      let folded = ascii_upper(field)
      let name = match canonical.get(folded) {
        Some(name) => name
        None => {
          canonical[folded] = field
          field
        }
      }
      if selected_label && !seen.contains(folded) {
        seen[folded] = true
        selected.push(name)
      }
    }
  }
  if !matched {
    raise Abort(UnknownColumn)
  }
  selected
}

///|
fn keyed_node_fields(
  definition : @query.GraphNodeDefinition,
  node : @query.GraphNodePattern,
  input : Input,
) -> Array[String] raise Abort {
  keyed_label_fields(definition.labels, node.label, input)
}

///|
fn keyed_edge_fields(
  graph : ScriptGraph,
  edge : @query.GraphEdgePattern,
) -> Array[String] raise Abort {
  let fields : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for definition in graph.mapping.edges {
    let selected = match edge.label {
      Some(name) => definition.labels.any(label => same_name(label.name, name))
      None => true
    }
    if selected {
      let input = property_mapping_input(definition.producer, graph.inputs)
      // Traversal predicates use each candidate definition's full property
      // scope. The common checker establishes presence and compatible types
      // across every candidate; this union only resolves authored names.
      for field in keyed_label_fields(definition.labels, None, input) {
        let folded = ascii_upper(field)
        if !seen.contains(folded) {
          seen[folded] = true
          fields.push(field)
        }
      }
    }
  }
  fields
}

///|
// Resolve only authored names. The common checker intersects the properties
// and types of every static candidate; runtime rows cannot narrow that scope.
fn keyed_hop_node_fields(
  graph : ScriptGraph,
  edge : @query.GraphEdgePattern,
  node : @query.GraphNodePattern,
) -> Array[String] raise Abort {
  let edges = graph.mapping.edges.filter(definition => {
    match edge.label {
      Some(name) => definition.labels.any(label => same_name(label.name, name))
      None => true
    }
  })
  let candidates = graph.mapping.nodes.filter(definition => {
    edges.any(edge_definition => {
      (
        edge.direction != "out" &&
        same_name(definition.name, edge_definition.source.definition)
      ) ||
      (
        edge.direction != "in" &&
        same_name(definition.name, edge_definition.destination.definition)
      )
    })
  })
  if node.label is Some(label) {
    // There is no per-hop node-label filter. A requested label can only be
    // discharged by every static reached definition, never by a property.
    if !graph.mapping.nodes.any(definition => {
        definition.labels.any(candidate => same_name(candidate.name, label))
      }) ||
      !candidates.all(definition => {
        definition.labels.any(candidate => same_name(candidate.name, label))
      }) {
      raise Abort(UnsupportedGraph)
    }
  }
  let fields : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for definition in candidates {
    let input = property_mapping_input(definition.producer, graph.inputs)
    for field in keyed_node_fields(definition, { ..node, label: None, }, input) {
      let folded = ascii_upper(field)
      if !seen.contains(folded) {
        seen[folded] = true
        fields.push(field)
      }
    }
  }
  fields
}

///|
fn keyed_property_field(
  path : Array[@query.NamePart],
  variable : @query.NamePart?,
  fields : Array[String],
) -> String? {
  if path.length() < 1 || path.length() > 2 {
    return None
  }
  if path.length() == 2 {
    match variable {
      Some(name) if same_name(path[0], name) => ()
      _ => return None
    }
  }
  let mut found : String? = None
  for field in fields {
    if same_name(path.last().unwrap(), { value: field, quoted: false, }) {
      if found is Some(_) {
        return None
      }
      found = Some(field)
    }
  }
  found
}

///|
fn keyed_constraint(
  construction : Construction,
  constraint : @query.GraphConstraint?,
  variable : @query.NamePart?,
  fields : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  // Only property predicates become ordinary expressions. Static labels are
  // passed independently to the Graph owner, never compared with a property.
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    keyed_property_field(path, variable, fields)
  }
  let append = fn(expression : @query.Expression) -> @builder.Node raise Abort {
    match
      @expression.append_with_properties(
        expression,
        resolve,
        construction.builder,
        max_work,
        resolve_parameter=construction.parameter_resolver(),
      ) {
      Ok(value) => value
      Err(error) => raise Abort(Expression(error))
    }
  }
  match constraint {
    None => construction.object([("literal", construction.add(Bool(true)))])
    Some(Predicate(expression)) => append(expression)
    Some(Properties(properties)) => {
      let predicates : Array[@builder.Node] = []
      for (field, expression) in properties {
        let name = match keyed_property_field([field], variable, fields) {
          Some(name) => name
          None => raise Abort(UnknownColumn)
        }
        predicates.push(
          construction.object([
            (
              "eq",
              construction.array([
                construction.object([("field", construction.text(name))]),
                append(expression),
              ]),
            ),
          ]),
        )
      }
      if predicates.is_empty() {
        construction.object([("literal", construction.add(Bool(true)))])
      } else if predicates.length() == 1 {
        predicates[0]
      } else {
        construction.object([("and", construction.array(predicates))])
      }
    }
  }
}

///|
fn keyed_start_match(
  construction : Construction,
  graph : ScriptGraph,
  definition : @query.GraphNodeDefinition,
  node : @query.GraphNodePattern,
  fields : Array[String],
  identity : String,
  output : String,
  limits : Limits,
) -> @builder.Node raise Abort {
  // Label membership belongs to match_nodes. Never replace it by a
  // comparison with a property, even if a property has the same name.
  let predicate = keyed_constraint(
    construction,
    node.constraint,
    node.variable,
    fields,
    limits.max_expression_work,
  )
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
  known? : Array[Input] = [],
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
    construction,
    query,
    input_graph,
    limits,
    steps,
    reserved,
    known~,
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
  if pattern.nodes.is_empty() ||
    pattern_query.label_field is Some(_) ||
    @query.cte_count(query) > 0 ||
    @query.set_part_count(query) > 0 ||
    @query.join_part_count(query) > 0 {
    raise Abort(UnsupportedGraph)
  }
  let definitions = keyed_start_definitions(graph.mapping, pattern.nodes[0])
  let definition = definitions[0]
  let input = property_mapping_input(definition.producer, graph.inputs)
  let fields = keyed_node_fields(definition, pattern.nodes[0], input)
  let identity = pipe_physical_name(fields, "aql_keyed_identity_")
  let mut seeds = ""
  for selected in definitions {
    let selected_input = property_mapping_input(selected.producer, graph.inputs)
    let selected_fields = keyed_node_fields(
      selected,
      pattern.nodes[0],
      selected_input,
    )
    // The current common match exposes a definition-specific closed schema.
    // Combine equivalent property sets without guessing missing-property NULLs
    // or converting element identities into scalar keys.
    if selected_fields.length() != fields.length() {
      raise Abort(UnsupportedGraph)
    }
    let names : Map[String, String] = Map([])
    for field in selected_fields {
      names[ascii_upper(field)] = field
    }
    let source_fields = fields.map(field => {
      match names.get(ascii_upper(field)) {
        Some(name) => name
        None => raise Abort(UnsupportedGraph)
      }
    })
    let mut branch = pipe_physical_name(reserved, "aql_keyed_seeds_")
    reserved.push(branch)
    steps.push(
      keyed_start_match(
        construction,
        graph,
        selected,
        pattern.nodes[0],
        source_fields,
        identity,
        branch,
        limits,
      ),
    )
    if source_fields != fields {
      let aligned = pipe_physical_name(reserved, "aql_keyed_seeds_")
      reserved.push(aligned)
      let projection = [construction.text(identity)]
      for index in 0..<fields.length() {
        projection.push(
          if fields[index] == source_fields[index] {
            construction.text(fields[index])
          } else {
            construction.object([
              (fields[index], construction.text(source_fields[index])),
            ])
          },
        )
      }
      steps.push(
        construction.object([
          ("from", construction.text(branch)),
          ("select", construction.array(projection)),
          ("as", construction.text(aligned)),
        ]),
      )
      branch = aligned
    }
    if seeds.is_empty() {
      seeds = branch
    } else {
      let combined = pipe_physical_name(reserved, "aql_keyed_seeds_")
      reserved.push(combined)
      steps.push(
        construction.object([
          ("from", construction.text(seeds)),
          ("append", construction.object([("with", construction.text(branch))])),
          ("as", construction.text(combined)),
        ]),
      )
      seeds = combined
    }
  }
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
        kind: NodeIdentity(identity),
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
      pattern.edges.any(edge => edge.variable is Some(_)) ||
      (pattern.edges.any(edge => edge.quantified) && !bounded) {
      raise Abort(UnsupportedGraph)
    }
    if bounded {
      let node = pattern.nodes[1]
      if graph.mapping.nodes.length() > 1 &&
        node.label is Some(label) &&
        !graph.mapping.nodes.all(definition => {
          definition.labels.any(candidate => same_name(candidate.name, label))
        }) {
        raise Abort(UnsupportedGraph)
      }
      ignore(keyed_node_fields(definition, node, input))
      if node.constraint is Some(_) {
        // Homogeneous node_where tests every reached hop. A quantified
        // pattern's endpoint condition must not be applied to intermediates.
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
      if edge.constraint is Some(_) {
        params.push(
          (
            "edge_where",
            keyed_constraint(
              construction,
              edge.constraint,
              None,
              keyed_edge_fields(graph, edge),
              limits.max_expression_work,
            ),
          ),
        )
      }
    } else {
      let hops : Array[@builder.Node] = []
      for index, edge in pattern.edges {
        let node = pattern.nodes[index + 1]
        let node_fields = keyed_hop_node_fields(graph, edge, node)
        let hop = [("direction", construction.text(edge.direction))]
        if edge.label is Some(label) {
          hop.push(
            ("edge_types", construction.array([construction.text(label.value)])),
          )
        }
        if edge.constraint is Some(_) {
          hop.push(
            (
              "edge_where",
              keyed_constraint(
                construction,
                edge.constraint,
                None,
                keyed_edge_fields(graph, edge),
                limits.max_expression_work,
              ),
            ),
          )
        }
        if node.constraint is Some(_) {
          hop.push(
            (
              "node_where",
              keyed_constraint(
                construction,
                node.constraint,
                node.variable,
                node_fields,
                limits.max_expression_work,
              ),
            ),
          )
        }
        hops.push(construction.object(hop))
      }
      params.push(("hops", construction.array(hops)))
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
    limits.source,
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
