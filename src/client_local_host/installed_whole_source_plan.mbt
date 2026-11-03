///|
/// A typed alternative in the existing Source/Compute Plan. It retains one
/// complete original input and its selected provider recipe, never a Query
/// requirement, a second Run or caller-supplied capacity scalars.
struct ClientInstalledWholeSourceCapacity {
  original : @sourceviews.SourceAcquisition
  acquisition : @row_source_host.RowInputAcquisition
  provider : @execution.ExecutionCapacity
  complete : @execution.ExecutionCapacity
}

///|
/// Pre-Plan selection from this exact Prepared/Request invocation. The closed
/// choice retains its actual Query or Source original; reference getters are DATA.
/// Query construction errors cannot select the whole-input constructor.
pub fn select_installed_source_input(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  stage : Int,
  source_index : Int,
) -> Result[@sourceviews.SourceAcquisitionRoute, ClientInstalledManagedRunIssue] {
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  if stage == 0 &&
    source_index == 0 &&
    @strategy.graph_captured_prefix(graph) == 1 &&
    installed_managed_run_purpose_supported(prepared) &&
    @strategy.graph_requires_acquisition_result_publication(graph) {
    // A checked root in the captured prefix needs its original computation
    // and publication identity. Select complete input before Query lowering;
    // this is not fallback from a failed Query or a caller purpose flag.
    guard @context.program_identity_stage_requests(
        @checked.source_identity(@strategy.graph_program(graph)),
        stage,
      )
      is Some(requests) else {
      return Err(SourceAcquisition(@publication_host.MissingRequests))
    }
    return @sourceviews.derive_source_acquisition(
        requests, source_index, 1000000,
      )
      .map(original => @sourceviews.WholeInputRoute(original))
      .map_err(issue => SourceRoute(@sourceviews.SourceInput(issue)))
  }
  select_installed_source_input_graph(graph, stage, source_index)
}

///|
/// The same immutable selection for an Effect's checked captured prefix.
/// This projects Requests only; the retained Plan constructs its acquisition.
pub fn select_installed_effect_source_input(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  stage : Int,
  source_index : Int,
) -> Result[@sourceviews.SourceAcquisitionRoute, ClientInstalledManagedRunIssue] {
  if !installed_effect_managed_request_matches(prepared, request) {
    return Err(ForeignOriginal)
  }
  select_installed_source_input_graph(
    installed_managed_owner_graph(Effect(prepared)),
    stage,
    source_index,
  )
}

///|
fn select_installed_source_input_graph(
  graph : @strategy.CheckedDAG,
  stage : Int,
  source_index : Int,
) -> Result[@sourceviews.SourceAcquisitionRoute, ClientInstalledManagedRunIssue] {
  guard @context.program_identity_stage_requests(
      @checked.source_identity(@strategy.graph_program(graph)),
      stage,
    )
    is Some(requests) else {
    return Err(SourceAcquisition(@publication_host.MissingRequests))
  }
  @sourceviews.select_source_acquisition_route(requests, source_index, 1000000).map_err(issue => {
      SourceRoute(issue)
    },
  )
}

///|
/// Derive this actual input inside the Request's already admitted Plan phase.
/// The same installed contracts and bound sequence are consumed, not emitted
/// and readmitted. Source declaration lifetime stays with initial material.
pub fn prepare_installed_whole_source_capacity(
  prepared : @publication_host.PreparedClientProgram,
  original : @sourceviews.SourceAcquisition,
  declaration : @row_source_host.RowDeclaration,
  contracts : ClientInstalledSequenceContracts,
  limits : @row_source_host.RowInputLimits,
  provider : @execution.ExecutionCapacity?,
) -> Result[ClientInstalledWholeSourceCapacity, ClientInstalledManagedRunIssue] {
  if !@publication_host.client_source_acquisition_matches_program(
      prepared, 0, 0, original,
    ) {
    return Err(ForeignOriginal)
  }
  // The same nominal Source original already attests a bounded snapshot and
  // bound request. Its correspondence above selects THIS complete sequence;
  // inspecting the narrower Query grammar again would discard root placement
  // and reject the complete-input choice made from the checked Result graph.
  let sequence = match
    @publication_host.prepare_prepared_client_full_sequence(
      prepared,
      0,
      @publication_host.prepared_client_values_sequence_limits(prepared),
    ) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  let acquisition = match
    @row_source_host.prepare_row_input_acquisition(
      original,
      @checked.source_identity(
        @strategy.graph_program(
          @publication_host.prepared_client_graph(prepared),
        ),
      ),
      sequence,
      contracts.original.value.contracts,
      declaration,
      limits,
    ) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  match
    installed_whole_source_capture_capacity(original, acquisition, provider) {
    Some(value) => Ok(value)
    None => Err(Unsupported)
  }
}

