///|
// Installer-private command retention selection. Compute uses its own backed
// domain; saved Result uses the existing bounded Read/SQLite facilities.
// Neither selection issues resources, permissions or cleanup acknowledgements.
priv enum LocalCommandBusinessKind {
  SourceFreeCompute
  SavedResultRead
} derive(Eq)

///|
priv struct LocalCommandBusinessProfile {
  kind : LocalCommandBusinessKind
  domain_bytes : Int64
  payload_facility_bytes : Int64
  limits : @initial_resources.LedgerLimits
}

///|
// One existing command slot retains either actual observation. Neither branch
// manufactures a Publisher or an execution/publication acknowledgement.
priv enum LocalRunReceiptObservation {
  FreshRunReceipt(@local_host.NativeLocalObservedRunState)
  RetainedRunReceipt(@local_host.NativeLocalRetainedRunReceipt)
}

///|
// Caller retention only. The existing Host/domain/retained-execution Owners
// keep every partial physical stage and their distinct acknowledgements.
priv struct LocalCommandBusinessOriginal {
  profile : LocalCommandBusinessProfile
  mut selected_profile : LocalCommandBusinessProfile?
  mut domain : @initial_arena.InstalledArenaDomain?
  mut execution : @initial_arena.InstalledArenaRetainedExecution?
  // The SAME original input and preparation survive Journal scope switches.
  mut request_input : @run_host.ClientSubmittedIntent?
  mut request_initial : @initial_resources.BackedPreparationAdmission[
    @run_host.ClientSubmittedIntent,
  ]?
  mut request_parent : @local_values.ClientRequestPreparation[
    @run_host.ClientSubmittedIntent,
  ]?
  mut request_body : @initial_resources.PreparationBodyBorrow[
    @run_host.PreparedClientProgram,
  ]?
  mut request_run : @local_values.ClientInstalledManagedRun?
  mut request_retiring : Bool
  mut operation : @local_host.NativeLocalStoreOperation?
  mut values_work : @local_host.NativeClientValuesWork?
  mut values_failure : @local_host.NativeClientValuesWorkFailure?
  mut store : @local_store.Store?
  mut store_failure : @local_store.NativePublicationStoreOpenFailure?
  mut store_parent : @local_filesystem.Root?
  mut store_parent_failure : @local_filesystem.NativeRootOpenFailure?
  mut store_root : @local_filesystem.Root?
  mut store_root_failure : @local_filesystem.NativeRootOpenFailure?
  mut store_root_operation : @local_sqlite.NativeStoreOperationOriginal?
  mut publication_publisher : @local_host.NativeLocalPublisherBinding?
  // Keep the actual service alias until the same publication cleanup ACK.
  // It is lifetime custody, not a value read or a replacement authority.
  mut _retained_publication_service : @local_publication.NativeRunPublicationService?
  mut publication_results : Array[
    @local_publication.NativeCapturedResultPublicationContext,
  ]?
  mut publication_pending : @local_publication.NativePreparedCapturedRunPublication?
  mut publication_failure : @local_host.NativeClientValuesPublicationIssue?
  // Preserve original managed failure receipts across retries until cleanup
  // confirms their domains can retire; an unread payload is not an ACK.
  mut _retained_publication_commit_failure : @local_publication.NativeRunPublicationIssue?
  mut _retained_publication_cleanup_failure : @local_publication.NativeCapturedRunPublicationCancellationIssue?
  mut publication_attempted : Bool
  mut publication_result : @local_publication.NativeRunPublicationResult?
  mut run_receipt_original : LocalRunReceiptObservation?
  mut publication_retired : Bool
  // Retain the original payload path before poll/return/close can fail.
  // These aliases do not acknowledge a Store, domain or delivery receipt.
  mut result_binding : @local_host.NativeLocalReadPolicyBinding?
  mut result_service : @local_result.NativeResultAccessService?
  mut result_session : @local_result.NativeResultAccessSession?
  mut result_material : @local_result.NativeResultMaterialReceiver?
  mut result_sink : @local_result.NativeResultSink?
  mut result_refusal : Ref[@local_host.NativeLocalReadBindingIssue?]?
  mut result_cleanup_issue : @local_result.NativeResultAccessIssue?
  mut active : Bool
}

