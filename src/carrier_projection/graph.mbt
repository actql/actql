///|
pub(all) enum GraphObligation {
  ValidateGraphRecords
  RejectRuntimeColumnCollisions
  RestoreSemanticIdentityNames
  ResolveGraphProjectionResources
} derive(Eq, Debug)

///|
pub fn graph_pending(v : CheckedProjection) -> Array[GraphObligation] {
  let out = []
  graph_pending_each(v, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn graph_pending_each(
  v : CheckedProjection,
  emit : (GraphObligation) -> Unit,
) -> Unit {
  if v.operation == NodeRows || v.operation == EdgeRows {
    emit(ValidateGraphRecords)
    emit(RejectRuntimeColumnCollisions)
    emit(RestoreSemanticIdentityNames)
    emit(ResolveGraphProjectionResources)
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn graph_pending_count(v : CheckedProjection) -> Int {
  let mut count = 0
  graph_pending_each(v, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn graph_pending_at(v : CheckedProjection, index : Int) -> GraphObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  graph_pending_each(v, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
fn graph_projection(
  _operation : Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  _limits : Limits,
) -> Result[CheckedProjection, Issue] {
  // There is one admitted Graph representation. The definition-selected
  // MATCH owner implements projection; these homogeneous projections are
  // unconnected operations, not a second profile or an opaque-Graph fallback.
  match input {
    @carrier.GraphValue(_) => Err(issue(source, UnsupportedGraphOperation))
    _ => Err(issue(source, IncompleteGraph))
  }
}