///|
pub fn installed_whole_source_original(
  value : ClientInstalledWholeSourceCapacity,
) -> @sourceviews.SourceAcquisition {
  value.original
}

///|
pub fn installed_whole_source_acquisition(
  value : ClientInstalledWholeSourceCapacity,
) -> @row_source_host.RowInputAcquisition {
  value.acquisition
}

///|
/// Read immutable correspondence without callbacks or a new resource claim.
pub fn check_installed_whole_source_capacity(
  value : ClientInstalledWholeSourceCapacity,
  acquisition : @row_source_host.RowInputAcquisition,
  provider : @execution.ExecutionCapacity,
) -> Bool {
  physical_equal(value.acquisition, acquisition) &&
  physical_equal(value.provider, provider)
}

///|
/// Closed immutable variant selection, not current authority or capacity.
pub fn installed_managed_source_input_kind(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[String, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.ledger is Some(_) &&
    physical_equal(owner.request, request) else {
    return Err(ForeignOriginal)
  }
  if owner.preparation is Some(PreparationContentManaged(_, actual)) {
    // The same adopted keyed Plan retains a Direct Row acquisition, whose
    // original requirement is a Query. This is the closed variant selected by
    // the existing Content read handoff, not a new query/current/grant/quote.
    guard physical_equal(actual, prepared) &&
      owner.content is KeyedContent(selected, _) &&
      physical_equal(selected.prepared, prepared) &&
      selected.direct.original_input &&
      selected.direct.provider is None &&
      selected.direct.acquisition is Some(_) else {
      return Err(ForeignOriginal)
    }
    return Ok("query")
  }
  guard owner.preparation is Some(PureManaged(_, actual)) &&
    physical_equal(actual, prepared) &&
    owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) else {
    return Err(ForeignOriginal)
  }
  Ok(if plan.whole_input is Some(_) { "whole-input" } else { "query" })
}

///|
/// Result placement belongs to this exact adopted Plan's physical graph.
/// This is immutable DATA; it does not authorize execution or check current.
pub fn installed_managed_acquisition_result_publication(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    value.ledger is Some(_) &&
    value.preparation is Some(PureManaged(_, actual)) &&
    physical_equal(actual, prepared) &&
    physical_equal(value.request, request) else {
    return Err(ForeignOriginal)
  }
  let graph = if value.captured_preparation is Some(plan) {
    guard physical_equal(plan.prepared, prepared) &&
      physical_equal(plan.request, request) else {
      return Err(ForeignOriginal)
    }
    plan.graph
  } else {
    guard value.source_free_preparation is Some(plan) &&
      plan.owner is Pure(original) &&
      physical_equal(original, prepared) else {
      return Err(ForeignOriginal)
    }
    installed_managed_owner_graph(plan.owner)
  }
  Ok(@strategy.graph_requires_acquisition_result_publication(graph))
}

