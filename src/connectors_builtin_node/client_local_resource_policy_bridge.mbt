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
pub fn client_local_resource_policy_row_ceiling(policy : @client_local_host.ClientLocalResourcePolicy) -> Int {
  @client_local_host.client_local_materialized_row_ceiling(policy).unwrap_or(-1)
}
