///|
/// Project the existing retention Owner's interval state before a Result
/// Manifest exists. This is metadata only: it does not authorize publication
/// or reading, bind a named Result, or issue a grant.
pub fn result_retention_interval_state(
  retention : PublicationContract,
  observed_at : String,
) -> Result[String, DeliveryIssuanceIssue] {
  retention_interval_state(retention, observed_at)
}

///|
/// Borrow the four fixed deadlines of the admitted Result retention contract.
/// The installed Portable Model profile can select a Raw interval within
/// these same outer deadlines. This projection cannot renew the contract.
pub fn result_retention_capture_bounds(
  retention : PublicationContract,
  retention_cid : String,
  metadata_cid : String,
  clock_cid : String,
  data_cid : String,
) -> (String, String, String, String)? {
  guard result_retention_intervals_valid(retention) &&
    contract_string(retention, "retention_contract_cid") == Some(retention_cid) &&
    contract_string(retention, "metadata_retention_policy_cid") ==
    Some(metadata_cid) &&
    contract_string(retention, "clock_contract_cid") == Some(clock_cid) &&
    contract_string(retention, "effective_data_policy_cid") == Some(data_cid) &&
    contract_string(retention, "available_until") is Some(available) &&
    contract_string(retention, "delete_by") is Some(deletion) &&
    contract_string(retention, "extension_ceiling_at") is Some(ceiling) &&
    contract_string(retention, "metadata_delete_by") is Some(metadata) else {
    return None
  }
  Some((available, deletion, ceiling, metadata))
}
