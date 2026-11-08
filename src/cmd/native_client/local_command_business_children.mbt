///|
// Reenter only the same retained execution to retire its original children.
fn LocalCommandBusinessOriginal::enter_children_cleanup(
  business : LocalCommandBusinessOriginal,
  host : @initial_arena.InstalledArenaHost,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard business.execution is Some(execution) else {
    return Err(CommandBusinessChildren)
  }
  let observed = match host.observe_domain_retained_execution_scope(execution) {
    Ok(value) => Ok(value)
    Err(_) => host.observe_domain_retained_execution_cleanup_scope(execution)
  }
  let scope = match observed {
    Ok(value) => value
    Err(primary) => {
      // A failed original entry can retain nominal active while no child C
      // frame was installed. Only its existing physical non-entry/unwind port
      // may reconcile that state; an error alone never clears this duty.
      match
        host.finish_domain_retained_execution_failed_entry_cleanup(execution) {
        Err(_) => return Err(CommandRetainedExecution(primary))
        Ok(_) => business.active = false
      }
      match host.observe_domain_retained_execution_cleanup_scope(execution) {
        Err(issue) => return Err(CommandRetainedExecution(issue))
        Ok(value) => value
      }
    }
  }
  match scope {
    @initial_bootstrap.BackedReadEntered => business.active = true
    @initial_bootstrap.BackedReadUnentered => {
      // Retain the original attempted entry even if its acknowledgement is
      // lost. Cleanup entry monotonically retires normal business access.
      business.active = true
      match host.enter_domain_retained_execution_cleanup(execution) {
        Err(issue) => return Err(CommandRetainedExecution(issue))
        Ok(_) => ()
      }
    }
  }
  Ok(())
}

///|
// Retain the exact constructor outcome before reporting an application error.
// Scope return or presentation failure cannot discard an acquired Work or a
// partially initialized occurrence. The parent retires these before Store.
fn LocalCommandBusinessPreparation::open_values_work(
  self : LocalCommandBusinessPreparation,
  run : LocalRunInstallation,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @run_host.ClientRequestIdentity,
) -> @local_host.NativeClientValuesWork raise ClientStop {
  guard self.original.business is Some(business) &&
    business.operation is Some(operation) &&
    business.values_work is None &&
    business.values_failure is None &&
    !self.original.closing &&
    !self.original.closed else {
    stop("LocalBusinessOriginalUnavailable")
  }
  guard @local_host.native_client_submitted_preparation(self.preparation)
    is Computation(prepared) &&
    self.requirements is Some(requirements) else {
    stop("LocalValuesExecutionProfileNotSupported")
  }
  let installed = run.source_free.unwrap_or_else(() => {
    stop("LocalValuesInstallationRequired")
  })
  let finalization_rounds = requirements
    .finalization_round_limit(prepared)
    .unwrap_or_else(() => stop("LocalValuesExecutionProfileNotSupported"))
  match
    self.host.open_original_values_work(
      operation,
      self.principal,
      self.connection,
      request,
      prepared,
      compiled,
      definition,
      self.installed_contracts,
      installed.values_body,
      installed.fragment_body,
      installed.ordered_body,
      16,
      finalization_rounds,
      requirements=Some(requirements),
      managed=business.request_run,
    ) {
    Ok(work) => {
      business.values_work = Some(work)
      work
    }
    Err(failure) => {
      local_values_failure_tags(
        @local_host.native_client_values_work_failure_issue(failure),
        native_timing_amount,
      )
      business.values_failure = Some(failure)
      stop("LocalOriginalValuesWorkUnavailable")
    }
  }
}

///|
// The fixed coordinator and the original Library select the existing Store
// constructor. Neither failure nor missing original falls back to open_store.
fn LocalCommandBusinessPreparation::open_store(
  self : LocalCommandBusinessPreparation,
  library : @local_sqlite.Library,
  managed : String,
  run : LocalRunInstallation,
) -> @local_store.Store raise ClientStop {
  self.original.open_business_store(library, managed, run)
}

///|
fn LocalCommandPreparationOriginal::open_business_store(
  self : LocalCommandPreparationOriginal,
  library : @local_sqlite.Library,
  managed : String,
  run : LocalRunInstallation,
  existing? : Bool = false,
) -> @local_store.Store raise ClientStop {
  guard self.business is Some(business) &&
    business.operation is Some(operation) &&
    business.store is None &&
    business.store_failure is None &&
    business.store_parent is None &&
    business.store_parent_failure is None &&
    business.store_root is None &&
    business.store_root_failure is None &&
    business.store_root_operation is None &&
    !self.closing &&
    !self.closed else {
    stop("LocalBusinessOriginalUnavailable")
  }
  let original = operation
    .sqlite_original()
    .unwrap_or_else(() => stop("LocalBusinessOriginalUnavailable"))
  business.store_root_operation = Some(original)
  let path = self.prepare_business_store_path(
    managed,
    run.store_name,
    existing~,
  )
  match
    @local_store.open_original_local_store_with_custody(
      library,
      original,
      path,
      run.store_authority_cid,
      run.store_capacity_bytes,
      run.store_objects,
      run.store_record_bytes,
      existing~,
      diagnostic_ceiling=Some(self.profile.diagnostic_ceiling),
    ) {
    Ok(store) => {
      business.store = Some(store)
      store
    }
    Err(CleanupRequired(failure)) => {
      business.store_failure = Some(failure)
      stop("LocalResultStoreCleanupPending")
    }
    Err(RefusedBeforeAcquisition(_)) => stop("LocalResultStoreUnavailable")
  }
}

