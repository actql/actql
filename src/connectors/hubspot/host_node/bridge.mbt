// Pure HubSpot projections for the Site's physical adapter. Bytes and limits
// cross this boundary, never a credential, permission or foreign opaque Owner.

///|
fn account_issue_json(issue : @catalog.AccountIdentityIssue) -> Json {
  let kind = match issue {
    InvalidLimits => "InvalidLimits"
    BudgetExceeded => "BudgetExceeded"
    InvalidResponse => "InvalidResponse"
    ForeignAccount => "ForeignAccount"
  }
  { "issue": kind.to_json() }
}

///|
/// The expected identifier comes from the original account observation. It
/// is not a request selector, credential identity, or authorization evidence.
#export_name("hubspotRecheckAccountIdentityJson")
pub fn hubspot_recheck_account_identity_json(
  bytes : Bytes,
  original_portal_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String {
  let observation = match
    @catalog.project_account_identity(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return ({ "refused": account_issue_json(issue) } : Json).stringify()
  }
  match @catalog.recheck_account_identity(observation, original_portal_id) {
    Ok(_) => ()
    Err(issue) =>
      return ({ "refused": account_issue_json(issue) } : Json).stringify()
  }
  (
    {
      "account": {
        "portalId": observation.portal_id.to_string().to_json(),
        "responseSha256": observation.response_sha256.to_json(),
      },
    } : Json).stringify()
}
