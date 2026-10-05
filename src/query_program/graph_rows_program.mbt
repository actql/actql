///|
fn script_has_graph_rows(query : @query.Query) -> Bool {
  for index in 0..<@query.operation_count(query) {
    guard @query.operation_at(query, index) is Some(GraphCall(call)) else {
      break
    }
    if call.operation == "node_rows" ||
      call.operation == "edge_rows" ||
      script_graph_diagnostic_fields(call.operation) is Some(_) ||
      call.operation == "graphs_equal" ||
      call.operation == "traverse" {
      return true
    }
  }
  false
}

///|
// Resolve names from the admitted constructor syntax, never from sampled rows.
// Presence, types, key/role collisions and output evidence remain obligations
// of the existing common Graph-row checker. No legacy scalar identity schema
// or inferred uniqueness is attached to this ordinary Relation input.
fn script_graph_row_columns(
  graph : ScriptGraph,
  edges : Bool,
  selection? : (String, String)? = None,
) -> Array[String] raise Abort {
  let definitions = if edges {
    graph.mapping.edges.map(edge => {
      (edge.name.value, edge.producer, edge.key, edge.labels)
    })
  } else {
    graph.mapping.nodes.map(node => {
      (node.name.value, node.producer, node.key, node.labels)
    })
  }
  let definitions = match selection {
    None => definitions
    Some((kind, name)) => {
      let identity = @carrier.property_name_identity(name)
      let selected = definitions.filter(definition => {
        if kind == "definition" {
          @carrier.property_name_identity(definition.0) == identity
        } else {
          definition.3.any(label => {
            @carrier.property_name_identity(label.name.value) == identity
          })
        }
      })
      guard !selected.is_empty() else { raise Abort(UnsupportedGraph) }
      selected
    }
  }
  // Match the common owner's canonical definition order for display spelling.
  definitions.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
  let fields = if edges {
    ["id", "src", "dst", "labels"]
  } else {
    ["id", "labels"]
  }
  let seen : Map[String, Bool] = Map([])
  for field in fields {
    seen[@carrier.property_name_identity(field)] = true
  }
  for (_, producer, keys, labels) in definitions {
    let input = property_mapping_input(producer, graph.inputs)
    let names = keys.map(key => property_mapping_column(key, input))
    for label in labels {
      let properties = match label.properties {
        AllColumns => columns(input)
        NoProperties => []
        AllColumnsExcept(excluded) => {
          let excluded = excluded.map(name => {
            property_mapping_column(name, input)
          })
          columns(input).filter(field => !excluded.contains(field))
        }
        Columns(pairs) =>
          pairs.map(pair => {
            ignore(property_mapping_column(pair.0, input))
            pair.1.value
          })
      }
      names.append(properties)
    }
    for name in names {
      let folded = @carrier.property_name_identity(name)
      if !seen.contains(folded) {
        seen[folded] = true
        fields.push(name)
      }
    }
  }
  fields.sort_by((a, b) => @canonical.compare_utf16(a, b))
  fields
}

///|
// These are string-valued selectors, not producer references or property
// predicates. The common Bridge still decides presence and type guarantees.
fn script_graph_row_selection(
  call : @query.SgaCall,
) -> (String, String)? raise Abort {
  if call.arguments.is_empty() {
    return None
  }
  guard call.arguments.length() == 1 else { raise Abort(UnsupportedGraph) }
  let (kind, argument) = call.arguments[0]
  guard kind == "definition" || kind == "label" else {
    raise Abort(UnsupportedGraph)
  }
  guard argument is TextValue(name) else { raise Abort(UnsupportedGraph) }
  Some((kind, name))
}

///|
fn lower_script_graph_rows(
  construction : Construction,
  query : @query.Query,
  graph : ScriptGraph,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  output : String,
  known? : Array[Input] = [],
  graphs? : Array[ScriptGraph] = [],
  retained? : Array[RetainedResult]? = None,
) -> Input raise Abort {
  if @query.cte_count(query) > 0 ||
    @query.set_part_count(query) > 0 ||
    @query.join_part_count(query) > 0 ||
    @query.graph_query(query)
    .map(graph => graph.pattern is Some(_))
    .unwrap_or(false) {
    raise Abort(UnsupportedGraph)
  }
  let mut current = graph.producer
  let mut row_input : Input? = None
  for index in 0..<@query.operation_count(query) {
    guard @query.operation_at(query, index) is Some(GraphCall(call)) else {
      break
    }
    if row_input is Some(_) {
      raise Abort(UnsupportedGraph)
    }
    if script_graph_diagnostic_fields(call.operation) is Some(fields) {
      row_input = Some(
        lower_script_graph_diagnostic(
          construction, query, call, current, fields, limits, steps, reserved,
        ),
      )
      current = row_input.unwrap().name
      continue
    }
    if call.operation == "graphs_equal" {
      row_input = Some(
        lower_script_graph_equality(
          construction, query, call, current, graphs, steps, reserved,
        ),
      )
      current = row_input.unwrap().name
      continue
    }
    if call.operation == "traverse" {
      row_input = Some(
        lower_script_traversal_nodes(
          construction, query, call, current, known, limits, steps, reserved,
        ),
      )
      current = row_input.unwrap().name
      continue
    }
    let selection = if call.operation == "normalize_graph" {
      guard call.arguments.is_empty() else { raise Abort(UnsupportedGraph) }
      None
    } else {
      script_graph_row_selection(call)
    }
    let body = match selection {
      None => construction.add(Bool(true))
      Some((kind, name)) =>
        construction.object([(kind, construction.text(name))])
    }
    if call.operation != "normalize_graph" &&
      call.operation != "node_rows" &&
      call.operation != "edge_rows" {
      raise Abort(UnsupportedGraph)
    }
    let name = pipe_physical_name(reserved, "aql_sga_")
    reserved.push(name)
    steps.push(
      construction.object([
        ("from", construction.text(current)),
        (call.operation, body),
        ("as", construction.text(name)),
      ]),
    )
    current = name
    if call.operation != "normalize_graph" {
      row_input = Some({
        relation: @query.relation(query),
        name,
        source: StepReference,
        visible_fields: script_graph_row_columns(
          graph,
          call.operation == "edge_rows",
          selection~,
        ),
        graph_bindings: [],
      })
    }
  }
  guard row_input is Some(input) else { raise Abort(UnsupportedGraph) }
  let relation_query = @query.after_graph_calls(query)
  let fields = query_columns(relation_query, input)
  let (body, output_fields) = compile_steps(
    construction,
    relation_query,
    input,
    fields,
    limits.max_expression_work,
    limits.max_collection_items,
    limits.max_collection_bytes,
    0,
    false,
    output,
    retained~,
  )
  steps.append(body)
  {
    relation: [],
    name: if body.is_empty() {
      input.name
    } else {
      output
    },
    source: StepReference,
    visible_fields: output_fields,
    graph_bindings: [],
  }
}
