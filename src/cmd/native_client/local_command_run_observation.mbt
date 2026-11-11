///|
// Caller retention within the existing command. Observation owns no Work,
// business domain, Result grant, Reader or replacement installation.
priv struct LocalCommandRunObservationOriginal {
  operation : @local_host.NativeLocalStoreOperation
  mut journal_operation : @local_host.NativeLocalStoreOperation?
  mut root_bridge : @local_sqlite.NativeStoreOperationOriginal?
  mut store : @local_store.Store?
  mut failure : @local_store.NativePublicationStoreOpenFailure?
  mut parent : @local_filesystem.Root?
  mut parent_failure : @local_filesystem.NativeRootOpenFailure?
  mut root : @local_filesystem.Root?
  mut root_failure : @local_filesystem.NativeRootOpenFailure?
  mut saved_effect_review : @local_host.NativeLocalSavedEffectReview?
  // Same successful Resolution's borrowed continuation. This command retains
  // it before any later claim/row constructor; it is not a second execution
  // owner, renewed approval, callback or physical cleanup acknowledgement.
  mut effect_resume : @local_host.NativeLocalEffectResumeOriginal?
  mut selected_namespace : String?
  mut attempted : Bool
  // Retain the exact failed Store receipt with this original across cleanup.
  mut _retained_store_issue : @local_store.NativePublicationStoreIssue?
}

///|
// Construct the routing receiver in outer control before entering the command
// Read. Activation and all original/configuration checks occur before Store IO.
fn LocalCommandPreparationOriginal::prepare_run_observation_operation(
  self : LocalCommandPreparationOriginal,
  journal? : Bool = false,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.host is Some(host) &&
    self.pair is Some(pair) &&
    self.journal is Some(capture) &&
    self.runtime is Some(runtime) &&
    self.saved_observation_business_disjoint() &&
    self.run_observation is None &&
    !self.phase_open &&
    !self.journal_read_open &&
    !self.closing &&
    !self.closed else {
    return Err(CommandRunObservationPending)
  }
  let library = match host.borrow_local_host_sqlite(pair) {
    Ok(value) => value
    Err(issue) => return Err(CommandPair(issue))
  }
  let operation = match
    @local_host.prepare_native_local_run_observation_store_operation(
      capture, runtime, library,
    ) {
    Ok(value) => value
    Err(issue) => return Err(CommandStoreOperation(issue))
  }
  let retained : LocalCommandRunObservationOriginal = {
    operation,
    journal_operation: None,
    root_bridge: None,
    store: None,
    failure: None,
    parent: None,
    parent_failure: None,
    root: None,
    root_failure: None,
    saved_effect_review: None,
    effect_resume: None,
    selected_namespace: None,
    attempted: false,
    _retained_store_issue: None,
  }
  // Retain the first original before preparing the separate Journal carrier.
  self.run_observation = Some(retained)
  if journal {
    match
      @local_host.prepare_native_local_run_observation_store_operation(
        capture, runtime, library,
      ) {
      Err(issue) => return Err(CommandStoreOperation(issue))
      Ok(value) => retained.journal_operation = Some(value)
    }
  }
  Ok(())
}

