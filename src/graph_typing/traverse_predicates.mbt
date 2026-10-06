///|
// A hop's candidate definitions are fixed by the checked Graph and authored
// labels/direction. Predicate values and actual Graph rows never narrow them.
fn traversal_hop_candidates(
  graph : @carrier.Graph,
  at : @decode.Cursor,
  direction : Direction,
  types : Array[String]?,
  b : Budget,
) -> (Array[Int], Array[Int]) raise Stop {
  let profile = @carrier.graph_definition(graph)
  let edges = []
  for edge in 0..<@carrier.graph_edge_count(profile) {
    spend(b, at, 1)
    let definition = @carrier.graph_edge_at(profile, edge).unwrap()
    let element = @carrier.graph_edge_element(definition)
    let mut selected = types is None
    if types is Some(types) {
      spend(b, at, types.length())
      for label in types {
        if @carrier.graph_element_definition_has_label(element, label) {
          selected = true
        }
      }
    }
    if selected {
      edges.push(edge)
    }
  }
  let nodes = []
  for node in 0..<@carrier.graph_node_count(profile) {
    spend(b, at, 1)
    let definition = @carrier.graph_node_at(profile, node).unwrap()
    let name = @carrier.graph_element_definition_name(definition).to_lower()
    let mut selected = false
    for edge in edges {
      spend(b, at, 1)
      let definition = @carrier.graph_edge_at(profile, edge).unwrap()
      let (source, target) = @carrier.graph_edge_endpoints(definition)
      if (direction != Incoming && target.to_lower() == name) ||
        (direction != Outgoing && source.to_lower() == name) {
        selected = true
      }
    }
    if selected {
      nodes.push(node)
    }
  }
  (edges, nodes)
}

///|
fn traversal_definition_properties(
  profile : @carrier.GraphDefinition,
  entity : EntityKind,
  definition : Int,
) -> @carrier.Knowledge {
  let element = if entity == Edges {
    @carrier.graph_edge_element(
      @carrier.graph_edge_at(profile, definition).unwrap(),
    )
  } else {
    @carrier.graph_node_at(profile, definition).unwrap()
  }
  @carrier.graph_element_definition_properties(element)
}

///|
fn traversal_common_scope(
  profile : @carrier.GraphDefinition,
  entity : EntityKind,
  candidates : Array[Int],
  at : @decode.Cursor,
  b : Budget,
) -> (@carrier.Knowledge, Array[Array[Int]]) raise Stop {
  let total = if entity == Edges {
    @carrier.graph_edge_count(profile)
  } else {
    @carrier.graph_node_count(profile)
  }
  spend(b, at, total)
  let positions : Array[Array[Int]] = []
  for _ in 0..<total {
    positions.push([])
  }
  let fields : Array[(@row.FieldName, @contract.Contract?)] = []
  if candidates is [first, ..] {
    let first_fields = traversal_definition_properties(profile, entity, first)
    for field_index in 0..<@carrier.field_count(first_fields) {
      spend(b, at, 1)
      let field = @carrier.field_at(first_fields, field_index).unwrap()
      let name = @row.reference_name(field.name)
      charge(b, at, name)
      let mut joined = field.contract.unwrap()
      let mut common = true
      let candidate_positions : Array[Int] = []
      for definition in candidates {
        let properties = traversal_definition_properties(
          profile, entity, definition,
        )
        let mut found = None
        for index in 0..<@carrier.field_count(properties) {
          spend(b, at, 1)
          let candidate = @carrier.field_at(properties, index).unwrap()
          if @row.reference_name(candidate.name).to_lower() == name.to_lower() {
            found = Some((index, candidate.contract.unwrap()))
          }
        }
        match found {
          None => common = false
          Some((index, contract)) => {
            candidate_positions.push(index)
            let (compatible, work) = @contract.join_nullability_usage(
              joined,
              contract,
              b.work,
            ) catch {
              _ => fail(at, BudgetExceeded)
            }
            spend(b, at, work)
            match compatible {
              Some(value) => joined = value
              None => common = false
            }
          }
        }
      }
      if common {
        fields.push((field.name, Some(joined)))
        for index in 0..<candidates.length() {
          positions[candidates[index]].push(candidate_positions[index])
        }
      }
    }
  }
  let scope = match
    @carrier.rows(
      fields,
      field_set=Closed,
      max_fields=fields.length(),
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(value) => value
    Err(_) => fail(at, BudgetExceeded)
  }
  (scope, positions)
}