///|
fn local_command_domain_bytes(payload : Int64) -> Int64? {
  if payload <= 0L {
    return None
  }
  // The layout provider accepts a page-aligned domain candidate. Checked
  // Program requirements count payload bytes and need not have that alignment.
  let mut bytes = match
    native_storage_page_round(payload, native_storage_page_bytes()) {
    Ok(value) => value
    Err(_) => return None
  }
  for _ in 0..<16 {
    let necessary = @initial_bootstrap.execution_domain_necessary_bytes(
      bytes, payload,
    )
    if necessary <= 0L {
      return None
    }
    if necessary <= bytes {
      return Some(bytes)
    }
    bytes = necessary
  }
  None
}

///|
// Declare the selected parent before its first physical acquisition. Complete
// external/initial overlap remains mandatory alongside this backed facility.
// The payload is a hard backed facility, not residual space or an estimate of
// every Program. Same-source Program limits must fit it before issue_epoch.
fn local_command_source_free_business_profile(
  static_profile : LocalCommandPreparationProfile,
) -> (LocalCommandPreparationProfile, LocalCommandBusinessProfile) raise ClientStop {
  // The existing Local host admits at most 32 physical tasks. Declare their
  // one-shot attempts, output holdings and bounded transfers before acquiring
  // the facility; the exact Program quote below can still refuse this budget.
  let task_capacity = 32
  let limits : @initial_resources.LedgerLimits = {
    planning_work: 100000,
    attempts: task_capacity,
    holdings: task_capacity,
    transfer_bytes: task_capacity.to_int64() * 1000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }
  let payload = limits.retained_bytes + limits.execution_bytes
  let bytes = local_command_domain_bytes(payload).unwrap_or_else(() => {
    stop("LocalBusinessLayoutUnavailable")
  })
  let domains = native_storage_sum([
    static_profile.read_domain_bytes,
    static_profile.sqlite_domain_bytes,
    bytes,
  ]).unwrap_or_else(() => stop("LocalBusinessLayoutUnavailable"))
  let (arena, control) = local_command_backing_layout(domains).unwrap_or_else(() => {
    stop("LocalBusinessLayoutUnavailable")
  })
  let original = static_profile.host_limits
  let profile : LocalCommandPreparationProfile = {
    ..static_profile,
    arena_bytes: arena,
    control_bytes: control,
    host_limits: {
      ..original,
      planning_work: original.planning_work + limits.planning_work,
      // The original business provisioning attempt and declared task attempts
      // occur once. Scope changes and child close do not refill them.
      attempts: original.attempts + 1 + limits.attempts,
      holdings: original.holdings + limits.holdings,
      transfer_bytes: original.transfer_bytes + limits.transfer_bytes,
      execution_bytes: arena,
    },
    native_storage: {
      ..static_profile.native_storage,
      shared_control_bytes: Some(control),
    },
  }
  (
    profile,
    {
      kind: SourceFreeCompute,
      domain_bytes: bytes,
      payload_facility_bytes: payload,
      limits,
    },
  )
}

///|
// Saved Result performs bounded metadata, verification, decoding and output in
// the existing command Read/SQLite facilities. This retains caller cleanup
// state but selects no Compute domain, execution or Ledger capacity.
fn local_command_saved_result_read_profile() -> LocalCommandBusinessProfile {
  {
    kind: SavedResultRead,
    domain_bytes: 0L,
    payload_facility_bytes: 0L,
    limits: {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    },
  }
}

///|
fn LocalCommandPreparationOriginal::prepare_business_domain(
  self : LocalCommandPreparationOriginal,
  host : @initial_arena.InstalledArenaHost,
  scope : @initial_arena.InstalledArenaBackingBorrow,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.business is Some(business) else { return Ok(()) }
  if business.profile.kind == SavedResultRead {
    return if !self.closing &&
      !self.closed &&
      self.primary is None &&
      business.domain is None &&
      business.execution is None {
      Ok(())
    } else {
      Err(CommandUnavailable)
    }
  }
  guard business.selected_profile is Some(selected) else {
    return Err(CommandUnavailable)
  }
  if business.domain is Some(_) || self.closing || self.closed {
    return Err(CommandUnavailable)
  }
  let acquired = host
    .prepare_domain_in_process(scope, selected.domain_bytes, selected.limits)
    .map_err(issue => CommandDomain(issue))
  match acquired {
    Err(issue) => Err(issue)
    Ok(PendingDomain(domain, issue)) => {
      business.domain = Some(domain)
      Err(CommandDomain(issue))
    }
    Ok(PreparedDomain(domain)) => {
      business.domain = Some(domain)
      host.transfer_domain(domain).map_err(issue => CommandDomain(issue))
    }
  }
}

