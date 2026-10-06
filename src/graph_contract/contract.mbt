///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  IncompleteGraph
  BudgetExceeded
} derive(Eq, Debug)

///|
/// The sole admitted Graph schema uses definition-scoped typed keys.
struct CheckedContract {
  graph : @carrier.Graph
  cid : String
  bytes : Int
  nodes : Int
}

///|
pub fn admit_graph(
  graph : @carrier.Graph,
  limits : Limits,
) -> Result[CheckedContract, Issue] {
  admit(@carrier.graph_carrier(graph), limits)
}

///|
pub fn cid(c : CheckedContract) -> String {
  c.cid
}

///|
pub fn bytes(c : CheckedContract) -> Int {
  c.bytes
}

///|
pub fn nodes(c : CheckedContract) -> Int {
  c.nodes
}
