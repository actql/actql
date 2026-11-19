///|
// Reverse physical children first, then their SAME Common RowRun parents.
// Already closed siblings remain retained until every pending child confirms.
fn close_managed_relation_file_sources(
  sources : Array[@row_file.NativeRelationFileCapture],
  reads : Array[@local.ClientInstalledSourceRead],
) -> Bool {
  for index = sources.length() - 1; index >= 0; index = index - 1 {
    if !(sources[index].close() is Ok(true)) {
      return false
    }
  }
  for index = reads.length() - 1; index >= 0; index = index - 1 {
    if !(@local.retire_installed_source_read(reads[index]) is Ok(_)) {
      return false
    }
  }
  true
}

///|
/// Execute the complete original finite Query prefix with one Work/claim and
/// one Common DAG. Each actual pending physical child remains cleanup-owned.
pub fn NativeLocalHostConnection::open_original_managed_relation_files_source_work(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  entry : NativeClientRelationFileWorkEntry,
  occurrence : String,
  quantum : Int,
  max_rounds : Int,
  current_time : () -> String,
) -> Result[NativeClientRelationFileWork, NativeClientRelationFileWorkFailure] {
  guard entry.access is Some(access) &&
    entry.payload is Some((prepared, compiled, definition)) else {
    return entry.unavailable
  }
  let (managed, count) = match access.source {
    ManagedRelationFiles(owner, inputs) => (owner, inputs.length())
    ManagedWholeRelationFiles(owner, inputs) => (owner, inputs.length())
    _ => return entry.unavailable
  }
  let ledger = match entry.take_entered_ledger(self, operation) {
    None => return entry.unavailable
    Some(value) => value
  }
  let execution = match operation.receiver.domain {
    StoreBusinessDomain(value) => value
    StoreRunObservationDomain => return entry.unavailable
  }
  let reads : Array[@local.ClientInstalledSourceRead] = []
  let sources : Array[@row_file.NativeRelationFileCapture] = []
  let pending : Ref[@row_file.NativeRelationFileFailure?] = Ref(None)
  let cleanup = () => {
    let ports_closed = match access.source {
      ManagedRelationFiles(_, _) =>
        @local.retire_installed_query_capture_ports(
          managed,
          prepared,
          access.base.request,
        )
      ManagedWholeRelationFiles(_, _) =>
        @local.retire_installed_whole_source_ports(
          managed,
          prepared,
          access.base.request,
        )
      _ => false
    }
    if !ports_closed {
      return false
    }
    if pending.val is Some(failure) {
      if !(failure.retry_cleanup() is Ok(true)) {
        return false
      }
      pending.val = None
    }
    close_managed_relation_file_sources(sources, reads)
  }
  let refuse = issue => {
    Err(
      relation_file_work_failure(
        issue,
        access=Some(access.base),
        entry=Some(entry),
        cleanup=Some(cleanup),
      ),
    )
  }
  let request = access.base.request
  if quantum <= 0 ||
    max_rounds <= 0 ||
    !entry.arena.owns_only_control() ||
    !managed_relation_file_originals_match(access.source, prepared, request) ||
    @strategy.graph_result_count(@host.prepared_client_graph(prepared)) != 1 ||
    @strategy.graph_program_has_effects(@host.prepared_client_graph(prepared)) ||
    @host.client_compiled_run_has_infers(compiled) {
    return refuse(Configuration)
  }
  if !access.current() {
    return refuse(
      OriginalOperation(access.base.primary.unwrap_or(AuthorizationDenied)),
    )
  }
  if !relation_file_prepared_binding_current(
      self.journal,
      request,
      prepared,
      compiled,
      definition,
    ) {
    return refuse(OriginalRunNotCurrent)
  }
  match
    self.journal.validate_prepared_run_binding(
      request, prepared, compiled, definition,
    ) {
    Err(issue) => return refuse(Journal(issue))
    Ok(_) => ()
  }
  match access.lookup() {
    Ok(Retained(record)) if @publication.publication_contract_identity(
        record.definition,
      ) ==
      @publication.publication_contract_identity(definition) &&
      !record.physical_start_claimed &&
      !record.cancellation_requested &&
      record.checkpoint is None => ()
    Ok(_) => return refuse(NeedsOriginalReconciliation)
    Err(issue) => return refuse(OriginalOperation(issue))
  }
  // These are original Plan reads, not physical transport starts. The SAME
  // managed Owner retains each read before its tuple crosses this boundary.
  for index in 0..<count {
    match access.source {
      ManagedRelationFiles(_, inputs) => {
        let input = inputs[index]
        let (read, _, acquisition, capacity) = match
          @local.begin_installed_managed_capture_source_read(
            managed,
            prepared,
            request,
            input.declaration,
            index,
          ) {
          Err(issue) => return refuse(InstalledRun(issue))
          Ok(value) => value
        }
        reads.push(read)
        if !physical_equal(acquisition, input.acquisition) ||
          !@local.installed_provider_row_capture_capacity_matches(
            capacity,
            acquisition,
            input.provider.capacity(),
          ) {
          return refuse(Configuration)
        }
      }
      ManagedWholeRelationFiles(_, inputs) => {
        let input = inputs[index]
        let (read, original, acquisition, capacity) = match
          @local.begin_installed_managed_whole_source_read_at(
            managed,
            prepared,
            request,
            input.declaration,
            index,
          ) {
          Err(issue) => return refuse(InstalledRun(issue))
          Ok(value) => value
        }
        reads.push(read)
        if !physical_equal(capacity, input.capacity) ||
          !physical_equal(
            original,
            @local.installed_whole_source_original(input.capacity),
          ) ||
          !@local.check_installed_whole_source_capacity(
            capacity,
            acquisition,
            input.provider.capacity(),
          ) {
          return refuse(Configuration)
        }
      }
      _ => return refuse(Configuration)
    }
  }
  let start = match access.claim() {
    Err(issue) => return refuse(OriginalOperation(issue))
    Ok(value) => value
  }
  match access.require_start_current(start) {
    Err(issue) => return refuse(OriginalOperation(issue))
    Ok(_) => ()
  }
  let started = current_time()
  match access.require_start_current(start) {
    Err(issue) => return refuse(OriginalOperation(issue))
    Ok(_) => ()
  }
  let captures : Array[@rows.RowSourceCapture] = []
  let captured_inputs : Array[@execution_query.CapturedInputSource] = []
  for index in 0..<count {
    match access.require_start_current(start) {
      Err(issue) => return refuse(OriginalOperation(issue))
      Ok(_) => ()
    }
    let outcome = match access.source {
      ManagedRelationFiles(_, inputs) => {
        let input = inputs[index]
        @row_file.prepare_native_managed_relation_file_query_capture(
          entry.original.host,
          execution,
          input.declaration,
          reads[index],
          input.acquisition,
          input.provider.capacity(),
          occurrence,
          input.selection,
          input.limits,
          prepared_provider=Some(input.provider),
        )
      }
      ManagedWholeRelationFiles(_, inputs) => {
        let input = inputs[index]
        @row_file.prepare_native_managed_relation_file_input_capture(
          entry.original.host,
          execution,
          input.declaration,
          reads[index],
          input.capacity,
          input.provider.capacity(),
          occurrence,
          input.selection,
          input.limits,
          prepared_provider=Some(input.provider),
        )
      }
      _ => return refuse(Configuration)
    }
    let source = match outcome {
      Err(failure) => {
        pending.val = Some(failure)
        return refuse(RelationFile(failure.issue()))
      }
      Ok(value) => value
    }
    sources.push(source)
    let mut complete = false
    for _ in 0..<max_rounds {
      match access.require_start_current(start) {
        Err(issue) => return refuse(OriginalOperation(issue))
        Ok(_) => ()
      }
      match source.advance(quantum) {
        Err(failure) => return refuse(RelationFile(failure.issue()))
        Ok(true) => {
          complete = true
          break
        }
        Ok(false) => ()
      }
    }
    if !complete {
      return refuse(Configuration)
    }
    let capture = match source.capture() {
      Err(issue) => return refuse(RelationFile(issue))
      Ok(value) => value
    }
    captures.push(capture)
    let original = match @rows.row_capture_source(capture) {
      Err(issue) => return refuse(CaptureIdentity(issue))
      Ok(value) => value
    }
    captured_inputs.push(original)
  }
  let source_usage = @resources.ledger_usage(ledger)
  let completed = current_time()
  match access.require_start_current(start) {
    Err(issue) => return refuse(OriginalOperation(issue))
    Ok(_) => ()
  }
  let (setup, _, _) = match
    @local.open_installed_managed_capture_host(
      managed, prepared, request, captured_inputs,
    ) {
    Err(issue) => return refuse(InstalledCapture(issue))
    Ok(value) => value
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  let computed = match
    (match access.source {
      ManagedRelationFiles(_, _) =>
        @local.execute_installed_captured_local_tasks_guarded(
          managed,
          prepared,
          request,
          setup,
          captures,
          quantum,
          max_rounds,
          () => access.require_start_current(start) is Ok(_),
          require_live=Some(() => access.poll_execution_original(start)),
        )
      ManagedWholeRelationFiles(_, _) =>
        @local.execute_installed_whole_source_values_guarded(
          managed,
          prepared,
          request,
          setup,
          quantum,
          max_rounds,
          () => access.require_start_current(start) is Ok(_),
        )
      _ => return refuse(Configuration)
    }) {
    Err(failure) =>
      return Err(
        relation_file_work_failure(
          match access.base.primary {
            Some(issue) => OriginalOperation(issue)
            None =>
              LocalExecution(
                @local.local_values_execution_failure_issue(failure),
              )
          },
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(() => {
            @local.retry_local_values_execution_failure_cleanup(failure) &&
            cleanup()
          }),
        ),
      )
    Ok(value) => value
  }
  // A post-compute projection cannot lose the dependent execution's custody.
  // The immutable geometry is bound to the same managed preparation below.
  let geometry = @local.installed_managed_capture_publication_geometry_original(
    managed, prepared, request,
  )
  guard geometry is Some((_, rows, entries, evidence_entries)) else {
    return Err(
      relation_file_work_failure(
        Configuration,
        access=Some(access.base),
        entry=Some(entry),
        cleanup=Some(() => computed.close() && cleanup()),
      ),
    )
  }
  let owner : NativeClientRelationFileWork = {
    access,
    start,
    prepared,
    compiled,
    definition,
    source: Managed(sources, reads),
    run,
    source_usage,
    execution: computed,
    plan: ManagedSourceFileExecution(rows, entries, evidence_entries),
    entry,
    output_bridge: None,
    capture_times: Some((started, completed)),
    publication_original: None,
    publication: None,
    identity_scan: None,
    publication_basis: None,
    publication_growing: false,
    publication_identity_issue: None,
    stopping: false,
  }
  match owner.require_current() {
    Err(issue) =>
      Err(
        relation_file_work_failure(
          issue,
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(() => owner.close()),
        ),
      )
    Ok(_) => Ok(owner)
  }
}