///|
fn check_traversal_hop_predicates(
  graph : @carrier.Graph,
  at : @decode.Cursor,
  direction : Direction,
  types : Array[String]?,
  edge_where : @decode.Cursor?,
  node_where : @decode.Cursor?,
  parameters : @parameter.Declarations?,
  max_tokens : Int,
  b : Budget,
) -> Result[(TraversalHop, Int), MatchIssue] {
  try {
    let profile = @carrier.graph_definition(graph)
    let empty = @carrier.rows(
      [],
      field_set=Closed,
      max_fields=0,
      max_name_bytes=0,
    ).unwrap()
    let (edge_fields, edge_positions, node_fields, node_positions) = if edge_where
      is None &&
      node_where is None {
      (empty, [], empty, [])
    } else {
      let (edges, nodes) = traversal_hop_candidates(
        graph, at, direction, types, b,
      )
      let (edge_fields, edge_positions) = if edge_where is Some(_) {
        traversal_common_scope(profile, Edges, edges, at, b)
      } else {
        (empty, [])
      }
      let (node_fields, node_positions) = if node_where is Some(_) {
        traversal_common_scope(profile, Nodes, nodes, at, b)
      } else {
        (empty, [])
      }
      (edge_fields, edge_positions, node_fields, node_positions)
    }
    let mut tokens = 0
    let edge_predicate = match edge_where {
      None => None
      Some(source) => {
        let checked = match
          check_predicate_in_scope(
            {
              fields: edge_fields,
              usage: { work: 0, nodes: 0, text_bytes: 0, },
            },
            source,
            parameters,
            {
              max_work: b.work,
              max_nodes: b.nodes,
              max_depth: b.limits.max_depth,
              max_text_bytes: b.text,
              max_tokens,
            },
          ) {
          Ok(value) => value
          Err(issue) => raise MatchStop(MatchPredicate(issue))
        }
        b.work -= checked.usage.work
        b.nodes -= checked.usage.nodes
        b.text -= checked.usage.text_bytes
        tokens += checked.usage.tokens
        Some(checked)
      }
    }
    let node_predicate = match node_where {
      None => None
      Some(source) => {
        let checked = match
          check_predicate_in_scope(
            {
              fields: node_fields,
              usage: { work: 0, nodes: 0, text_bytes: 0, },
            },
            source,
            parameters,
            {
              max_work: b.work,
              max_nodes: b.nodes,
              max_depth: b.limits.max_depth,
              max_text_bytes: b.text,
              max_tokens: max_tokens - tokens,
            },
          ) {
          Ok(value) => value
          Err(issue) => raise MatchStop(MatchPredicate(issue))
        }
        b.work -= checked.usage.work
        b.nodes -= checked.usage.nodes
        b.text -= checked.usage.text_bytes
        tokens += checked.usage.tokens
        Some(checked)
      }
    }
    Ok(
      (
        {
          direction,
          types,
          edge_predicate,
          node_predicate,
          edge_fields,
          node_fields,
          edge_property_positions: edge_positions,
          node_property_positions: node_positions,
        },
        tokens,
      ),
    )
  } catch {
    Stop(issue) => Err(MatchStructure(issue))
    MatchStop(issue) => Err(issue)
    _ => abort("unexpected traversal predicate checker exception")
  }
}
