///|
pub(all) enum SubgraphObligation {
  AdmitSubgraphInput
  InduceSelectedEndpoints
  FilterInducedEdges
  PreserveSubgraphIdentitiesAndProperties
  PreserveSubgraphPolicyAndScope
  ResolveSubgraphResources
  ResolveSubgraphProfile
} derive(Eq, Debug)

///|
struct CheckedSubgraph {
  source : @decode.Cursor
  output : @carrier.Carrier
  nodes : CheckedSelector
  edges : CheckedPredicate?
  edge_fields : @carrier.Knowledge
  edge_property_positions : Array[Array[Int]]
  usage : PredicateUsage
}

///|
pub fn check_subgraph(
  source : @decode.Cursor,
  graph : @carrier.Carrier,
  relation : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedSubgraph, MatchIssue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_tokens < 0 {
      fail(source, InvalidLimits)
    }
    guard graph is @carrier.GraphValue(value) else {
      if @carrier.kind(graph) != @carrier.GraphKind {
        fail(source, WrongCarrier(@carrier.kind(graph)))
      }
      fail(source, IncompleteGraph)
    }
    let b : Budget = {
      limits: {
        max_work: limits.max_work,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_text_bytes,
      },
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let root = decoded(@decode.closed_object(source, ["nodes", "edges"]))
    let at = decoded(@decode.required(root, "nodes"))
    let nodes = match
      check_selector(at, graph, relation, parameters, {
        ..limits,
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
      }) {
      Ok(checked) => checked
      Err(issue) => raise MatchStop(issue)
    }
    b.work -= nodes.usage.work
    b.nodes -= nodes.usage.nodes
    b.text -= nodes.usage.text_bytes
    let mut tokens = nodes.usage.tokens
    let empty = @carrier.rows(
      [],
      field_set=Closed,
      max_fields=0,
      max_name_bytes=0,
    ).unwrap()
    let mut edge_fields = empty
    let mut edge_positions : Array[Array[Int]] = []
    let edges = match @decode.lookup(root, "edges") {
      None => None
      Some(at) => {
        let profile = @carrier.graph_property_definition(value)
        let candidates = []
        for index in 0..<@carrier.property_graph_edge_count(profile) {
          spend(b, at, 1)
          candidates.push(index)
        }
        let (fields, positions) = traversal_common_scope(
          profile,
          Edges,
          candidates,
          at,
          b,
        )
        edge_fields = fields
        edge_positions = positions
        let checked = match
          check_predicate_in_scope(
            { fields, usage: { work: 0, nodes: 0, text_bytes: 0, }, },
            at,
            parameters,
            {
              max_work: b.work,
              max_nodes: b.nodes,
              max_depth: limits.max_depth,
              max_text_bytes: b.text,
              max_tokens: limits.max_tokens - tokens,
            },
          ) {
          Ok(checked) => checked
          Err(issue) => raise MatchStop(MatchPredicate(issue))
        }
        b.work -= checked.usage.work
        b.nodes -= checked.usage.nodes
        b.text -= checked.usage.text_bytes
        tokens += checked.usage.tokens
        Some(checked)
      }
    }
    Ok({
      source,
      output: graph,
      nodes,
      edges,
      edge_fields,
      edge_property_positions: edge_positions,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens,
      },
    })
  } catch {
    Stop(issue) => Err(MatchStructure(issue))
    MatchStop(issue) => Err(issue)
    _ => abort("unexpected subgraph checker exception")
  }
}

///|
pub fn subgraph_output(checked : CheckedSubgraph) -> @carrier.Carrier {
  checked.output
}

///|
pub fn subgraph_source(checked : CheckedSubgraph) -> @decode.Cursor {
  checked.source
}

///|
pub fn subgraph_nodes(checked : CheckedSubgraph) -> CheckedSelector {
  checked.nodes
}

///|
pub fn subgraph_edges(checked : CheckedSubgraph) -> CheckedPredicate? {
  checked.edges
}

///|
pub fn subgraph_edge_fields(checked : CheckedSubgraph) -> @carrier.Knowledge {
  checked.edge_fields
}

///|
pub fn subgraph_edge_property_position(
  checked : CheckedSubgraph,
  definition : Int,
  field : Int,
) -> Int? {
  checked.edge_property_positions
  .get(definition)
  .bind(fields => fields.get(field))
}

///|
pub fn subgraph_usage(checked : CheckedSubgraph) -> PredicateUsage {
  checked.usage
}

///|
pub fn subgraph_pending(checked : CheckedSubgraph) -> Array[SubgraphObligation] {
  let out = []
  out.push(AdmitSubgraphInput)
  out.push(InduceSelectedEndpoints)
  if checked.edges is Some(_) {
    out.push(FilterInducedEdges)
  }
  out.push(PreserveSubgraphIdentitiesAndProperties)
  out.push(PreserveSubgraphPolicyAndScope)
  out.push(ResolveSubgraphResources)
  out.push(ResolveSubgraphProfile)
  out
}

///|
pub fn subgraph_pending_count(checked : CheckedSubgraph) -> Int {
  if checked.edges is Some(_) {
    7
  } else {
    6
  }
}

///|
pub fn subgraph_pending_at(
  checked : CheckedSubgraph,
  index : Int,
) -> SubgraphObligation? {
  match index {
    0 => Some(AdmitSubgraphInput)
    1 => Some(InduceSelectedEndpoints)
    2 if checked.edges is Some(_) => Some(FilterInducedEdges)
    _ => {
      let offset = if checked.edges is Some(_) { 3 } else { 2 }
      match index - offset {
        0 => Some(PreserveSubgraphIdentitiesAndProperties)
        1 => Some(PreserveSubgraphPolicyAndScope)
        2 => Some(ResolveSubgraphResources)
        3 => Some(ResolveSubgraphProfile)
        _ => None
      }
    }
  }
}