///|
fn LocalCommandPreparationOriginal::prepare_business_execution(
  self : LocalCommandPreparationOriginal,
  host : @initial_arena.InstalledArenaHost,
  input : @run_host.ClientSubmittedIntent,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.business is Some(business) else { return Ok(()) }
  if business.profile.kind == SavedResultRead {
    return if !self.closing &&
      !self.closed &&
      self.primary is None &&
      business.domain is None &&
      business.execution is None {
      Ok(())
    } else {
      Err(CommandUnavailable)
    }
  }
  guard business.selected_profile is Some(selected) &&
    business.domain is Some(domain) &&
    business.execution is None else {
    return Err(CommandUnavailable)
  }
  match
    host.prepare_domain_read(
      domain,
      // The physical ceiling counts the whole acquired page span, including
      // control and context pages. Task payload budgets remain in the Ledger.
      execution_ceiling=selected.domain_bytes,
    ) {
    Err(issue) => return Err(CommandDomain(issue))
    Ok(_) => ()
  }
  // Reuse the existing fixed bootstrap allowance on this actual child. It
  // is charged separately from the growing Request reservation, never slack.
  match
    host.prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: self.profile.read_budget.bootstrap_retained,
      bootstrap_execution: self.profile.read_budget.bootstrap_execution,
    }) {
    Err(issue) => Err(CommandRetainedExecution(issue))
    Ok(PendingRequestExecution(execution, issue)) => {
      business.execution = Some(execution)
      Err(CommandRetainedExecution(issue))
    }
    Ok(ReadyRequestExecution(execution, initial)) => {
      business.execution = Some(execution)
      business.request_initial = Some(initial)
      Ok(())
    }
  }
}

///|
fn LocalCommandPreparationOriginal::close_business_execution(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  native_timing_begin(28)
  defer native_timing_end(28)
  guard self.business is Some(business) else { return Ok(()) }
  guard self.host is Some(host) else {
    return if business.domain is None && business.execution is None {
      Ok(())
    } else {
      Err(CommandUnavailable)
    }
  }
  if (business.request_parent is Some(_) || business.request_run is Some(_)) &&
    !business.request_retiring {
    return Err(CommandBusinessChildren)
  }
  if business.execution is Some(execution) {
    if business.active {
      // The fixed Store coordinator may already have acknowledged this exact
      // business leave before a later Read/SQL switch failed. Observe its
      // actual original frame; a logical caller latch is not a second leave.
      let observed = match
        host.observe_domain_retained_execution_scope(execution) {
        Ok(scope) => Ok(scope)
        Err(_) =>
          host.observe_domain_retained_execution_cleanup_scope(execution)
      }
      match observed {
        Ok(@initial_bootstrap.BackedReadUnentered) => business.active = false
        Ok(@initial_bootstrap.BackedReadEntered) | Err(_) =>
          // A failed observation is not inactivity. Retain/retry only the
          // original scope this invocation already attempted to enter.
          match host.leave_domain_retained_execution(execution) {
            Err(issue) =>
              match
                host.finish_domain_retained_execution_failed_entry_cleanup(
                  execution,
                ) {
                Err(_) => return Err(CommandRetainedExecution(issue))
                Ok(_) => business.active = false
              }
            Ok(_) => business.active = false
          }
      }
    }
    match host.close_domain_retained_execution(execution) {
      Err(issue) => return Err(CommandRetainedExecution(issue))
      Ok(_) => business.execution = None
    }
  }
  if business.request_run is Some(run) {
    match @local_values.retire_installed_managed_run(run) {
      Err(_) => return Err(CommandBusinessChildren)
      Ok(_) => business.request_run = None
    }
  }
  if business.request_parent is Some(parent) {
    match @local_values.abort_request_preparation_after_cleanup(parent) {
      Err(_) => return Err(CommandBusinessChildren)
      Ok(_) => business.request_parent = None
    }
  }
  business.request_initial = None
  business.request_input = None
  if business.domain is Some(domain) {
    match host.close_domain_after_owner_ack(domain) {
      Err(issue) => return Err(CommandDomain(issue))
      Ok(_) => business.domain = None
    }
  }
  Ok(())
}