///|
fn LocalCommandPreparationOriginal::open_run_observation_store(
  self : LocalCommandPreparationOriginal,
  library : @local_sqlite.Library,
  managed : String,
  run : LocalRunInstallation,
) -> @local_store.Store raise ClientStop {
  guard self.run_observation is Some(original) &&
    self.saved_observation_business_disjoint() &&
    self.journal_read_open &&
    !self.closing &&
    !self.closed else {
    stop("LocalRunObservationOriginalUnavailable")
  }
  if original.store is Some(store) {
    guard original.selected_namespace == Some(run.namespace_id) &&
      original.root_bridge is Some(bridge) &&
      store.matches_original_operation(bridge) else {
      stop("LocalRunObservationForeignStore")
    }
    return store
  }
  if original.attempted {
    stop("LocalRunObservationStoreUnavailable")
  }
  // A failed first acquisition never becomes a second open or initializer.
  original.attempted = true
  original.selected_namespace = Some(run.namespace_id)
  command_preparation_result(
    original.operation.activate().map_err(issue => CommandStoreOperation(issue)),
  )
  let bridge = original.operation
    .sqlite_original()
    .unwrap_or_else(() => stop("LocalRunObservationOriginalUnavailable"))
  original.root_bridge = Some(bridge)
  let parent = match
    @local_filesystem.open_private_root_in_current_read_context_with_custody(
      managed,
      self.profile.diagnostic_ceiling,
    ) {
    Ok(value) => {
      original.parent = Some(value)
      value
    }
    Err(failure) => {
      original.parent_failure = Some(failure)
      stop("LocalRunObservationRootCleanupPending")
    }
  }
  match parent.inspect_directory(run.store_name) {
    Ok(Some(_)) => ()
    Ok(None) => stop("LocalOriginalStoreUnavailable")
    Err(_) => stop("LocalRunObservationStoreCustodyUnavailable")
  }
  let root = match parent.open_child_with_custody(run.store_name) {
    Ok(value) => {
      original.root = Some(value)
      value
    }
    Err(failure) => {
      original.root_failure = Some(failure)
      stop("LocalRunObservationRootCleanupPending")
    }
  }
  root
  .private_ownership()
  .unwrap_or_else(() => stop("LocalRunObservationStoreCustodyUnavailable"))
  |> ignore
  match
    @local_store.open_original_local_store_with_custody(
      library,
      bridge,
      managed + "/" + run.store_name,
      run.store_authority_cid,
      run.store_capacity_bytes,
      run.store_objects,
      run.store_record_bytes,
      existing=true,
      diagnostic_ceiling=Some(self.profile.diagnostic_ceiling),
    ) {
    Ok(store) => {
      original.store = Some(store)
      store
    }
    Err(CleanupRequired(failure)) => {
      original.failure = Some(failure)
      original._retained_store_issue = Some(failure.issue())
      stop("LocalRunObservationStoreCleanupPending")
    }
    Err(RefusedBeforeAcquisition(issue)) => {
      original._retained_store_issue = Some(issue)
      stop("LocalRunObservationStoreUnavailable")
    }
  }
}

///|
// Run only after the borrowed command Read returns. The same Store mirror is
// reconciled before lower-level scope recovery, child close or Root retirement.
fn LocalCommandPreparationOriginal::close_run_observation(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.run_observation is Some(original) else { return Ok(()) }
  if self.journal_read_open || self.phase_open {
    return Err(CommandRunObservationPending)
  }
  // Cut the dependent continuation before its Saved originals. Retiring
  // this DATA does not erase the durable Resolution/lease, refund work, stop
  // an operation or acknowledge physical Store/Root cleanup below.
  if original.effect_resume is Some(continuation) {
    continuation.retire_read_aliases()
    original.effect_resume = None
  }
  if original.saved_effect_review is Some(review) {
    // Read aliases do not own deletion of the historical encrypted evidence.
    review.retire_read_aliases()
    original.saved_effect_review = None
  }
  if original.store is Some(store) {
    match store.reconcile_original_return() {
      Err(issue) => return Err(CommandRunObservationStore(issue))
      Ok(_) => ()
    }
  }
  match original.operation.pending_scope() {
    Err(issue) => return Err(CommandStoreOperation(issue))
    Ok(true) =>
      match original.operation.retry_scope_cleanup() {
        Err(issue) => return Err(CommandStoreOperation(issue))
        Ok(_) => ()
      }
    Ok(false) => ()
  }
  if original.failure is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(CommandRunObservationStore(issue))
      Ok(_) => original.failure = None
    }
  }
  if original.store is Some(store) {
    match store.close() {
      Err(issue) => return Err(CommandRunObservationStore(issue))
      Ok(_) => original.store = None
    }
  }
  if original.parent is Some(_) ||
    original.parent_failure is Some(_) ||
    original.root is Some(_) ||
    original.root_failure is Some(_) {
    guard original.root_bridge is Some(bridge) else {
      return Err(CommandRunObservationPending)
    }
    match bridge.enter_cleanup_work() {
      Err(issue) =>
        return Err(CommandStoreOperation(StoreOperationSqlite(issue)))
      Ok(_) => ()
    }
    let closed = original.close_root_descriptors()
    let returned = bridge.leave_store()
    match (closed, returned) {
      (Err(issue), _) => return Err(issue)
      (Ok(_), Err(issue)) =>
        return Err(CommandStoreOperation(StoreOperationSqlite(issue)))
      (Ok(_), Ok(_)) => {
        original.root_failure = None
        original.root = None
        original.parent_failure = None
        original.parent = None
      }
    }
  }
  original.root_bridge = None
  if original.journal_operation is Some(journal) {
    match journal.close_captured_journal_database() {
      Err(issue) => return Err(CommandStoreOperation(issue))
      Ok(_) => original.journal_operation = None
    }
  }
  match original.operation.close_checked() {
    Err(issue) => Err(CommandStoreOperation(issue))
    Ok(_) => {
      self.run_observation = None
      Ok(())
    }
  }
}

