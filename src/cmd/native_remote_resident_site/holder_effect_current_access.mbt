///|
/// Host purposes use existing account operations and decision boundaries.
/// Neither purpose grants Provider access or approves an Effect.
priv enum HolderEffectEvidencePurpose {
  Read
  Publication
}

///|
/// Facts selected from the authenticated original Host admission, not from
/// materials, a scope CID, the Site operator or the Reviewer. Selectors belong
/// to the installing Host application. This private record has no wire issuer.
priv struct HolderEffectHostSubject {
  principal : String
  account_id : String
  configuration_cid : String
  authorization_context_cid : String
  read_connection : String
  read_resource : String
  publication_connection : String
  publication_resource : String
}

///|
/// The installed Host must obtain this from its current admission/decision
/// Owners. `current` covers authentication, permission expiry/revocation and
/// policy revision, including delegated answers; account matching alone does
/// not prove that a previously issued Host Permit is still valid.
priv struct HolderEffectHostCurrent {
  configuration : @authorization.AdmittedAccountConfiguration
  delegated_action : @authorization.RuntimeAction?
  current : () -> Bool
}

///|
/// Borrowed original custody paired with the actual authenticated Host
/// admission. The installer must retain that original admission across reads;
/// a newly authenticated caller cannot replace it. No resource Owner is added.
priv struct HolderEffectHostAdmission {
  original : HolderEffectOriginalPolicyContext
  subject : HolderEffectHostSubject
  receiver_origin : String
  observation_url : String
  site_key : String
  site_generation : Int
  read_current : (HolderEffectEvidencePurpose) -> HolderEffectHostCurrent?
}

///|
/// Re-evaluate the existing Account/Decision Owner at every fence. Read and
/// publication have different tuples and boundaries; a read-only Allow or
/// delegated answer cannot authorize the Coordinator transfer.
fn holder_effect_current_decision(
  subject : HolderEffectHostSubject,
  dispatch_cid : String,
  purpose : HolderEffectEvidencePurpose,
  read_current : (HolderEffectEvidencePurpose) -> HolderEffectHostCurrent?,
) -> Bool {
  if subject.principal.is_empty() || subject.account_id.is_empty() {
    return false
  }
  guard read_current(purpose) is Some(selected) &&
    (selected.current)() &&
    selected.configuration.account_id() == subject.account_id &&
    selected.configuration.configuration_cid() == subject.configuration_cid else {
    return false
  }
  let (connection, resource, operation, boundary) = match purpose {
    Read =>
      (
        subject.read_connection,
        subject.read_resource,
        "read",
        @authorization.Acquisition,
      )
    Publication =>
      (
        subject.publication_connection,
        subject.publication_resource,
        "write",
        @authorization.Transfer,
      )
  }
  if connection.is_empty() || resource.is_empty() {
    return false
  }
  let allowed = @authorization.bind_dispatch_authorization(
      selected.configuration,
      { principal: subject.principal, connection, resource, operation, },
      boundary,
      dispatch_cid,
      subject.authorization_context_cid,
      delegated_action=selected.delegated_action,
    )
    is Ok(_)
  allowed && (selected.current)()
}

///|
/// A remote query supplies no principal. Select current authority only from
/// the retained original context and trusted Host admission. Recheck custody
/// after both admission selection and the fallible current decision lookup.
fn holder_effect_evidence_allowed(
  original : HolderEffectOriginalPolicyContext,
  resources : HolderOutputResources,
  purpose : HolderEffectEvidencePurpose,
  select : (HolderEffectOriginalPolicyContext) -> HolderEffectHostAdmission?,
) -> Bool {
  guard original.current() && select(original) is Some(admission) else {
    return false
  }
  let current = () => {
    original.current() &&
    admission.original.current() &&
    physical_equal(admission.original.task, original.task) &&
    physical_equal(admission.original.producer_task, original.producer_task) &&
    physical_equal(admission.original.consumer, original.consumer) &&
    physical_equal(admission.original.producer, original.producer) &&
    physical_equal(admission.original.journal, original.journal) &&
    physical_equal(
      admission.original.materials.prepared,
      original.materials.prepared,
    ) &&
    admission.original.request == original.request &&
    admission.receiver_origin == resources.destination_origin &&
    admission.observation_url == resources.observation_url &&
    admission.site_key == resources.site_key &&
    admission.site_generation == resources.site_generation &&
    @remote.dispatch_request_execution_scope(original.task.request)[0] ==
    admission.site_key &&
    @remote.dispatch_request_execution_scope(original.task.request)[1] ==
    admission.site_generation.to_string()
  }
  guard current() else { return false }
  let allowed = holder_effect_current_decision(
    admission.subject,
    @remote.dispatch_request_identity(original.task.request),
    purpose,
    admission.read_current,
  )
  allowed && current()
}
