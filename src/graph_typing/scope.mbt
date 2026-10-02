///|
pub(all) enum EntityKind {
  Nodes
  Edges
} derive(Eq, Debug)

///|
struct CheckedScope {
  fields : @carrier.Knowledge
  usage : Usage
}

///|
/// Definition-free homogeneous scope is unconnected under the sole Graph
/// contract. MATCH builds the exact selected definition scope before invoking
/// the shared expression checker; opaque Graphs never synthesize a scope.
pub fn check_scope(
  _entity : EntityKind,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedScope, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if @carrier.kind(input) != @carrier.GraphKind {
      fail(source, WrongCarrier(@carrier.kind(input)))
    }
    if input is @carrier.GraphValue(graph) {
      reject_unconnected_graph_operation(graph, source)
    }
    fail(source, IncompleteGraph)
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn scope_fields(c : CheckedScope) -> @carrier.Knowledge {
  c.fields
}

///|
pub fn scope_usage(c : CheckedScope) -> Usage {
  c.usage
}
