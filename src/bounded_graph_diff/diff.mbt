///|
pub(all) struct Limits {
  max_workspace_slots : Int
  max_output_nodes : Int
  max_output_text_bytes : Int
  max_output_depth : Int
  max_identity_bytes : Int
  max_identity_nodes : Int
  max_identity_depth : Int
  value_limits : @value.Limits
}

///|
pub(all) enum Issue {
  InvalidLimits
  InvalidGraph
  InvalidDeltaContract
  UnsupportedGraphOperation
  WorkspaceLimit
  OutputLimit
  Snapshot(@snapshot.Issue)
  Comparison(@value.CompleteEqualityIssue)
  Terminal
} derive(Eq, Debug)

///|
// These boundary types remain for callers that handle the typed refusal. No
// delta or preparation is issued; retaining them is not tuple execution.
#warnings("-unused_constructor")
pub enum Poll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(Delta, progress~ : Int64, work~ : Int64)
  Failed(Issue, progress~ : Int64, work~ : Int64)
}

///|
#warnings("-struct_never_constructed")
struct Delta {
  value : @value.CheckedValue
  base_cid : String
  target_cid : String
}

///|
/// No preparation can be issued until independent-key delta semantics are
/// connected. The previous endpoint-tuple delta implementation is retired.
#warnings("-struct_never_constructed")
struct Preparation {
  closed : Bool
}

///|
fn valid_limits(limits : Limits) -> Bool {
  limits.max_workspace_slots >= 0 &&
  limits.max_output_nodes >= 0 &&
  limits.max_output_text_bytes >= 0 &&
  limits.max_output_depth >= 0 &&
  limits.max_identity_bytes >= 0 &&
  limits.max_identity_nodes >= 0 &&
  limits.max_identity_depth >= 0
}

///|
pub fn prepare(
  _left : @storage.Storage,
  _right : @storage.Storage,
  _delta_contract : @contract.Contract,
  _graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  Err(UnsupportedGraphOperation)
}

///|
pub fn prepare_view(
  _left : @lifecycle.ProducerView,
  _left_graph : @carrier.Graph,
  _right : @lifecycle.ProducerView,
  _right_graph : @carrier.Graph,
  _delta_contract : @contract.Contract,
  _graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  Err(UnsupportedGraphOperation)
}

///|
pub fn advance(
  _preparation : Preparation,
  _quantum : Int,
) -> Result[Poll, Issue] {
  Err(Terminal)
}

///|
pub fn value(delta : Delta) -> @value.CheckedValue {
  delta.value
}

///|
pub fn base_cid(delta : Delta) -> String {
  delta.base_cid
}

///|
pub fn target_cid(delta : Delta) -> String {
  delta.target_cid
}

///|
pub fn cleanup(preparation : Preparation) -> Bool {
  preparation.closed
}
