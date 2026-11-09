///|
// Acquire the existing conservative installed facility BEFORE semantic
// preparation, and before the first durable Submission or Run action. The declared Host maximum is not initialized
// execution capacity. Every partial acquisition remains on this same carrier.
fn LocalCommandPreparationOriginal::prepare_business_request_capacity(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  input : LocalCommandBusinessInput,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.host is Some(host) &&
    self.journal is Some(journal) &&
    physical_equal(journal, capture) &&
    self.journal_read_open &&
    self.business is Some(business) &&
    business.profile.kind == SourceFreeCompute &&
    business.selected_profile is None &&
    business.domain is None &&
    business.execution is None &&
    business.operation is None &&
    self.backing_scope is None &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    return Err(CommandUnavailable)
  }
  let maximum = business.profile.limits
  // This is the pre-existing installer ceiling, not inferred Program demand.
  // The SAME Request reservation grows within it before each constructor.
  let selected = maximum
  business.request_input = Some(input)
  if selected.retained_bytes > 9223372036854775807L - selected.execution_bytes {
    return Err(CommandUnavailable)
  }
  // The existing shared Owner quotes its complete fixed Request entrance.
  // The already selected Native control block covers first Reader/callback
  // bookkeeping; it is a physical prefix, not another logical reservation.
  guard @local_values.client_request_preparation_control_capacity(
      @local_values.client_local_resource_policy(),
    )
    is Some((control_retained, control_execution)) &&
    native_storage_sum([control_retained, control_execution]) is Ok(control) &&
    native_storage_sum([
      self.profile.read_budget.bootstrap_retained,
      self.profile.read_budget.bootstrap_execution,
    ])
    is Ok(prefix) &&
    prefix >= control &&
    prefix > 0L &&
    prefix <= business.profile.payload_facility_bytes &&
    local_command_domain_bytes(prefix) is Some(bytes) &&
    bytes <= business.profile.domain_bytes else {
    return Err(CommandUnavailable)
  }
  // Preserve the same immutable MAX selection. Record actual initial backing
  // separately BEFORE any physical attempt; partial failure retains both.
  business.selected_profile = Some(business.profile)
  business.initial_window_bytes = Some(prefix)
  business.initial_domain_bytes = Some(bytes)
  native_timing_amount(53, maximum.retained_bytes)
  native_timing_amount(54, maximum.execution_bytes)
  native_timing_amount(55, selected.retained_bytes)
  native_timing_amount(56, selected.execution_bytes)
  native_timing_amount(57, bytes)
  match capture.suspend_original_read_for_preparation() {
    Err(issue) => return Err(CommandAdoption(issue))
    Ok(_) => ()
  }
  let acquired = try {
    let scope = command_preparation_value(
      host.borrow_backing().map_err(issue => CommandHost(issue)),
    )
    self.backing_scope = Some(scope)
    command_preparation_value(
      host
      .enter_backing_borrow_scope(scope)
      .map_err(issue => CommandHost(issue)),
    )
    self.backing_entered = true
    let before = self.observe_extent_work(host, scope)
    let acquired = self.prepare_business_domain(host, scope)
    record_command_extent_work(
      before,
      self.observe_extent_work(host, scope),
      46,
    )
    command_preparation_value(acquired)
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => Err(issue)
  }
  // This only returns our original backing borrow; it never retries domain or
  // execution construction. Keep the acquisition error primary if cleanup or
  // restoring the original Read also fails.
  let returned = self.finish_business_backing_scope(host)
  let prepared = match (acquired, returned) {
    (Ok(_), Ok(_)) =>
      try {
        command_preparation_value(self.prepare_business_execution(host, input))
        // The fixed static caller has no Store/Run operation child. Its SAME
        // Request reservation funds parsing, checking and metadata only.
        if input.operation != "check" {
          command_preparation_value(self.prepare_business_operation())
        }
        Ok(())
      } catch {
        LocalCommandPreparationStop(issue) => Err(issue)
      }
    (Err(issue), _) | (_, Err(issue)) => Err(issue)
  }
  let resumed = capture
    .resume_original_read_after_preparation()
    .map_err(issue => CommandAdoption(issue))
  match prepared {
    Err(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
    Ok(_) => resumed
  }
}

///|
fn LocalCommandPreparationOriginal::finish_business_backing_scope(
  self : LocalCommandPreparationOriginal,
  host : @initial_arena.InstalledArenaHost,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.backing_scope is Some(scope) else { return Ok(()) }
  if self.backing_entered {
    match host.leave_backing_borrow_scope(scope) {
      Err(issue) => return Err(CommandHost(issue))
      Ok(_) => self.backing_entered = false
    }
  }
  match host.return_backing_borrow(scope) {
    Err(issue) => Err(CommandHost(issue))
    Ok(_) => {
      self.backing_scope = None
      Ok(())
    }
  }
}

