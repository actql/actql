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
      Ok(n) => n
      Err(e) => raise MatchStop(e)
    }
    b.work -= nodes.usage.work
    b.nodes -= nodes.usage.nodes
    b.text -= nodes.usage.text_bytes
    let mut tokens = nodes.usage.tokens
    let edges = match @decode.lookup(root, "edges") {
      None => None
      Some(at) => {
        let edges = match
          check_predicate(Edges, at, graph, parameters, {
            ..limits,
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
            max_tokens: limits.max_tokens - tokens,
          }) {
          Ok(e) => e
          Err(e) => raise MatchStop(MatchPredicate(e))
        }
        b.work -= edges.usage.work
        b.nodes -= edges.usage.nodes
        b.text -= edges.usage.text_bytes
        tokens += edges.usage.tokens
        Some(edges)
      }
    }
    Ok({
      source,
      output: graph,
      nodes,
      edges,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens,
      },
    })
  } catch {
    Stop(e) => Err(MatchStructure(e))
    MatchStop(e) => Err(e)
    _ => abort("unexpected subgraph checker exception")
  }
}

///|
pub fn subgraph_output(c : CheckedSubgraph) -> @carrier.Carrier {
  c.output
}

///|
pub fn subgraph_source(c : CheckedSubgraph) -> @decode.Cursor {
  c.source
}

///|
pub fn subgraph_nodes(c : CheckedSubgraph) -> CheckedSelector {
  c.nodes
}

///|
pub fn subgraph_edges(c : CheckedSubgraph) -> CheckedPredicate? {
  c.edges
}

///|
pub fn subgraph_usage(c : CheckedSubgraph) -> PredicateUsage {
  c.usage
}

///|
pub fn subgraph_pending(c : CheckedSubgraph) -> Array[SubgraphObligation] {
  let out = []
  subgraph_pending_each(c, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn subgraph_pending_each(
  c : CheckedSubgraph,
  emit : (SubgraphObligation) -> Unit,
) -> Unit {
  emit(AdmitSubgraphInput)
  emit(InduceSelectedEndpoints)
  emit(PreserveSubgraphIdentitiesAndProperties)
  emit(PreserveSubgraphPolicyAndScope)
  emit(ResolveSubgraphResources)
  emit(ResolveSubgraphProfile)
  if c.edges is Some(_) {
    emit(FilterInducedEdges)
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn subgraph_pending_count(c : CheckedSubgraph) -> Int {
  let mut count = 0
  subgraph_pending_each(c, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn subgraph_pending_at(
  c : CheckedSubgraph,
  index : Int,
) -> SubgraphObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  subgraph_pending_each(c, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}