///|
/// Reuse the existing admitted Run Ledger for its exact complete-input Plan.
/// No Query-capacity array, new limits, reservation or Ledger is constructed.
pub fn installed_managed_whole_source_ledger(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  capacity : ClientInstalledWholeSourceCapacity,
  transfer : Int64,
  scratch : Int64,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  match check_installed_managed_run_binding(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard value.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    plan.whole_input is Some(selected) &&
    physical_equal(selected, capacity) &&
    plan.transport_bytes.length() == 1 &&
    plan.transport_bytes[0] == transfer &&
    plan.transport_execution_bytes.length() == 1 &&
    plan.transport_execution_bytes[0] == scratch &&
    value.reads.length() == 1 &&
    value.reads[0] is Some(read) &&
    read.original is Some(original) &&
    physical_equal(original, read) &&
    read.ledger is Some(original_ledger) &&
    physical_equal(original_ledger, ledger) &&
    read.managed_run is Some((original_run, 0)) &&
    physical_equal(original_run, value) &&
    read.whole_input is Some(original_capacity) &&
    physical_equal(original_capacity, selected) else {
    return Err(ForeignOriginal)
  }
  if !installed_effect_limits_fit(plan.limits, @resources.ledger_limits(ledger)) {
    return Err(InsufficientCapacity)
  }
  Ok(ledger)
}

///|
pub fn installed_whole_source_capture_capacity(
  original : @sourceviews.SourceAcquisition,
  acquisition : @row_source_host.RowInputAcquisition,
  provider : @execution.ExecutionCapacity?,
) -> ClientInstalledWholeSourceCapacity? {
  guard provider is Some(provider) &&
    @row_source_host.row_input_acquisition_matches_source(acquisition, original) &&
    @row_source_host.row_input_acquisition_capacity(acquisition, Some(provider))
    is Some(complete) else {
    return None
  }
  Some({ original, acquisition, provider, complete, })
}

///|
/// The existing Run retains this same input preparation and reader response
/// borrow before another fallible callback can escape. No second admission or
/// raw Ledger is exposed to the provider.
pub fn begin_installed_managed_whole_source_read(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  declaration : @row_source_host.RowDeclaration,
) -> Result[
  (
    ClientInstalledSourceRead,
    @sourceviews.SourceAcquisition,
    @row_source_host.RowInputAcquisition,
    ClientInstalledWholeSourceCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard owner.preparation is Some(PureManaged(_, actual)) &&
    physical_equal(actual, prepared) &&
    physical_equal(owner.request, request) &&
    owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    plan.whole_input is Some(source) else {
    return Err(ForeignOriginal)
  }
  match
    @row_source_host.check_row_input_acquisition_original(
      source.acquisition,
      declaration,
      source.original,
    ) {
    Ok(_) => ()
    Err(_) => return Err(ForeignOriginal)
  }
  let read = match begin_installed_managed_run_source_read(owner, 0) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard owner.captured_preparation is Some(after) &&
    physical_equal(after, plan) &&
    owner.preparation is Some(PureManaged(_, actual)) &&
    physical_equal(actual, prepared) &&
    physical_equal(owner.request, request) else {
    return Err(ForeignOriginal)
  }
  read.declaration = Some(declaration)
  read.whole_input = Some(source)
  Ok((read, source.original, source.acquisition, source))
}

///|
pub fn start_installed_whole_source_read_rows(
  read : ClientInstalledSourceRead,
  acquisition : @row_source_host.RowInputAcquisition,
  nonce : String,
  original_stop : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@row_source_host.RowRun, ClientInstalledSourceReadIssue] {
  let ledger = match require_installed_source_read_current(read) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard read.whole_input is Some(selected) &&
    physical_equal(selected.acquisition, acquisition) else {
    return Err(ForeignOriginal)
  }
  if read.started {
    return Err(AlreadyStarted)
  }
  read.started = true
  retain_installed_source_read_run(
    read,
    @row_source_host.start_accounted_row_input_acquisition(
      acquisition,
      Some(selected.provider),
      nonce,
      original_stop,
      ledger,
      transfer_bytes,
      execution_bytes,
    ),
  )
}

///|
/// Complete input and actual Compute coexist on the same Request parent.
/// Construction of these originals must already be held by that parent; this
/// immutable plan describes later overlap, not permission or retroactive credit.
pub fn prepare_installed_managed_whole_source_plan(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  source : ClientInstalledWholeSourceCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  prepare_installed_managed_whole_source_plan_owned(
    prepared,
    request,
    source,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    None,
    retained_output~,
    provider_factory~,
  )
}

///|
/// Consume an already bound original invocation, never another clock, compiler
/// or Definition. The same Request constructor must already back and retain
/// its input, output, helpers and failed-child overlap before this DATA call.
pub fn prepare_installed_managed_whole_source_plan_at_query_time(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  source : ClientInstalledWholeSourceCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  invocation : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )?,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  guard invocation is Some((original, original_request, compiled, definition)) &&
    physical_equal(original_request, request) else {
    return Err(ForeignOriginal)
  }
  match
    @publication_host.client_query_time_preparation_context_for_run(
      original, prepared, compiled, definition, request,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  prepare_installed_managed_whole_source_plan_owned(
    prepared,
    request,
    source,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    Some(original),
    retained_output~,
    provider_factory~,
  )
}

///|
fn prepare_installed_managed_whole_source_plan_owned(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  source : ClientInstalledWholeSourceCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  query_time : @publication_host.ClientQueryTimePreparation?,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) ||
    !@publication_host.client_source_acquisition_matches_program(
      prepared,
      0,
      0,
      source.original,
    ) ||
    transport_bytes < 0L ||
    transport_execution_bytes < 0L ||
    !installed_managed_run_purpose_supported(prepared) {
    return Err(ForeignOriginal)
  }
  let graph = match
    @strategy.prepare_source_input_dag(
      @publication_host.prepared_client_graph(prepared),
      source.original,
    ) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  let sequences = match
    prepare_client_local_sequences_owned(
      Pure(prepared),
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time=query_time.map(original => (original, request)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_rows = Int::max(
    @publication_host.prepared_client_values_max_rows(prepared),
    @row_source_host.row_input_acquisition_max_rows(source.acquisition),
  )
  let capacity_plan = client_local_capacity_plan(
    sequences,
    max_rows,
    scalar_values=true,
    graph=Some(graph),
  )
  let inputs = Array::makei(sequences.length(), task => {
    @strategy.graph_task_input_count(graph, task).unwrap_or(0)
  })
  guard client_local_sequence_capacity_original(
      sequences,
      @strategy.graph_task_count(graph),
      capacity_plan=Some(capacity_plan),
      retained_inputs=Some(inputs),
      max_rows~,
      retained_output~,
      include_simultaneous=true,
      simultaneous_graph=Some(graph),
    )
    is Some(local_capacity) else {
    return Err(Unsupported)
  }
  guard prepare_client_local_configuration(
      graph,
      capacity_plan,
      ExecutionRows,
      local_capacity.provider_retained,
      local_capacity.provider_execution,
      retained_output,
      provider_factory,
    )
    is Some(configuration) &&
    client_prepared_local_configuration_capacity(
      configuration,
      local_capacity.limits,
    )
    is Some(actual) else {
    return Err(Unsupported)
  }
  let retained = @execution.execution_capacity_retained_bytes(source.complete)
  let execution = @execution.execution_capacity_execution_bytes(source.complete)
  guard local_capacity.simultaneous
    is Some((compute_retained, compute_execution)) else {
    return Err(Unsupported)
  }
  let base = actual.limits
  if retained > 9223372036854775807L - compute_retained ||
    execution > 9223372036854775807L - compute_execution ||
    execution + compute_execution >
    9223372036854775807L - transport_execution_bytes ||
    transport_bytes > 9223372036854775807L - base.transfer_bytes ||
    base.attempts == 2147483647 ||
    base.holdings == 2147483647 {
    return Err(InsufficientCapacity)
  }
  let limits : @resources.LedgerLimits = {
    ..base,
    attempts: base.attempts + 1,
    holdings: base.holdings + 1,
    transfer_bytes: base.transfer_bytes + transport_bytes,
    retained_bytes: Int64::max(base.retained_bytes, compute_retained + retained),
    execution_bytes: Int64::max(
      base.execution_bytes,
      compute_execution + execution + transport_execution_bytes,
    ),
  }
  Ok({
    prepared,
    request,
    _observed_query_time: query_time,
    captures: [],
    whole_input: Some(source),
    direct_occurrences: None,
    model_input_prefix: None,
    model_input_suffix: None,
    graph,
    transport_bytes: [transport_bytes],
    transport_execution_bytes: [transport_execution_bytes],
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    sequences,
    compute_sequences: sequences,
    capacity_plan,
    configuration,
    compilation: None,
    limits,
  })
}
