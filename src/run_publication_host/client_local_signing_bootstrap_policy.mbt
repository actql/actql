///|
/// Packaged finite policy DATA, not an initialized issuer, current authority,
/// private-key original or durable use. The actual Host must authenticate this
/// original with its explicit first initialization, Store/key and adoption.
struct ClientLocalSigningBootstrapPolicy {
  wire : String
}

///|
/// First-issue candidate DATA only. Persist the actual sample and absolute
/// expiry with the same original operation before claiming/signing. Reopening
/// or a repeated answer must read that original, not call this to renew it.
struct ClientLocalSigningBootstrapIssue {
  sampled_at : Int64
  expires_at : Int64
}

///|
pub(all) enum ClientLocalSigningBootstrapIssueError {
  ForeignPolicy
  InvalidInitializationIdentity
  InvalidIssueTime
} derive(Eq, Debug)

///|
/// Select the pinned packaged policy for explicit first initialization only.
/// Calling this getter does not backfill an old installation or issue a grant.
pub fn client_local_default_signing_bootstrap_policy() -> ClientLocalSigningBootstrapPolicy {
  { wire: client_local_default_signing_policy_wire(), }
}

///|
/// Admit exact saved policy bytes. Authentication/custody of the initialized
/// original remains with the existing Host and journal, not this DATA reader.
pub fn admit_client_local_signing_bootstrap_policy(
  wire : String,
  expected_cid : String,
) -> Result[
  ClientLocalSigningBootstrapPolicy,
  ClientLocalSigningBootstrapIssueError,
] {
  let policy = client_local_default_signing_bootstrap_policy()
  if wire != policy.wire || expected_cid != policy.cid() {
    Err(ForeignPolicy)
  } else {
    Ok(policy)
  }
}

///|
pub fn ClientLocalSigningBootstrapPolicy::original_wire(
  self : ClientLocalSigningBootstrapPolicy,
) -> String {
  self.wire
}

///|
pub fn ClientLocalSigningBootstrapPolicy::cid(
  self : ClientLocalSigningBootstrapPolicy,
) -> String {
  product_cid(self.wire)
}

///|
/// The explicit identifier format over the original initialization intent CID,
/// never a new CID domain or proof of installation/issuer authority. The Host
/// must obtain this input from its same authenticated initialization original.
pub fn ClientLocalSigningBootstrapPolicy::issuer_identity(
  _self : ClientLocalSigningBootstrapPolicy,
  initialization_intent_cid : String,
) -> Result[String, ClientLocalSigningBootstrapIssueError] {
  if !valid_client_request_cid(initialization_intent_cid) {
    Err(InvalidInitializationIdentity)
  } else {
    Ok("local-signing/" + initialization_intent_cid)
  }
}

///|
/// Pure first-issue arithmetic, not a clock sampler, issuer or claim. The actual
/// trusted Host samples once inside its original durable issue, and supplies
/// the applicable earlier original key/authorization bound, if one exists.
pub fn ClientLocalSigningBootstrapPolicy::prepare_first_issue(
  _self : ClientLocalSigningBootstrapPolicy,
  trusted_sample_ms : Int64,
  original_valid_until_ms : Int64?,
) -> Result[
  ClientLocalSigningBootstrapIssue,
  ClientLocalSigningBootstrapIssueError,
] {
  // These fixed values are read from the same generated selected policy, not
  // duplicated policy constants in Host consumers or their fixtures.
  let interval = client_local_default_signing_issue_interval()
  if trusted_sample_ms < 0L ||
    trusted_sample_ms > 9223372036854775807L - interval {
    return Err(InvalidIssueTime)
  }
  let ceiling = trusted_sample_ms + interval
  let expires = match original_valid_until_ms {
    Some(bound) => {
      if bound <= trusted_sample_ms {
        return Err(InvalidIssueTime)
      }
      if bound < ceiling {
        bound
      } else {
        ceiling
      }
    }
    None => ceiling
  }
  Ok({ sampled_at: trusted_sample_ms, expires_at: expires, })
}

///|
/// Finite original selected policy, not usage availability or an ordinal claim.
pub fn ClientLocalSigningBootstrapPolicy::max_uses(
  _self : ClientLocalSigningBootstrapPolicy,
) -> Int {
  client_local_default_signing_max_uses()
}

///|
pub fn ClientLocalSigningBootstrapIssue::sampled_at(
  self : ClientLocalSigningBootstrapIssue,
) -> Int64 {
  self.sampled_at
}

///|
pub fn ClientLocalSigningBootstrapIssue::expires_at(
  self : ClientLocalSigningBootstrapIssue,
) -> Int64 {
  self.expires_at
}