///|
// Retained-run presentation selects the existing Read/SQLite routing only.
// The parsed Compute candidate is not an acquired execution or authority. No
// domain, work Ledger, payload capacity or preparation grant is constructed.
fn LocalCommandPreparationOriginal::prepare_saved_result_operation(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.host is Some(host) &&
    self.pair is Some(pair) &&
    self.journal is Some(actual) &&
    physical_equal(actual, capture) &&
    self.runtime is Some(runtime) &&
    self.journal_read_open &&
    self.business is Some(business) &&
    business.selected_profile is None &&
    business.domain is None &&
    business.execution is None &&
    business.operation is None &&
    self.backing_scope is None &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    return Err(CommandUnavailable)
  }
  let library = match host.borrow_local_host_sqlite(pair) {
    Ok(value) => value
    Err(issue) => return Err(CommandPair(issue))
  }
  match capture.suspend_original_read_for_preparation() {
    Err(issue) => return Err(CommandAdoption(issue))
    Ok(_) => ()
  }
  let prepared = match
    @local_host.prepare_native_local_run_observation_store_operation(
      capture, runtime, library,
    ) {
    Ok(operation) => {
      // Retain before the fallible original Read return. The existing child-
      // first business cleanup retires this same routing, Store and failures.
      business.operation = Some(operation)
      Ok(())
    }
    Err(issue) => Err(CommandStoreOperation(issue))
  }
  let resumed = capture
    .resume_original_read_after_preparation()
    .map_err(issue => CommandAdoption(issue))
  match prepared {
    Err(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
    Ok(_) => resumed
  }
}

///|
// Actual Saved constructor demand, never a fresh input/Request allowance.
// Retain each selected amount and partial domain before the next fallible
// acquisition; the SAME Host Read is returned on both success and failure.
fn LocalCommandPreparationOriginal::prepare_saved_effect_capacity(
  self : Self,
  capture : @local_host.NativeLocalJournalCapture,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.host is Some(host) &&
    self.journal is Some(actual) &&
    physical_equal(actual, capture) &&
    self.journal_read_open &&
    self.run_observation is Some(observation) &&
    observation.effect_resume is Some(_) &&
    self.business is Some(business) &&
    business.profile.kind == SavedEffectApply &&
    self.saved_observation_business_disjoint() &&
    business.selected_profile is None &&
    business.domain is None &&
    business.execution is None &&
    business.operation is None &&
    self.backing_scope is None &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    return Err(CommandUnavailable)
  }
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity)
  let limits = business.profile.limits
  guard retained > 0L &&
    execution > 0L &&
    retained <= limits.retained_bytes &&
    execution <= limits.execution_bytes &&
    native_storage_sum([retained, execution]) is Ok(payload) &&
    payload <= business.profile.payload_facility_bytes &&
    local_command_domain_bytes(payload) is Some(bytes) &&
    bytes <= business.profile.domain_bytes else {
    return Err(CommandUnavailable)
  }
  business.selected_profile = Some(business.profile)
  business.initial_window_bytes = Some(payload)
  business.initial_domain_bytes = Some(bytes)
  match capture.suspend_original_read_for_preparation() {
    Err(issue) => return Err(CommandAdoption(issue))
    Ok(_) => ()
  }
  let acquired = try {
    let scope = command_preparation_value(
      host.borrow_backing().map_err(issue => CommandHost(issue)),
    )
    self.backing_scope = Some(scope)
    command_preparation_value(
      host
      .enter_backing_borrow_scope(scope)
      .map_err(issue => CommandHost(issue)),
    )
    self.backing_entered = true
    command_preparation_value(self.prepare_business_domain(host, scope))
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => Err(issue)
  }
  let returned = self.finish_business_backing_scope(host)
  let prepared = match (acquired, returned) {
    (Ok(_), Ok(_)) =>
      try {
        command_preparation_value(self.prepare_saved_effect_execution(host))
        command_preparation_value(self.prepare_business_operation())
        Ok(())
      } catch {
        LocalCommandPreparationStop(issue) => Err(issue)
      }
    (Err(issue), _) | (_, Err(issue)) => Err(issue)
  }
  let resumed = capture
    .resume_original_read_after_preparation()
    .map_err(issue => CommandAdoption(issue))
  match prepared {
    Err(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
    Ok(_) => resumed
  }
}

///|
// The existing original retained execution, without issuing a new Request
// preparation, input producer, Run admission or Model/Source computation.
fn LocalCommandPreparationOriginal::prepare_saved_effect_execution(
  self : Self,
  host : @initial_arena.InstalledArenaHost,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.business is Some(business) &&
    business.profile.kind == SavedEffectApply &&
    business.selected_profile is Some(selected) &&
    business.domain is Some(domain) &&
    business.execution is None &&
    business.request_initial is None &&
    business.request_parent is None else {
    return Err(CommandUnavailable)
  }
  match
    host.prepare_domain_read(domain, execution_ceiling=selected.domain_bytes) {
    Err(issue) => return Err(CommandDomain(issue))
    Ok(_) => ()
  }
  match host.prepare_domain_retained_execution(domain) {
    Err(issue) => Err(CommandRetainedExecution(issue))
    Ok(PendingRetainedExecution(execution, issue)) => {
      business.execution = Some(execution)
      Err(CommandRetainedExecution(issue))
    }
    Ok(ReadyRetainedExecution(execution)) => {
      business.execution = Some(execution)
      Ok(())
    }
  }
}
