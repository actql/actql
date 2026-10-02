///|
/// A retained decision of the existing account owner, not a new grant. The
/// installing Host supplies authenticated principals and any delegated answer.
pub struct DispatchAuthorization {
  configuration : AdmittedAccountConfiguration
  tuple : AccessTuple
  boundary : DecisionBoundary
  subject_cid : String
  context_cid : String
  basis : DispatchBasis
}

///|
pub(all) enum DispatchBindingIssue {
  InvalidSubject
  Denied
  UnresolvedDelegation
  ForeignDecision
} derive(Eq, Debug)

///|
/// Re-evaluate the exact tuple. A Host permit cannot override account denial,
/// or migrate from another tuple, configuration, subject or boundary.
pub fn bind_dispatch_authorization(
  configuration : AdmittedAccountConfiguration,
  tuple : AccessTuple,
  boundary : DecisionBoundary,
  subject_cid : String,
  context_cid : String,
  delegated_action? : RuntimeAction? = None,
) -> Result[DispatchAuthorization, DispatchBindingIssue] {
  if !valid_cid(subject_cid) || !valid_cid(context_cid) {
    return Err(InvalidSubject)
  }
  let basis = match evaluate_account(configuration, tuple) {
    Deny(_) => return Err(Denied)
    Allow(entry) => AccountAllow(entry)
    Delegate(matched) => {
      guard delegated_action
        is Some(AuthorizedForDispatch(HostPermit(subject, authority, claims))) else {
        return Err(UnresolvedDelegation)
      }
      if subject.account_id != configuration.account_id ||
        subject.configuration_cid != configuration.configuration_cid ||
        subject.entry_id != matched.entry_id ||
        subject.tuple != tuple ||
        subject.boundary != boundary ||
        subject.subject_cid != subject_cid ||
        subject.context_cid != context_cid {
        return Err(ForeignDecision)
      }
      HostPermit(subject, authority, claims.copy())
    }
  }
  Ok({ configuration, tuple, boundary, subject_cid, context_cid, basis, })
}

///|
pub fn dispatch_authorization_matches(
  value : DispatchAuthorization,
  current : AdmittedAccountConfiguration,
  tuple : AccessTuple,
  boundary : DecisionBoundary,
  subject_cid : String,
  context_cid : String,
) -> Bool {
  value.configuration.configuration_cid == current.configuration_cid &&
  value.configuration.account_id == current.account_id &&
  value.tuple == tuple &&
  value.boundary == boundary &&
  value.subject_cid == subject_cid &&
  value.context_cid == context_cid
}

///|
pub fn dispatch_authorization_configuration(
  value : DispatchAuthorization,
) -> AdmittedAccountConfiguration {
  value.configuration
}

///|
pub fn dispatch_authorization_tuple(
  value : DispatchAuthorization,
) -> AccessTuple {
  value.tuple
}

///|
pub fn dispatch_authorization_basis(
  value : DispatchAuthorization,
) -> DispatchBasis {
  value.basis
}
