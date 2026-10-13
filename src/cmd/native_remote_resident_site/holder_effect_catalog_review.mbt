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
  read_original_use : () -> Result[
    @effect_credential.RemoteCredentialUse,
    @journal.NativeRemoteJournalIssue,
  ]
  publication : HolderEffectReviewPublication
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
  // The credential Owner supplies the original use, not Catalog/transport
  // bytes. These are restoration observations, never permission to resend.
  mut original_use : @effect_resource.NativeCredentialUseStatus?
  mut query_issue : HolderCatalogUseObservationIssue?
  mut restore_issue : @publication_store.NativePublicationStoreIssue?
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
  read_original_use : () -> Result[
    @effect_credential.RemoteCredentialUse,
    @journal.NativeRemoteJournalIssue,
  ],
  publication : HolderEffectReviewPublication,
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
    read_original_use,
    publication,
    observed: None,
    context: None,
    retiring: false,
    catalog_cleanup_confirmed: false,
    read_started: false,
    custody: None,
    read_issue: None,
    read_failure: None,
    original_use: None,
    query_issue: None,
    restore_issue: None,
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
  // Once an actual read was entered, a failure without a captured response
  // cannot prove there was no original use/GET. Reconcile through the same
  // Resource Owner before closing its DB; missing/unknown stays pending.
  if !holder_catalog_cleanup_original_use_observed(
      self.read_started,
      self.original_use is Some(_),
      self.custody is Some(_),
      self.observed is Some(_),
      () => self.query_original_catalog_use(),
    ) {
    return false
  }
  if !self.catalog_cleanup_confirmed && self.custody is None {
    if self.original_use is Some(_) {
      // Cleanup can restore exact original evidence without renewing current
      // disclosure permission. It still requires the authenticated Store/use.
      ignore(self.restore_original_catalog())
      if self.custody is None {
        return false
      }
    } else if self.query_issue is Some(_) {
      // Failed observation is not absence of an older physical use or Store.
      return false
    }
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
  self.original_use = None
  self.query_issue = None
  self.restore_issue = None
  true
}

