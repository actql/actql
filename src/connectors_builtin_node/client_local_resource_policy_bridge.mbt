///|
/// Nominal installed Local policy, not caller-selected numeric authority.
#export_name("clientLocalResourcePolicyOriginal")
pub fn client_local_resource_policy_original() -> @client_local_host.ClientLocalResourcePolicy {
  @client_local_host.client_local_resource_policy()
}

///|
/// Only the in-process materializing Local default installation may use this
/// coarse necessary ceiling. Existing retained environment identities remain
/// their original policy; this projection cannot reauthorize a recovered Run.
#export_name("clientLocalResourcePolicyRowCeiling")
pub fn client_local_resource_policy_row_ceiling(
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Int {
  @client_local_host.client_local_materialized_row_ceiling(policy).unwrap_or(-1)
}

///|
/// Fixed ordinary Local supplier projection. The caller cannot replace the
/// original policy or turn this necessary counter bound into a second ledger.
#export_name("clientLocalPreparationResourceLimits")
pub fn client_local_preparation_resource_limits(
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Array[Int64] {
  guard @client_local_host.client_local_preparation_initial_limits(policy)
    is Some(limits) else {
    return []
  }
  [
    limits.planning_work.to_int64(),
    limits.attempts.to_int64(),
    limits.holdings.to_int64(),
    limits.transfer_bytes,
    limits.retained_bytes,
    limits.execution_bytes,
  ]
}

///|
/// Read-only standard Model request window selected by the ordinary Local
/// installation. This DATA neither debits resources nor changes explicit Host
/// limits, and cannot reauthorize a retained Environment or recovered Run.
#export_name("clientLocalResourcePolicyModelRequestByteCeiling")
pub fn client_local_resource_policy_model_request_byte_ceiling(
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Int64 {
  guard @client_local_host.client_local_preparation_initial_limits(policy)
    is Some(_) else {
    return -1L
  }
  @infer_host.standard_limits().model.max_request_bytes
}
