///|
/// Installed in-process Local materialization authority. This immutable policy
/// is not an allocation, a debit, or a global/concurrent-Run memory claim. Each
/// Run retains its own ledger and must admit its complete original inventory.
struct ClientLocalResourcePolicy {
  retained_bytes : Int64
  execution_bytes : Int64
  dispatch_planning_work : Int
  graph_work : Int
  relation_wire_bytes : Int
}

///|
let local_materialization_policy : ClientLocalResourcePolicy = {
  retained_bytes: 536870912L,
  execution_bytes: 536870912L,
  dispatch_planning_work: 100000,
  graph_work: @publication_host.client_standard_program_preparation_limits().max_graph_work,
  relation_wire_bytes: 1000000,
}

///|
pub fn client_local_resource_policy() -> ClientLocalResourcePolicy {
  local_materialization_policy
}

///|
fn client_local_retained_byte_ceiling() -> Int64 {
  local_materialization_policy.retained_bytes
}

///|
fn client_local_execution_byte_ceiling() -> Int64 {
  local_materialization_policy.execution_bytes
}

///|
fn client_local_joint_byte_ceiling() -> Int64 {
  Int64::min(
    client_local_retained_byte_ceiling(),
    client_local_execution_byte_ceiling(),
  )
}

///|
/// A necessary upper bound, never sufficient admission: even an empty-schema
/// materialized row consumes one output value node. The actual joint inventory
/// still funds every cell, name, input, intermediate, metadata and live workspace.
/// This fact does not apply to streaming or independently installed backends.
pub fn client_local_materialized_row_ceiling(
  policy : ClientLocalResourcePolicy,
  retained_bytes? : Int64? = None,
  execution_bytes? : Int64? = None,
) -> Int? {
  guard client_local_preparation_initial_limits(
      policy,
      retained_bytes~,
      execution_bytes~,
    )
    is Some(limits) else {
    return None
  }
  let unit = @execution.execution_capacity_node_bytes()
  if unit <= 0L {
    return None
  }
  // Each retained output node also occupies the same Run's execution memory.
  // This necessary bound selects no capacity and allocates no row storage.
  let rows = Int64::min(limits.retained_bytes, limits.execution_bytes) / unit
  if rows > 2147483647L {
    None
  } else {
    Some(rows.to_int())
  }
}

///|
/// Initial counters for a selected ordinary materializing-Local preparation.
/// Every graph task/edge insertion pays original graph work before allocation;
/// final Compute requirements are a narrowing of this same original ledger.
/// Compiler phase work counters remain distinct from dispatch planning work.
/// This does not cover Native acquisition, Model, Effect or Content recipes.
pub fn client_local_preparation_initial_limits(
  policy : ClientLocalResourcePolicy,
  retained_bytes? : Int64? = None,
  execution_bytes? : Int64? = None,
) -> @resources.LedgerLimits? {
  if !physical_equal(policy, local_materialization_policy) ||
    policy.graph_work < 0 ||
    policy.relation_wire_bytes < 0 {
    return None
  }
  // This DATA selects the SAME initial supplier before Request construction.
  // It is never a late resize or an allowance beside the original Ledger.
  // An explicit smaller ceiling is valid DATA too. The same initial owner
  // must admit its actual controls and each later constructor before use.
  let (retained, execution) = match (retained_bytes, execution_bytes) {
    (None, None) => (policy.retained_bytes, policy.execution_bytes)
    (Some(retained), Some(execution)) => {
      if retained <= 0L || execution <= 0L {
        return None
      }
      (retained, execution)
    }
    _ => return None
  }
  Some({
    planning_work: policy.dispatch_planning_work,
    attempts: policy.graph_work,
    holdings: policy.graph_work,
    transfer_bytes: policy.graph_work.to_int64() *
    policy.relation_wire_bytes.to_int64(),
    retained_bytes: retained,
    execution_bytes: execution,
  })
}

///|
// Installed source-free Compute work policy. This is a finite counter limit,
// not physical backing, currentness, permission or a replacement Ledger.
fn client_local_source_free_max_work(selected : Int?) -> Int? {
  let work = selected.unwrap_or(20000000)
  if work > 0 {
    Some(work)
  } else {
    None
  }
}