///|
/// A previous query error is not permanent retirement evidence. Each cleanup
/// pass can inspect only the same original Journal/Resource use. This result
/// acknowledges observation only: claimed/unknown is neither successful GET
/// nor Store/physical cleanup, and no absence permits another read or claim.
fn holder_catalog_cleanup_original_use_observed(
  read_started : Bool,
  has_original_use : Bool,
  has_custody : Bool,
  has_observation : Bool,
  query : () -> Result[@effect_resource.NativeCredentialUseStatus?, Unit],
) -> Bool {
  if read_started &&
    !has_original_use &&
    !has_custody &&
    !has_observation {
    query() is Ok(Some(_))
  } else {
    true
  }
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
  if self.original_use is Some(_) || self.query_issue is Some(_) {
    return self.confirm_restored_catalog(current)
  }
  if self.read_started {
    return false
  }
  match self.query_original_catalog_use() {
    Ok(Some(_)) => return self.confirm_restored_catalog(current)
    Ok(None) => return false
    Err(_) => {
      guard self.query_issue is Some(issue) &&
        holder_catalog_initial_read_ready(issue, () => {
          self.installation.initial_use.ready()
        }) &&
        current() else {
        return false
      }
      // The original funded Owner supplied eligibility independently of this
      // missing-use observation. Resource still owns the actual first claim.
      self.query_issue = None
    }
  }
  self.read_started = true
  match
    self.installation.read(
      self.describe_limits,
      self.max_observation_bytes,
      current,
    ) {
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
/// Preserve the existing Owner's classification. A missing original journal or
/// credential record is unavailable responsibility, never an unsent proof.
priv enum HolderCatalogUseObservationIssue {
  Original(@journal.NativeRemoteJournalIssue)
  Resource(@effect_resource.NativeCredentialResourceIssue)
  Changed
}

///|
/// The original Journal Owner selects a nominal use before and after the
/// Resource query. This function issues no claim or Provider call and accepts
/// no use identity from a candidate response or replacement credential DB.
fn holder_catalog_original_use_query(
  read_original : () -> Result[
    @effect_credential.RemoteCredentialUse,
    @journal.NativeRemoteJournalIssue,
  ],
  query_resource : () -> Result[
    @effect_resource.NativeCredentialUseStatus,
    @effect_resource.NativeCredentialResourceIssue,
  ],
) -> Result[
  @effect_resource.NativeCredentialUseStatus,
  HolderCatalogUseObservationIssue,
] {
  let original = match read_original() {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  let status = match query_resource() {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  let current = match read_original() {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  let original_cid = @effect_credential.credential_use_cid(original)
  if @effect_credential.credential_use_cid(current) != original_cid ||
    status.use_cid != original_cid {
    return Err(Changed)
  }
  Ok(status)
}

///|
/// Restore only the use issued and retained for this original dispatch. The
/// initial nominal claim is a separate unfinished caller connection; missing
/// records here cannot enter that path or turn into a fresh Catalog GET.
fn HolderEffectCatalogReviewCustody::query_original_catalog_use(
  self : HolderEffectCatalogReviewCustody,
) -> Result[@effect_resource.NativeCredentialUseStatus?, Unit] {
  let installed = self.installation
  match
    holder_catalog_original_use_query(self.read_original_use, () => {
      @effect_resource.query_native_credential_use(
        installed.service,
        installed.grant,
        installed.use_id,
        installed.scope,
      )
    }) {
    Ok(status) => {
      if self.original_use is Some(original) &&
        original.use_cid != status.use_cid {
        self.query_issue = Some(Changed)
        return Err(())
      }
      self.original_use = Some(status)
      self.read_started = true
      self.query_issue = None
      Ok(Some(status))
    }
    Err(issue) => {
      self.query_issue = Some(issue)
      Err(())
    }
  }
}

///|
/// Fixed local reasons expose neither configured contents nor response bytes.
fn HolderEffectCatalogReviewCustody::pending_reason(
  self : HolderEffectCatalogReviewCustody,
) -> String {
  if self.installation.initial_use.issue is Some(_) {
    return "catalog-initial-claim"
  }
  if self.restore_issue is Some(_) {
    "catalog-restoration"
  } else {
    match self.query_issue {
      Some(Original(@journal.Physical(@sqlite.NotFound))) =>
        "catalog-original-use-missing"
      Some(Original(@journal.StaleSiteBinding)) => "catalog-original-use-site"
      Some(Original(_)) => "catalog-original-use"
      Some(Resource(@effect_resource.Journal(@sqlite.NotFound))) =>
        "catalog-use-observation-missing"
      Some(Resource(_)) => "catalog-use-observation"
      Some(Changed) => "catalog-use-binding"
      None => "original-custody"
    }
  }
}

///|
fn holder_catalog_use_succeeded(
  original : @effect_resource.NativeCredentialUseStatus,
) -> Bool {
  original.outcome == "succeeded" && original.status == Some(200)
}

///|
/// Restore only the scoped original Store record, including cleanup-only
/// tombstones. Missing/corrupt bytes retain responsibility and never start a
/// replacement read or reserve another observation holding.
fn HolderEffectCatalogReviewCustody::restore_original_catalog(
  self : HolderEffectCatalogReviewCustody,
) -> Bool {
  guard self.original_use is Some(original) else { return false }
  match
    self.store.restore_effect_catalog_custody(
      self.installation.binding,
      self.installation.resource,
      original.use_cid,
      self.describe_limits,
      self.crypto,
      self.key,
    ) {
    Ok(custody) => {
      self.custody = Some(custody)
      self.restore_issue = None
      true
    }
    Err(issue) => {
      self.restore_issue = Some(issue)
      false
    }
  }
}

///|
/// Read-only reconciliation may observe a later terminal credential record,
/// but its original use must remain identical. Unknown/claimed outcomes cannot
/// authorize Catalog adoption; restoration is not evidence-read permission.
fn HolderEffectCatalogReviewCustody::confirm_restored_catalog(
  self : HolderEffectCatalogReviewCustody,
  current : () -> Bool,
) -> Bool {
  if !current() {
    return false
  }
  guard self.query_original_catalog_use() is Ok(Some(original)) &&
    holder_catalog_use_succeeded(original) &&
    current() &&
    self.restore_original_catalog() &&
    self.custody is Some(custody) else {
    return false
  }
  @effect_review.retry_native_salesforce_catalog_custody(custody, current)
  is Ok(_)
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
    (catalog.publication.current)() &&
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
