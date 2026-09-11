///|
/// Root-scoped shared demand facts. Node indices belong to the exact typed
/// expression; these are neither fragment-global IDs nor wire identities.
struct DemandIndex {
  roots : RootIndex
  paths : Array[@typing.DemandPaths]
  usage : DemandUsage
}

///|
pub(all) struct DemandLimits {
  max_roots : Int
  max_nodes : Int
  max_work : Int
  max_text_bytes : Int
  max_links : Int
}

///|
pub(all) struct DemandUsage {
  roots : Int
  nodes : Int
  work : Int
  text_bytes : Int
  links : Int
} derive(Eq, Debug)

///|
pub(all) enum DemandIssue {
  InvalidDemandLimits
  DemandLimit
  InvalidTypedTopology
}

///|
pub fn demand_roots(index : DemandIndex) -> RootIndex {
  index.roots
}

///|
pub fn demand_root_at(index : DemandIndex, i : Int) -> @typing.DemandPaths? {
  index.paths.get(i)
}

///|
pub fn demand_usage(index : DemandIndex) -> DemandUsage {
  index.usage
}

///|
/// Semantic demand and normalized source addressing belong to expression_typing.
/// Budgets accumulate across roots. Shared bounded accessors separately govern
/// detached test lists and pointer expansion. This is not a sealed fragment.
pub fn prepare_demand(
  roots : RootIndex,
  limits : DemandLimits,
) -> Result[DemandIndex, DemandIssue] {
  if limits.max_roots < 0 ||
    limits.max_nodes < 0 ||
    limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_links < 0 {
    return Err(InvalidDemandLimits)
  }
  let count = roots.entries.length()
  if count > limits.max_roots || count > limits.max_work {
    return Err(DemandLimit)
  }
  let paths = []
  let mut nodes = 0
  let mut work = count
  let mut text = 0
  let mut links = 0
  for root in roots.entries {
    let n = @typing.node_count(root.typed_expression)
    if n > limits.max_nodes - nodes {
      return Err(DemandLimit)
    }
    let path = match
      @typing.derive_demands(root.typed_expression, {
        max_work: limits.max_work - work,
        max_text_bytes: limits.max_text_bytes - text,
        max_links: limits.max_links - links,
      }) {
      Ok(path) => path
      Err(InvalidLimits) => return Err(InvalidDemandLimits)
      Err(BudgetExceeded) => return Err(DemandLimit)
      Err(InvalidNode) => return Err(InvalidTypedTopology)
    }
    let used = @typing.demand_usage(path)
    nodes += n
    work += used.work
    text += used.text_bytes
    links += used.links
    paths.push(path)
  }
  Ok({
    roots,
    paths,
    usage: { roots: count, nodes, work, text_bytes: text, links, },
  })
}
