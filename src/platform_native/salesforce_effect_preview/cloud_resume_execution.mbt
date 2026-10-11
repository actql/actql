///|
/// Independent existing Host/Provider installation, with no cached Reviewer
/// authentication. Original principal, key and current claim are read through
/// the scoped Cloud control channel when the retained Resume is consumed.
pub(all) struct NativeResidentEffectCloudResumeInstallation {
  crypto : @signature.Library
  scope : NativeEffectCloudReviewerScope
  keys : Array[NativeEffectHostAuthority]
  current_authority : () -> Bool
  now : () -> String
  limits : NativeResidentEffectWriteLimits
  access : (@catalog.SingleWriteRequest) -> Result[
    NativeSalesforceTargetAccess,
    NativeResidentEffectWriteIssue,
  ]
}

///|
/// Keep the current original Reviewer selection through the row Owner's last
/// send fence. A changed context returns false, not permission to retry work.
fn native_cloud_reviewer_authority_current(
  installation : NativeEffectReviewerInstallation,
  selected : NativeEffectReviewerSelection,
  key_id : String,
  current : () -> Bool,
) -> Bool {
  native_cloud_reviewer_read_current(
    () => (installation.read_current)(selected, key_id) is Some(_),
    installation.current_site,
    current,
  )
}

///|
fn native_cloud_reviewer_read_current(
  read_current : () -> Bool,
  current_site : () -> Bool,
  current : () -> Bool,
) -> Bool {
  current() && current_site() && read_current() && current_site() && current()
}

///|
/// Actual Reviewer proof and independent Host attestation precede the existing
/// Resume/Ledger/Provider row. Later authorization checks reread the same
/// registration and claim; no signer-derived principal or static approval is
/// installed here. Settlement retains the existing no-resend responsibility.
pub fn NativeResidentEffectReview::execute_remote_approved_row_with_cloud_reviewer(
  self : NativeResidentEffectReview,
  body : String,
  installed : NativeResidentEffectCloudResumeInstallation,
  claim_control : NativeEffectCloudCurrentRead,
  reviewer_control : NativeEffectCloudCurrentRead,
  current_site : () -> Bool,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeResidentEffectWriteIssue,
] {
  let current = () => current_site() && (installed.current_authority)()
  if !current() {
    return Err(AuthorityDenied)
  }
  let (principal, reviewer) = match
    self.cloud_reviewer_installation(
      body,
      { control: reviewer_control, scope: installed.scope, },
      installed.crypto,
      installed.limits.ledger,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resolution(issue))
  }
  let authentication = match
    self.authenticate_remote_reviewer(
      body,
      principal,
      reviewer,
      installed.keys,
      current,
      installed.now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resolution(issue))
  }
  guard self.retention is Some(retention) else { return Err(Unavailable) }
  let report = match retention.report() {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  let selected : NativeEffectReviewerSelection = {
    principal_id: principal,
    checkpoint_cid: @remote.remote_effect_checkpoint_report_checkpoint(report).checkpoint_cid,
  }
  let reviewers : Array[@checkpoint.ReviewerAuthority] = [
    { key_id: authentication.key_id, reviewer_id: authentication.reviewer_id, },
  ]
  let current_reviewer = () => {
    native_cloud_reviewer_authority_current(
      reviewer,
      selected,
      authentication.key_id,
      current,
    )
  }
  self.execute_remote_approved_row_with_cloud_current(
    body,
    {
      authentication,
      reviewers,
      keys: installed.keys,
      current_authority: current_reviewer,
      // The existing claim observer is supplied by the authenticated control
      // adapter below. No wire-derived observation is used as a fallback.
      observe_resume: () => None,
      now: installed.now,
      limits: installed.limits,
      access: installed.access,
    },
    claim_control,
    current_site,
  )
}
