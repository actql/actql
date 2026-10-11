///|
/// Independent Host installation. Transport bytes cannot supply these roles,
/// signing keys, current resume observations or mutation credentials. The
/// access callback selects an existing exact credential use, never a new Run.
pub(all) struct NativeResidentEffectResumeConfiguration {
  authentication : @checkpoint.HostAuthentication
  reviewers : Array[@checkpoint.ReviewerAuthority]
  keys : Array[NativeEffectHostAuthority]
  current_authority : () -> Bool
  observe_resume : () -> NativeEffectResumeObservation?
  now : () -> String
  limits : NativeResidentEffectWriteLimits
  access : (@catalog.SingleWriteRequest) -> Result[
    NativeSalesforceTargetAccess,
    NativeResidentEffectWriteIssue,
  ]
}

///|
/// Join an admitted original delivery to this same Review and row Owner.
/// The trusted observation must confirm the wire's claim independently;
/// historical signature or Source authority cannot grant mutation permission.
pub fn NativeResidentEffectReview::execute_remote_approved_row(
  self : NativeResidentEffectReview,
  body : String,
  configuration : NativeResidentEffectResumeConfiguration,
  current_site : () -> Bool,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeResidentEffectWriteIssue,
] {
  let current = () => current_site() && (configuration.current_authority)()
  let row = match
    self.prepare_remote_approved_row(
      body,
      configuration.authentication,
      configuration.reviewers,
      configuration.keys,
      current,
      configuration.observe_resume,
      configuration.now,
      configuration.limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  row.execute_or_settle(configuration.access)
}

///|
/// Retry only the exact row's saved response and common terminal receipt.
/// Once a send was attempted or its claim was restored, even selecting a new
/// credential is forbidden here. Missing response evidence stays unresolved.
pub fn NativeResidentEffectApprovedRow::execute_or_settle(
  self : NativeResidentEffectApprovedRow,
  access : (@catalog.SingleWriteRequest) -> Result[
    NativeSalesforceTargetAccess,
    NativeResidentEffectWriteIssue,
  ],
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeResidentEffectWriteIssue,
] {
  if self.started || self.dispatching is Some(_) {
    return self.settle()
  }
  if !self.current() {
    return Err(AuthorityDenied)
  }
  let installed = match access(self.request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.send(installed) {
    Ok(_) => self.settle()
    Err(issue) => Err(issue)
  }
}

///|
/// Local progress can finish retained response persistence without renewing
/// write authority. It never prepares a row or invokes a Provider. The caller
/// separately checks current evidence access and the holder's Site custody.
pub fn NativeResidentEffectReview::retry_approved_row_custody(
  self : NativeResidentEffectReview,
) -> Result[Bool, NativeResidentEffectWriteIssue] {
  if !self.effect_pending {
    return Ok(false)
  }
  guard self.current() && self.approved_row is Some(row) else {
    return Err(Unavailable)
  }
  row.settle().map(_ => true)
}