///|
// Run only after the original borrowed command callback has returned. Compute
// cleanup uses its actual execution frame; Store cleanup uses its own original
// Read/SQL route. Their acknowledgements never substitute for each other.
fn LocalCommandPreparationOriginal::close_business_children(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  native_timing_begin(17)
  defer native_timing_end(17)
  guard self.business is Some(business) else { return Ok(()) }
  if self.journal_read_open || self.phase_open {
    return Err(CommandBusinessChildren)
  }
  match business.close_result_children_after_return() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match business.close_publication_children() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !business.model_work.is_empty() || business.effect_model is Some(_) {
    guard self.host is Some(host) && business.execution is Some(execution) else {
      return Err(CommandBusinessChildren)
    }
    match business.enter_children_cleanup(host) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if business.effect_model is Some(state) {
      for target in state.targets {
        match target.close() {
          Err(issue) => return Err(issue)
          Ok(false) => return Err(CommandBusinessChildren)
          Ok(true) => ()
        }
      }
      state.targets.clear()
      state.targets.shrink_to_fit()
      // Sever this caller's output alias before the original Model releases it.
      // This is no physical ACK and does not clear any child obligation.
      if state.proposals is Some(proposals) {
        if !proposals.close() {
          return Err(CommandBusinessChildren)
        }
        state.proposals = None
      }
      if business.request_run is Some(run) {
        match @local_values.retire_installed_effect_captured_consumers(run) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(false) => return Err(CommandBusinessChildren)
          Ok(true) => ()
        }
      }
      state.effect_host = None
      state.effect_capture = None
      state.model_output = None
      // The observation issuer owns its original publication backing. Cut
      // this caller alias before Work retires that issuer and its reservation.
      state._retained_model_observation = None
      state._retained_local_model_observation = None
      state._retained_local_model_dependencies = None
      if state.model_use is Some(held) {
        @infer.release_output(held) |> ignore
        state.model_use = None
      }
    }
    for work in business.model_work {
      match work.close() {
        Err(issue) => return Err(CommandBusinessModel(issue))
        Ok(false) => return Err(CommandBusinessChildren)
        Ok(true) => ()
      }
    }
    // Only actual child acknowledgements sever these references. Unknown or
    // partial Model/Store/Journal duties keep the same originals for cleanup.
    business.model_work.clear()
    if business.effect_model is Some(state) {
      if state.source_identity_scan is Some(scan) {
        if !@query.cancel_captured_source_cell_identity(scan) {
          return Err(CommandBusinessChildren)
        }
        state.source_identity_scan = None
      }
      // Work/Store consumers above have retired. Cut the actual Source body
      // aliases before returning the SAME Read allocation below.
      for identity in state.source_identities {
        @query.clear_captured_source_relation_dependency_bodies(identity)
      }
      state.source_identities.clear()
      state.source_identities.shrink_to_fit()
      for failure in state.source_failures {
        match failure.retry_cleanup() {
          Err(issue) => return Err(CommandBusinessSource(issue))
          Ok(false) => return Err(CommandBusinessChildren)
          Ok(true) => ()
        }
      }
      state.source_failures.clear()
      state.source_failures.shrink_to_fit()
      // Stop new assembly work without returning its backing. Raw envelopes
      // borrowed by Source/Store children remain funded by this SAME lookup
      // until those original physical children have retired and cut aliases.
      if state.lookup is Some(lookup) {
        @run_host.stop_client_keyed_lookup_input(lookup)
      }
      for source in state.sources {
        match source.close() {
          Err(issue) => return Err(CommandBusinessSource(issue))
          Ok(false) => return Err(CommandBusinessChildren)
          Ok(true) => ()
        }
      }
      if state.lookup is Some(lookup) {
        match @run_host.cleanup_client_keyed_lookup_input(lookup, 31) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(false) => return Err(CommandBusinessChildren)
          Ok(true) => state.lookup = None
        }
      }
      if state.prefix is Some(prefix) {
        let original = @local_values.client_original_composed_keyed_prefix_execution(
          prefix,
        )
        @local_values.cancel_client_serialization_prefix(original) |> ignore
        match @local_values.cleanup_client_serialization_prefix(original) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(false) => return Err(CommandBusinessChildren)
          Ok(true) => state.prefix = None
        }
      }
      for read in state.source_reads {
        match @local_values.retire_installed_source_read(read) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(_) => ()
        }
      }
      for read in state.keyed_reads {
        match @local_values.retire_installed_keyed_source_read(read) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(_) => ()
        }
      }
      state.keyed_reads.clear()
      state.keyed_reads.shrink_to_fit()
      state.model_output = None
      if state.model_read is Some(read) {
        match
          @run_host.stop_client_model_read_checked(
            state.scope.unwrap(),
            read,
            state.first.model_compiled.unwrap(),
            state.first.definition,
            state.graph,
          ) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(_) => ()
        }
        match
          @run_host.settle_client_model_read_checked(
            read,
            state.first.model_compiled.unwrap(),
            state.first.definition,
            state.graph,
            true,
          ) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(_) => state.model_read = None
        }
      }
      state.source_reads.clear()
      state.source_reads.shrink_to_fit()
      if business.request_run is Some(run) {
        match @local_values.quiesce_installed_managed_run(run) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(_) => ()
        }
      }
      state.sources.clear()
      state.sources.shrink_to_fit()
      state.captured_inputs.clear()
      state.captured_inputs.shrink_to_fit()
      state.input_originals.clear()
      state.input_originals.shrink_to_fit()
      if state.scope is Some(scope) {
        match
          @run_host.finish_client_model_read_scope(
            scope,
            state.first.model_compiled.unwrap(),
            state.first.definition,
            state.graph,
            true,
          ) {
          Err(_) => return Err(CommandBusinessChildren)
          Ok(false) => return Err(CommandBusinessChildren)
          Ok(true) => state.scope = None
        }
      }
      business.effect_model = None
    }
    match host.leave_domain_retained_execution(execution) {
      Err(issue) => return Err(CommandRetainedExecution(issue))
      Ok(_) => business.active = false
    }
  }
  if business.values_work is Some(_) || business.values_failure is Some(_) {
    guard self.host is Some(host) &&
      business.execution is Some(execution) &&
      business.operation is Some(_) &&
      !self.journal_read_open &&
      !self.phase_open else {
      return Err(CommandBusinessChildren)
    }
    match business.enter_children_cleanup(host) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if business.values_work is Some(work) {
      if !work.close() {
        return Err(CommandBusinessChildren)
      }
      business.values_work = None
    }
    if business.values_failure is Some(failure) {
      if !failure.close() {
        return Err(CommandBusinessChildren)
      }
      business.values_failure = None
    }
    if !self.business_inventory_recorded && business.domain is Some(domain) {
      self.business_inventory_recorded = self.record_domain_inventory(
        host, domain, 14,
      )
    }
    match host.leave_domain_retained_execution(execution) {
      Err(issue) => return Err(CommandRetainedExecution(issue))
      Ok(_) => business.active = false
    }
  }
  if business.request_parent is Some(_) ||
    business.request_run is Some(_) ||
    business.request_body is Some(_) {
    guard self.host is Some(host) && business.execution is Some(execution) else {
      return Err(CommandBusinessChildren)
    }
    match business.enter_children_cleanup(host) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if business.request_read_failure is Some(failure) {
      match failure.retry_cleanup() {
        Err(_) => return Err(CommandBusinessChildren)
        Ok(_) => business.request_read_failure = None
      }
    }
    if business.request_body is Some(holder) {
      match @local_host.return_native_client_submitted_request_body(holder) {
        Err(_) => return Err(CommandBusinessChildren)
        Ok(_) => business.request_body = None
      }
    }
    // Logical cleanup intentionally stays pending until this SAME Native
    // initializer has observed its separate physical retirement and report.
    // The Native close below still refuses any outstanding live reservation.
    if business.request_run is Some(run) {
      ignore(@local_values.retire_installed_managed_run(run))
    } else if business.request_parent is Some(parent) {
      ignore(@local_values.abort_request_preparation_after_cleanup(parent))
    }
    business.request_retiring = true
    match host.leave_domain_retained_execution(execution) {
      Err(issue) => return Err(CommandRetainedExecution(issue))
      Ok(_) => business.active = false
    }
  }
  // A retained failed-open owner includes its own DB alias until the actual
  // return ACK. A successful physical child close alone cannot clear it here.
  if business.store_failure is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(CommandBusinessStore(issue))
      Ok(_) => business.store_failure = None
    }
  }
  if business.store is Some(store) {
    match store.close() {
      Err(issue) => return Err(CommandBusinessStore(issue))
      Ok(_) => business.store = None
    }
  }
  self.close_business_store_roots()
}
