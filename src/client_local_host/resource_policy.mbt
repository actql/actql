///|
/// Installed in-process Local materialization authority. This immutable policy
/// is not an allocation, a debit, or a global/concurrent-Run memory claim. Each
/// Run retains its own ledger and must admit its complete original inventory.
struct ClientLocalResourcePolicy {
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
let local_materialization_policy : ClientLocalResourcePolicy = {
  retained_bytes: 536870912L,
  execution_bytes: 536870912L,
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
  Int64::min(client_local_retained_byte_ceiling(),client_local_execution_byte_ceiling())
}

///|
/// A necessary upper bound, never sufficient admission: even an empty-schema
/// materialized row consumes one output value node. The actual joint inventory
/// still funds every cell, name, input, intermediate, metadata and live workspace.
/// This fact does not apply to streaming or independently installed backends.
pub fn client_local_materialized_row_ceiling(policy : ClientLocalResourcePolicy) -> Int? {
  if !physical_equal(policy,local_materialization_policy) {return None}
  let unit=@execution.execution_capacity_node_bytes()
  if unit<=0L || policy.retained_bytes<0L {return None}
  let rows=policy.retained_bytes/unit
  if rows>2147483647L {None} else {Some(rows.to_int())}
}
