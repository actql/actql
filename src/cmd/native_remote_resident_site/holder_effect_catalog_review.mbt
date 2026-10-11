///|
/// Local references to existing credential, Store and capture Owners. This
/// keeps the original read/save responsibility with the same checked task;
/// it issues no new grant, Ledger, dispatch or cleanup evidence.
priv struct HolderEffectCatalogReviewCustody {
  installation : HolderEffectCatalogInstallation
  store : @publication_store.Store
  configuration : @effect_review.NativeResidentEffectReviewConfiguration
  connector_id : String
  describe_limits : @effect_catalog.DescribeLimits
  declaration_limits : @effect_catalog.DeclarationLimits
  max_observation_bytes : Int
  crypto : @signature.Library
  key : Bytes
  mut observed : (
    @effect_catalog.CatalogObservation,
    @effect_resource.NativeCredentialResponse,
  )?
  mut context : @resident_host.ResidentEffectReviewInputContext?
  mut retiring : Bool
  mut catalog_cleanup_confirmed : Bool
  mut read_started : Bool
  mut custody : @publication_store.EffectCatalogCustody?
  // Preserve the first failure, including a physical response whose Store
  // preparation failed. A later save failure cannot replace that evidence.
  mut read_issue : @effect_review.NativeSalesforceNamedCatalogIssue?
  mut read_failure : @effect_review.NativeSalesforceCatalogCustodyFailure?
}

///|
/// Raw read evidence can be carried by the existing typed failure as well as
/// a failed Store preparation. Neither form is cleanup-complete evidence.
fn holder_effect_catalog_failure_has_response(
  failure : @effect_review.NativeSalesforceCatalogCustodyFailure,
) -> Bool {
  if failure.response is Some(_) {
    return true
  }
  match failure.issue {
    Read(issue) => holder_effect_catalog_read_has_response(issue)
    _ => false
  }
}

///|
fn holder_effect_catalog_read_has_response(
  issue : @effect_review.NativeSalesforceNamedCatalogIssue,
) -> Bool {
  match issue {
    MetadataAuthorizationChanged(_)
    | MetadataReadUnavailable(_)
    | CatalogSyncFailure(_, _)
    | CatalogObservationFailure(_, _) => true
    _ => false
  }
}

///|
fn new_holder_effect_catalog_review_custody(
  installation : HolderEffectCatalogInstallation,
  store : @publication_store.Store,
  configuration : @effect_review.NativeResidentEffectReviewConfiguration,
  connector_id : String,
  describe_limits : @effect_catalog.DescribeLimits,
  declaration_limits : @effect_catalog.DeclarationLimits,
  max_observation_bytes : Int,
  crypto : @signature.Library,
  key : Bytes,
) -> HolderEffectCatalogReviewCustody {
  {
    installation,
    store,
    configuration,
    connector_id,
    describe_limits,
    declaration_limits,
    max_observation_bytes,
    crypto,
    key,
    observed: None,
    context: None,
    retiring: false,
    catalog_cleanup_confirmed: false,
    read_started: false,
    custody: None,
    read_issue: None,
    read_failure: None,
  }
}

///|
/// The service close does not retire Catalog bytes. Confirm each original
/// cleanup separately and retain the same failing handle for later retry.
fn HolderEffectCatalogReviewCustody::close(
  self : HolderEffectCatalogReviewCustody,
) -> Bool {
  self.retiring = true
  if self.context is Some(context) {
    if !context.close() {
      return false
    }
    self.context = None
  }
  if self.custody is None && self.observed is Some(_) {
    // Saving original read evidence is not disclosure or another Provider call.
    ignore(self.save_observed_catalog(() => false))
    if self.custody is None {
      return false
    }
  }
  // Failed Store preparation leaves a genuine response outside durable Store
  // custody. Handle closure alone cannot discharge that unresolved evidence.
  if !self.catalog_cleanup_confirmed &&
    self.custody is None &&
    (
      (
        self.read_failure is Some(failure) &&
        holder_effect_catalog_failure_has_response(failure)
      ) ||
      (
        self.read_issue is Some(issue) &&
        holder_effect_catalog_read_has_response(issue)
      )
    ) {
    return false
  }
  if self.custody is Some(custody) {
    match custody.retry_cleanup() {
      Ok(_) => {
        self.catalog_cleanup_confirmed = true
        self.custody = None
        self.observed = None
      }
      _ => return false
    }
  }
  if !self.installation.close() {
    return false
  }
  self.read_failure = None
  self.read_issue = None
  true
}

///|
/// Only the first call can enter the credential/Provider read. A prepared
/// custody retries its exact Store write/readback; a failure without custody
/// stays unresolved and cannot be hidden by another Provider read.
fn HolderEffectCatalogReviewCustody::confirm_catalog(
  self : HolderEffectCatalogReviewCustody,
  resources : HolderOutputResources,
  current : () -> Bool,
) -> Bool {
  if self.retiring || !physical_equal(self.store, resources.store) || !current() {
    return false
  }
  if self.custody is Some(pending) {
    return @effect_review.retry_native_salesforce_catalog_custody(
        pending, current,
      )
      is Ok(_)
  }
  if self.observed is Some(_) {
    return self.save_observed_catalog(current)
  }
  if self.read_started {
    return false
  }
  self.read_started = true
  match
    self.installation.read(self.describe_limits, self.max_observation_bytes) {
    Ok(observed) => {
      self.observed = Some(observed)
      // Even if authority changed during read, save its exact original response
      // before refusing adoption. The existing Store Owner fences disclosure.
      self.save_observed_catalog(current)
    }
    Err(issue) => {
      self.read_issue = Some(issue)
      false
    }
  }
}