///|
// Compare the exact existing checked Program/registry inventory before epoch
// or Submission admission. Passing this comparison issues no actual resource
// or Account authority; the same retained-execution current fence is separate.
fn LocalCommandPreparationOriginal::require_business_program(
  self : LocalCommandPreparationOriginal,
  prepared : @run_host.PreparedClientProgram,
  installed_contracts : @local_values.ClientInstalledSequenceContracts,
  assets : @run_host.ClientLocalProductAssets,
  requirements : @local_values.ClientLocalRequirements,
) -> Result[@initial_resources.LedgerLimits, LocalCommandPreparationIssue] {
  if self.closing || self.closed || self.primary is Some(_) {
    return Err(CommandUnavailable)
  }
  guard self.host is Some(host) &&
    self.business is Some(business) &&
    business.profile.kind == SourceFreeCompute &&
    business.execution is Some(execution) else {
    return Err(CommandUnavailable)
  }
  if !requirements.matches(
      prepared,
      installed_contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ) {
    return Err(CommandUnavailable)
  }
  let needed = requirements.maximum_limits()
  let supplied = business.profile.limits
  if needed.planning_work > supplied.planning_work ||
    needed.attempts > supplied.attempts ||
    needed.holdings > supplied.holdings ||
    needed.transfer_bytes > supplied.transfer_bytes ||
    needed.retained_bytes > supplied.retained_bytes ||
    needed.execution_bytes > supplied.execution_bytes {
    return Err(CommandUnavailable)
  }
  host
  .require_domain_retained_execution_current(execution)
  .map_err(issue => CommandRetainedExecution(issue))
  .map(_ => needed)
}

///|
// Construct this outer-control receiver only after the original Journal and
// Runtime exist, before any Store/Work call or business entry. Activation is
// later, after the exact adopted Runtime binding and Program selection.
fn LocalCommandPreparationOriginal::prepare_business_operation(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.business is Some(business) else { return Ok(()) }
  guard self.host is Some(host) &&
    self.pair is Some(pair) &&
    self.journal is Some(capture) &&
    self.runtime is Some(runtime) &&
    business.operation is None &&
    !self.phase_open &&
    !self.closing &&
    !self.closed else {
    return Err(CommandUnavailable)
  }
  guard self.read is Some(read) &&
    host.observe_local_host_consuming_read_scope(pair, read)
    is Ok(@initial_arena.ReadUnentered) else {
    return Err(CommandUnavailable)
  }
  let library = match host.borrow_local_host_sqlite(pair) {
    Ok(value) => value
    Err(issue) => return Err(CommandPair(issue))
  }
  let prepared = match business.profile.kind {
    SourceFreeCompute => {
      guard business.execution is Some(execution) else {
        return Err(CommandUnavailable)
      }
      @local_host.prepare_native_local_store_operation(
        capture, execution, runtime, library,
      )
    }
    SavedResultRead => {
      if business.domain is Some(_) || business.execution is Some(_) {
        return Err(CommandUnavailable)
      }
      @local_host.prepare_native_local_run_observation_store_operation(
        capture, runtime, library,
      )
    }
  }
  let operation = match prepared {
    Ok(value) => value
    Err(issue) => return Err(CommandStoreOperation(issue))
  }
  business.operation = Some(operation)
  Ok(())
}

///|
// Metadata follows its actual child Store/DB and scope acknowledgements. A
// false pending observation alone cannot close a Database or Library; their
// existing original bridge refuses metadata retirement while they remain live.
fn LocalCommandPreparationOriginal::close_business_operation(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  native_timing_begin(29)
  defer native_timing_end(29)
  guard self.business is Some(business) else { return Ok(()) }
  if business.operation is Some(operation) {
    match operation.pending_scope() {
      Err(issue) => return Err(CommandStoreOperation(issue))
      Ok(true) =>
        match operation.retry_scope_cleanup() {
          Err(issue) => return Err(CommandStoreOperation(issue))
          Ok(_) => ()
        }
      Ok(false) => ()
    }
    match operation.close_checked() {
      Err(issue) => return Err(CommandStoreOperation(issue))
      Ok(_) => business.operation = None
    }
  }
  Ok(())
}
