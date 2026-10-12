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
