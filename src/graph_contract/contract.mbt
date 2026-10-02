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
pub fn law_cid() -> String {
  property_law_cid()
}

///|
pub fn admit(
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedContract, Issue] {
  admit_property_graph(input, limits)
}

///|
pub fn admit_graph(
  graph : @carrier.Graph,
  limits : Limits,
) -> Result[CheckedContract, Issue] {
  admit_property_graph(@carrier.graph_carrier(graph), limits)
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

///|
pub fn graph(c : CheckedContract) -> @carrier.Graph {
  c.graph
}

///|
pub fn stringify(
  c : CheckedContract,
  limits : Limits,
) -> String raise @encode.EncodeFailure {
  stringify_property_graph(c, limits)
}
