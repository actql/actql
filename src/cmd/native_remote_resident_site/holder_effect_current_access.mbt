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
  original_identity : @effect_review.NativeEffectCloudHostIdentityRead
}

///|
/// Re-evaluate the existing Account/Decision Owner at every fence. Read and
/// publication have different tuples and boundaries; a read-only Allow or
/// delegated answer cannot authorize the Coordinator transfer. The installed
/// caller supplies fresh original identity before and after the decision; the
/// same current Account fence is repeated after the final identity HTTP read.
fn holder_effect_current_decision(
  subject : HolderEffectHostSubject,
  dispatch_cid : String,
  purpose : HolderEffectEvidencePurpose,
  read_current : (HolderEffectEvidencePurpose) -> HolderEffectHostCurrent?,
  current_original? : () -> Bool = () => true,
) -> Bool {
  if subject.principal.is_empty() || subject.account_id.is_empty() {
    return false
  }
  guard read_current(purpose) is Some(selected) &&
    current_original() &&
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
  allowed && (selected.current)() && current_original() && (selected.current)()
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
  guard current() &&
    physical_equal(
      admission.original_identity.control.client,
      resources.control,
    ) &&
    original.consumer.effect_original_dispatch(original.journal)
    is Some(dispatch) &&
    @remote.dispatch_request_identity(dispatch) ==
    @remote.dispatch_request_identity(original.task.request) &&
    admission.original_identity.scope.site_key == resources.site_key &&
    admission.original_identity.scope.site_generation ==
    resources.site_generation.to_int64() &&
    admission.original_identity.scope.authority_scope_cid ==
    resources.coordinator_authority &&
    holder_effect_control_read_url(
      resources.observation_url,
      "effect-host-identity-current",
    )
    is Some(identity_url) &&
    admission.original_identity.control.url == identity_url else {
    return false
  }
  let allowed = holder_effect_current_decision(
    admission.subject,
    @remote.dispatch_request_identity(original.task.request),
    purpose,
    admission.read_current,
    current_original=() => {
      guard current() &&
        admission.original_identity.read_original_consumer(
          original.consumer,
          original.producer,
          original.journal,
        )
        is Some(identity) else {
        return false
      }
      identity.principal_id() == admission.subject.principal && current()
    },
  )
  allowed && current()
}
