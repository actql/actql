///|
fn select_retained_project_whole_file(
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  snapshot : @host.ClientSavedSubmissionSnapshot,
  authority_scope_cid : String,
) -> Result[
  (
    @host.ClientRequestIdentity,
    @local_host.ClientRequestWholeFileInput[@buffers.BufferSlot],
  ),
  Int,
] {
  if @local_host.reserve_request_program_plan(parent, slot) is Err(issue) {
    return Err(mock_project_request_issue(issue))
  }
  match
    @local_host.select_request_retained_whole_file(
      parent, slot, snapshot, authority_scope_cid,
    ) {
    Err(ForeignFileSubmission) => Err(-35)
    Err(UnsupportedFileRoute) => Err(-20)
    Err(RetainedFileIdentity(_)) => Err(-31)
    Err(RetainedFileSelection(FileSourceSelection(Preparation(issue))))
    | Err(RetainedFileSelection(FileWholeConstruction(Preparation(issue)))) =>
      Err(mock_project_request_issue(issue))
    Err(RetainedFileSelection(_)) => Err(-20)
    Ok(original) => Ok(original)
  }
}

///|
fn compile_retained_project_whole_file(
  value : Instance,
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  request : @host.ClientRequestIdentity,
  selected : @local_host.ClientRequestWholeFileInput[@buffers.BufferSlot],
  declaration : @row_host.RowDeclaration,
  input_limits : @row_host.RowInputLimits,
  transfer_bytes : Int64,
  provider_execution_bytes : Int64,
) -> Result[@local_host.ClientInstalledWholeSourceCapacity, Int] {
  let manifests = @host.packaged_client_compilation_manifests()
  let limits = match
    @local_host.request_program_compilation_limits(parent, slot) {
    Err(Preparation(issue)) => return Err(mock_project_request_issue(issue))
    Err(_) => return Err(-20)
    Ok(original) => original
  }
  let contracts = value.installed_sequences.contracts
  let provider_factory = _ => []
  match
    @local_host.prepare_request_program_compilation(
      parent,
      slot,
      contracts,
      manifests~,
      compilation_limits=limits,
      retained_output=false,
      provider_factory~,
    ) {
    Err(Preparation(issue)) => return Err(mock_project_request_issue(issue))
    Err(_) => return Err(-20)
    Ok(_) => ()
  }
  match
    @local_host.prepare_request_whole_file_module(
      parent,
      slot,
      request,
      selected,
      declaration,
      contracts,
      input_limits,
      None,
      transfer_bytes,
      provider_execution_bytes,
      manifests~,
      retained_output=false,
      provider_factory~,
    ) {
    Err(WholeFileCapacity(InsufficientCapacity))
    | Err(WholeFilePlan(InsufficientCapacity)) => Err(-4)
    Err(WholeFileCapacity(ForeignOriginal))
    | Err(WholeFilePlan(ForeignOriginal)) => Err(-2)
    Err(WholeFileCompilerLimits(Preparation(issue)))
    | Err(WholeFileModule(Preparation(issue))) =>
      Err(mock_project_request_issue(issue))
    Err(_) => Err(-20)
    Ok(capacity) => Ok(capacity)
  }
}

///|
fn select_paid_local_csv_source(
  checker : @host.ClientProjectLocalFileCheck,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  selected : @local_host.ClientRequestWholeFileInput[@buffers.BufferSlot],
) -> Result[(@host.ClientProjectLocalCsvSource, @row_host.RowInputLimits), Int] {
  let acquisition = @local_host.client_request_whole_file_source(selected)
  checker
  .prepare_csv_source(
    acquisition,
    account,
    principal,
    {
      max_file_bytes: 16777216L,
      max_page_bytes: 1048576,
      max_files: 1000L,
      max_page_rows: 256L,
    },
    demand => {
      @local_host.reserve_request_whole_file_provider_selection(
        parent, slot, selected, demand,
      ).map_err(issue => {
        match issue {
          Preparation(cause) => mock_project_request_issue(cause)
          _ => -20
        }
      })
    },
    issue => {
      match issue {
        ForeignOriginal => -2
        InvalidLimits => -4
        SourceUnavailable | ReadDenied => -20
      }
    },
  )
  .map(source => {
    let bound = source.transport.max_rows.to_int()
    (
      source,
      @local_host.installed_row_input_policy(
        bound,
        source.max_page_bytes,
        100000,
        32,
        bound,
      ),
    )
  })
}

///|
/// Select only a checked singleton Whole CSV. The original adopted Account,
/// current Project and submission stay on the same Request through compilation.
fn prepare_retained_local_csv_file(
  value : Instance,
  configuration : StoredRunConfiguration,
  check : StoredMockProjectCheck,
  held : StoredMockProjectRequest,
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  snapshot : @host.ClientSavedSubmissionSnapshot,
) -> Int {
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard check.local_file is Some(checker) &&
    configuration.local_project == Some(check.project) &&
    original_local_project_inputs(value, check.project) is Some(inputs) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.account is Some(account) else {
    return -2
  }
  let (request, selected) = match
    select_retained_project_whole_file(
      parent,
      slot,
      snapshot,
      configuration.authority_scope_cid,
    ) {
    Ok(original) => original
    Err(code) => return code
  }
  let (source, input_limits) = match
    select_paid_local_csv_source(
      checker,
      account,
      configuration.tuple.principal,
      parent,
      slot,
      selected,
    ) {
    Ok(original) => original
    Err(code) => return code
  }
  let quote = source.transport
  let capacity = match
    compile_retained_project_whole_file(
      value,
      parent,
      slot,
      request,
      selected,
      source.declaration(),
      input_limits,
      quote.transfer_bytes,
      quote.execution_bytes,
    ) {
    Ok(capacity) => capacity
    Err(code) => return code
  }
  let input = @local_host.installed_whole_source_acquisition(capacity)
  guard source.bind_input(input) is Ok(original) else { return -2 }
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard original_local_project_inputs(value, check.project) is Some(still) &&
    physical_equal(still, inputs) &&
    check.local_file is Some(active) &&
    physical_equal(active, checker) &&
    @local_host.inspect_request_whole_file_plan_original(parent, slot, (
      original,
      _,
      _,
    ) => physical_equal(original, request))
    is Some(true) else {
    return -2
  }
  held.whole_file_source = Some(LocalCsv(original))
  0
}