///|
/// Retry preparation/persistence using the exact admitted observation, body and
/// use. The first failure remains available; no service or grant is invoked.
fn HolderEffectCatalogReviewCustody::save_observed_catalog(
  self : HolderEffectCatalogReviewCustody,
  current : () -> Bool,
) -> Bool {
  guard self.observed is Some((catalog, response)) else { return false }
  match
    @effect_review.retain_native_salesforce_named_catalog_response(
      self.store,
      catalog,
      response,
      self.installation.binding,
      self.installation.resource,
      self.describe_limits,
      self.crypto,
      self.key,
      current,
    ) {
    Ok((custody, _)) => {
      self.custody = Some(custody)
      true
    }
    Err(failure) => {
      self.custody = failure.pending
      if self.read_failure is None {
        self.read_failure = Some(failure)
      }
      false
    }
  }
}

///|
/// Bind the independent policy to the actual completed consumer before any
/// Provider read. Capture then joins that consumer with its original producer
/// journal; confirmed Catalog custody supplies metadata, never expected input.
fn prepare_holder_effect_catalog_review(
  task : HolderTaskCustody,
  original : HolderEffectOriginalPolicyContext,
  journal : @journal.Journal,
  resources : HolderOutputResources,
  catalog : HolderEffectCatalogReviewCustody,
  authorize_evidence_read : () -> Bool,
) -> Bool {
  let configuration = catalog.configuration
  let installed = catalog.installation
  guard original.invocation(
      configuration.preview_limits.max_wire_bytes,
      configuration.preview_limits.max_nodes,
      configuration.preview_limits.max_depth,
    )
    is Some((_, invocation)) else {
    return false
  }
  let invocation_cid = @publication.publication_contract_identity(invocation)
  let execution = @remote.dispatch_request_execution_scope(task.request)
  let current = () => {
    authorize_evidence_read() &&
    original.current() &&
    !catalog.retiring &&
    !installed.client_closed &&
    !installed.database_closed &&
    (installed.current)() &&
    installed.scope.dispatch_request_cid ==
    @remote.dispatch_request_identity(task.request) &&
    installed.scope.run_invocation_cid == invocation_cid &&
    installed.binding.run_invocation_cid == invocation_cid &&
    installed.binding.dispatch_request_cid ==
    installed.scope.dispatch_request_cid &&
    installed.binding.site_key == resources.site_key &&
    installed.binding.site_generation == resources.site_generation &&
    installed.scope.site_key == execution[0] &&
    installed.scope.site_generation.to_string() == execution[1] &&
    installed.scope.runtime_bundle_cid == execution[2] &&
    configuration.runtime_bundle_cid == execution[2] &&
    installed.api_version == configuration.api_version
  }
  if !current() {
    return false
  }
  if task.effect_review_cleanup is Some(pending) {
    if !pending.close() {
      return false
    }
    task.effect_review_cleanup = None
  }
  if catalog.context is None {
    let context = match
      original.consumer.prepare_effect_review_inputs(
        journal,
        original.producer,
        journal,
        configuration.stage,
        0,
        configuration.retention,
        configuration.export_limits,
        // Reuse the existing finite two-task connection budget.
        4,
        configuration.max_work,
        configuration.preview_limits.max_wire_bytes,
        configuration.preview_limits.max_nodes,
        configuration.preview_limits.max_depth,
      ) {
      Ok(value) => value
      Err(failure) => {
        task.effect_review_cleanup = failure.pending
        return false
      }
    }
    catalog.context = Some(context)
  }
  guard catalog.context is Some(context) else { return false }
  let evidence_current = () => {
    current() &&
    context.matches_holder(original.consumer, journal) &&
    context.source_binding_cid(journal) ==
    Some(configuration.source_binding_cid)
  }
  if !evidence_current() ||
    !catalog.confirm_catalog(resources, evidence_current) {
    return false
  }
  guard catalog.custody is Some(custody) && evidence_current() else {
    return false
  }
  // The Review preparation entry consumes this input context on both success
  // and rejection. Its existing pending cleanup handle remains task-owned.
  catalog.context = None
  match
    @effect_review.prepare_native_resident_effect_review_from_catalog_custody(
      original.consumer,
      journal,
      context,
      custody,
      installed.binding,
      catalog.connector_id,
      installed.resource,
      catalog.declaration_limits,
      configuration,
      evidence_current,
    ) {
    Ok(review) => {
      task.effect_review = Some(review)
      true
    }
    Err(failure) => {
      task.effect_review_cleanup = failure.pending
      false
    }
  }
}