///|
fn LocalCommandRunObservationOriginal::close_root_descriptors(
  self : LocalCommandRunObservationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.root_failure is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  if self.root is Some(root) {
    match root.close() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  if self.parent_failure is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  if self.parent is Some(parent) {
    match parent.close() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
// Exact current RunRead selection precedes any Store open. The adopted Runtime
// and original selected_namespace join this same installed Store; no Result read grant
// or business installation is selected merely to observe availability.
fn LocalCommandPreparationOriginal::refresh_run_observation_state(
  self : LocalCommandPreparationOriginal,
  host : @local_host.NativeLocalHostConnection,
  capture : @local_host.NativeLocalJournalCapture,
  configuration : LocalCommandConfiguration,
  runtime : LocalPackagedRuntime,
  id : String,
) -> @local_host.NativeClientSavedRunStateSelection raise ClientStop {
  let settings = configuration.settings
  guard self.journal is Some(actual_capture) &&
    physical_equal(actual_capture, capture) &&
    capture.original_host() is Some(actual_host) &&
    physical_equal(actual_host, host) &&
    self.runtime is Some(actual_runtime) &&
    physical_equal(actual_runtime, runtime.physical) &&
    self.run_observation is Some(observation) &&
    self.saved_observation_business_disjoint() &&
    self.journal_read_open &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    stop("LocalRunObservationOriginalUnavailable")
  }
  // execute_adopted_command joined these same immutable configuration bytes
  // to this capture before dispatch. Observing the saved Run does not need
  // another JSON decode or Program Environment admission.
  let environment_name = configuration.environment_name
  let run_file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunOriginalNotSelected")
  })
  local_host_result(
    capture.bind_packaged_runtime_in_original_read(
      runtime.physical,
      settings.principal,
      settings.connection,
      environment_name,
      run_file,
      "runtime.json",
    ),
  )
  |> ignore
  let original = match
    local_host_result(
      capture.lookup_submitted_run_original_by_id_in_original_read(
        settings.principal,
        settings.connection,
        id,
      ),
    ) {
    Ok(value) => value
    Err(issue) => stop(local_saved_state_issue(issue))
  }
  let scope = local_host_result(
    capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    ),
  )
  let reference = local_original_run_reference(original.definition(), scope)
  guard reference is Object(fields) &&
    json_text(fields, "namespaceId") is Some(namespace_id) else {
    stop("LocalOriginalRunUnavailable")
  }
  let run = configuration.run_installation(
    run_file,
    local_host_result(capture.selected_configuration_in_original_read(run_file)),
  )
  if run.namespace_id != namespace_id {
    stop("LocalOriginalRunReferenceMismatch")
  }
  let managed = local_host_result(capture.managed_root_path_in_original_read()).unwrap_or_else(() => {
      stop("LocalManagedRootRequired")
    },
  )
  local_host_result(capture.check_current_in_original_read()) |> ignore
  guard self.host is Some(physical) && self.pair is Some(pair) else {
    stop("LocalRunObservationOriginalUnavailable")
  }
  let library = physical
    .borrow_local_host_sqlite(pair)
    .unwrap_or_else(() => stop("LocalRunObservationOriginalUnavailable"))
  let store = self.open_run_observation_store(library, managed, run)
  let refreshed = local_host_result(
    capture.refresh_original_run_availability_in_original_read(
      settings.principal,
      settings.connection,
      original,
      store,
      namespace_id,
      observation.operation,
      local_utc_now(),
      @env.now().to_double(),
    ),
  )
  match refreshed {
    Ok(value) => value
    Err(issue) => stop(local_saved_state_issue(issue))
  }
}

///|
// A saved continuation can select the existing physical execution facility,
// while this same command retains its distinct original observation Store.
// Never admit fresh Request/Compute state or a second business Store here.
fn LocalCommandPreparationOriginal::saved_observation_business_disjoint(
  self : Self,
) -> Bool {
  match self.business {
    None => true
    Some(business) =>
      (
        business.profile.kind == SavedEffectApply ||
        (
          business.profile.kind == SourceFreeCompute &&
          business.selected_profile is None &&
          business.domain is None &&
          business.execution is None &&
          business.operation is None &&
          business.request_intent is None &&
          business.request_body is None
        )
      ) &&
      business.request_input is None &&
      business.request_initial is None &&
      business.request_parent is None &&
      business.request_run is None &&
      business.effect_model is None &&
      business.values_work is None &&
      business.model_work.is_empty() &&
      business.store is None &&
      business.store_failure is None &&
      !business.active
  }
}
