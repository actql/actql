///|
/// Two admitted retention envelopes may describe different effective data
/// policies while retaining exactly the same custody contract and time bounds.
/// This does not authorize changing either policy or extending a dependency.
pub fn result_retention_bounds_equal(
  left : PublicationContract,
  right : PublicationContract,
) -> Bool {
  if left.name != "result_retention_policy" ||
    right.name != "result_retention_policy" {
    return false
  }
  for
    field in [
      "retention_contract_cid", "available_until", "delete_by", "extension_ceiling_at",
      "metadata_retention_policy_cid", "metadata_delete_by", "clock_contract_cid",
    ] {
    if contract_string(left, field) != contract_string(right, field) {
      return false
    }
  }
  true
}
