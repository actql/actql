///|
/// A typed alternative in the existing Source/Compute Plan. It retains one
/// complete original input and its selected provider recipe, never a Query
/// requirement, a second Run or caller-supplied capacity scalars.
struct ClientInstalledWholeSourceCapacity {
  original : @sourceviews.SourceAcquisition
  acquisition : @row_source_host.RowInputAcquisition
  provider : @execution.ExecutionCapacity?
  complete : @execution.ExecutionCapacity
}

///|
// Borrow the actual Host policy retained by this checked Program. A Source
// capture ceiling or observed row count cannot substitute for this owner.
fn installed_source_listing_policy(
  graph : @strategy.CheckedDAG,
) -> @capacity.Policy {
  let identity = @checked.source_identity(@strategy.graph_program(graph))
  let sources = @context.program_identity_sources(identity)
  let operations = @context.program_sources_operations(sources)
  let preparation = @context.operation_profiles_preparation(operations)
  let producers = @context.preparation_sources(preparation)
  let capacity = @context.source_producer_capacity(producers)
  let selected = @context.source_policy_selected(
    @context.source_capacity_context(capacity),
  )
  @environment.capacity_policy(@context.selected_capacity(selected))
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
/// The existing installed Row input profile, shared by Pure and Effect
/// constructors. Source row/page policy is retained exactly as configured;
/// this DATA neither admits resources nor grants a physical read.
pub fn installed_row_input_policy(
  max_rows : Int,
  max_page_bytes : Int,
  max_page_nodes : Int,
  max_page_depth : Int,
  max_page_rows : Int,
) -> @row_source_host.RowInputLimits {
  {
    max_rows,
    page: {
      max_bytes: max_page_bytes,
      max_nodes: max_page_nodes,
      max_depth: max_page_depth,
      max_rows: max_page_rows,
    },
    retention: {
      max_nodes: 100000,
      max_text_bytes: 500000,
      max_depth: 100,
      max_work: 20000000,
    },
    wire: {
      max_columns: 100,
      max_order_work: 100000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
    },
  }
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
  prepare_installed_whole_source_capacity_original(
    prepared,
    original,
    Some(declaration),
    contracts,
    limits,
    provider,
  )
}

///|
/// The installed DuckDB implementation projects its already checked Catalog
/// SourceView instead of regenerating an unrelated row declaration.
pub fn prepare_installed_catalog_whole_source_capacity(
  prepared : @publication_host.PreparedClientProgram,
  original : @sourceviews.SourceAcquisition,
  contracts : ClientInstalledSequenceContracts,
  limits : @row_source_host.RowInputLimits,
) -> Result[ClientInstalledWholeSourceCapacity, ClientInstalledManagedRunIssue] {
  // This installed table binding has no parameterized Source Request compiler.
  // Preserve that checked payload by refusing it, never by dropping fields.
  if @sourceviews.parameterized_request_field_count(
      @sourceviews.source_acquisition_request(original),
    ) !=
    0 {
    return Err(Unsupported)
  }
  prepare_installed_whole_source_capacity_original(
    prepared,
    original,
    None,
    contracts,
    limits,
    None,
  )
}

///|
fn prepare_installed_whole_source_capacity_original(
  prepared : @publication_host.PreparedClientProgram,
  original : @sourceviews.SourceAcquisition,
  declaration : @row_source_host.RowDeclaration?,
  contracts : ClientInstalledSequenceContracts,
  limits : @row_source_host.RowInputLimits,
  provider : @execution.ExecutionCapacity?,
) -> Result[ClientInstalledWholeSourceCapacity, ClientInstalledManagedRunIssue] {
  let stage = @sourceviews.declaration(
      @sourceviews.mode_input(@sourceviews.source_acquisition_mode(original)),
    ).stage_index
  let ordinal = @sourceviews.source_acquisition_source_index(original)
  let graph = @publication_host.prepared_client_graph(prepared)
  guard @publication_host.client_source_acquisition_matches_program(
      prepared, stage, ordinal, original,
    ) &&
    @strategy.graph_stage_operation_task(graph, stage, 0) is Some(task) else {
    return Err(ForeignOriginal)
  }
  // The same nominal Source original already attests a bounded snapshot and
  // bound request. Its correspondence above selects THIS complete sequence;
  // inspecting the narrower Query grammar again would discard root placement
  // and reject the complete-input choice made from the checked Result graph.
  let sequence = match
    @publication_host.prepare_prepared_client_full_sequence(
      prepared,
      task,
      @publication_host.prepared_client_values_sequence_limits(prepared),
    ) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  let program = @checked.source_identity(
    @strategy.graph_program(@publication_host.prepared_client_graph(prepared)),
  )
  let policy = Some(
    installed_source_listing_policy(
      @publication_host.prepared_client_graph(prepared),
    ),
  )
  let acquisition = match
    (match declaration {
      Some(declaration) =>
        @row_source_host.prepare_row_input_acquisition(
          original,
          program,
          sequence,
          contracts.original.value.contracts,
          declaration,
          limits,
          listing_policy=policy,
        )
      None =>
        @row_source_host.prepare_catalog_row_input_acquisition(
          original,
          program,
          sequence,
          contracts.original.value.contracts,
          limits,
          listing_policy=policy,
        )
    }) {
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
  value.provider is Some(selected) &&
  physical_equal(selected, provider)
}

///|
/// Borrowed immutable correspondence only. The read entrance still checks
/// its same current parent and expected physical Ledger before starting work.
pub fn installed_whole_source_read_capacity_matches(
  read : ClientInstalledSourceRead,
  value : ClientInstalledWholeSourceCapacity,
  acquisition : @row_source_host.RowInputAcquisition,
  provider : @execution.ExecutionCapacity,
) -> Bool {
  read.original is Some(original) &&
  physical_equal(original, read) &&
  read.ledger is Some(_) &&
  read.whole_input is Some(selected) &&
  physical_equal(selected, value) &&
  check_installed_whole_source_capacity(value, acquisition, provider)
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
  Ok(if !plan.whole_sources.is_empty() { "whole-input" } else { "query" })
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
  installed_managed_whole_sources_ledger(
    value,
    prepared,
    request,
    [capacity],
    [transfer],
    [scratch],
  )
}

///|
pub fn installed_managed_whole_sources_ledger(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  capacities : Array[ClientInstalledWholeSourceCapacity],
  transfer : Array[Int64],
  scratch : Array[Int64],
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
    !plan.whole_sources.is_empty() &&
    capacities.length() == plan.whole_sources.length() &&
    transfer == plan.transport_bytes &&
    scratch == plan.transport_execution_bytes &&
    value.reads.length() == capacities.length() else {
    return Err(ForeignOriginal)
  }
  for index, capacity in capacities {
    guard physical_equal(plan.whole_sources[index], capacity) &&
      value.reads[index] is Some(read) &&
      read.original is Some(original) &&
      physical_equal(original, read) &&
      read.ledger is Some(original_ledger) &&
      physical_equal(original_ledger, ledger) &&
      read.managed_run is Some((original_run, slot)) &&
      slot == index &&
      physical_equal(original_run, value) &&
      read.whole_input is Some(original_capacity) &&
      physical_equal(original_capacity, capacity) else {
      return Err(ForeignOriginal)
    }
  }
  if !installed_managed_capture_parent_fits(
      value,
      prepared,
      ledger,
      plan.limits,
    ) {
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
  guard @row_source_host.row_input_acquisition_matches_source(
      acquisition, original,
    ) &&
    @row_source_host.row_input_acquisition_capacity(acquisition, provider)
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
  begin_installed_managed_whole_source_read_original(
    owner,
    prepared,
    request,
    Some(declaration),
    None,
    0,
  )
}

///|
/// Native's original entered Ledger and the selected transport are checked
/// with this same read acquisition. Do not call a second callbackful Ledger
/// getter immediately after creating the read. Original partial read custody
/// remains on the same Run if a post-current constructor fence refuses.
pub fn begin_installed_managed_whole_source_read_on_ledger(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  declaration : @row_source_host.RowDeclaration,
  expected : ClientInstalledWholeSourceCapacity,
  ledger : @resources.Ledger,
  transfer : Int64,
  scratch : Int64,
) -> Result[
  (
    ClientInstalledSourceRead,
    @sourceviews.SourceAcquisition,
    @row_source_host.RowInputAcquisition,
    ClientInstalledWholeSourceCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    plan.whole_sources.length() == 1 &&
    physical_equal(plan.whole_sources[0], expected) &&
    plan.transport_bytes.length() == 1 &&
    plan.transport_bytes[0] == transfer &&
    plan.transport_execution_bytes.length() == 1 &&
    plan.transport_execution_bytes[0] == scratch &&
    owner.ledger is Some(original) &&
    physical_equal(original, ledger) else {
    return Err(ForeignOriginal)
  }
  let acquired = match
    begin_installed_managed_whole_source_read_original(
      owner,
      prepared,
      request,
      Some(declaration),
      Some(expected),
      0,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard owner.captured_preparation is Some(after) &&
    physical_equal(after, plan) &&
    owner.ledger is Some(original) &&
    physical_equal(original, ledger) &&
    acquired.0.ledger is Some(actual) &&
    physical_equal(actual, ledger) else {
    return Err(ForeignOriginal)
  }
  if !installed_managed_capture_parent_fits(
      owner,
      prepared,
      ledger,
      plan.limits,
    ) {
    return Err(InsufficientCapacity)
  }
  Ok(acquired)
}

///|
pub fn begin_installed_managed_catalog_whole_source_read(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  source : ClientInstalledWholeSourceCapacity,
) -> Result[
  (
    ClientInstalledSourceRead,
    @sourceviews.SourceAcquisition,
    @row_source_host.RowInputAcquisition,
    ClientInstalledWholeSourceCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  begin_installed_managed_whole_source_read_original(
    owner,
    prepared,
    request,
    None,
    Some(source),
    0,
  )
}

///|
pub fn begin_installed_managed_whole_source_read_at(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  declaration : @row_source_host.RowDeclaration,
  occurrence : Int,
) -> Result[
  (
    ClientInstalledSourceRead,
    @sourceviews.SourceAcquisition,
    @row_source_host.RowInputAcquisition,
    ClientInstalledWholeSourceCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  begin_installed_managed_whole_source_read_original(
    owner,
    prepared,
    request,
    Some(declaration),
    None,
    occurrence,
  )
}

///|
fn begin_installed_managed_whole_source_read_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  declaration : @row_source_host.RowDeclaration?,
  expected : ClientInstalledWholeSourceCapacity?,
  occurrence : Int,
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
    plan.whole_sources.get(occurrence) is Some(source) else {
    return Err(ForeignOriginal)
  }
  if expected is Some(actual) && !physical_equal(actual, source) {
    return Err(ForeignOriginal)
  }
  if declaration is Some(declaration) {
    match
      @row_source_host.check_row_input_acquisition_original(
        source.acquisition,
        declaration,
        source.original,
      ) {
      Ok(_) => ()
      Err(_) => return Err(ForeignOriginal)
    }
  }
  let read = match begin_installed_managed_run_source_read(owner, occurrence) {
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
  read.declaration = declaration
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
  expected_ledger? : @resources.Ledger? = None,
) -> Result[@row_source_host.RowRun, ClientInstalledSourceReadIssue] {
  let ledger = match require_installed_source_read_current(read) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard read.whole_input is Some(selected) &&
    physical_equal(selected.acquisition, acquisition) else {
    return Err(ForeignOriginal)
  }
  if expected_ledger is Some(original) && !physical_equal(original, ledger) {
    return Err(ForeignOriginal)
  }
  if !(read.start is Unstarted) {
    return Err(AlreadyStarted)
  }
  read.start = Constructing
  retain_installed_source_read_run(
    read,
    @row_source_host.start_accounted_row_input_acquisition(
      acquisition,
      selected.provider,
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
  runtime_admission? : Bool = false,
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
    runtime_admission~,
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
  runtime_admission? : Bool = false,
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
    runtime_admission~,
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
  runtime_admission? : Bool = false,
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  prepare_installed_managed_whole_sources_plan(
    prepared,
    request,
    [source],
    [transport_bytes],
    [transport_execution_bytes],
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    retained_output~,
    provider_factory~,
    runtime_admission~,
    query_time~,
  )
}

///|
/// Complete checked inputs use the same captured Plan/Compute engine. Every
/// occurrence retains its real Source original; no completed task is invented.
pub fn prepare_installed_managed_whole_sources_plan(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  sources : Array[ClientInstalledWholeSourceCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
  runtime_admission? : Bool = false,
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  if sources.is_empty() {
    return Err(Unsupported)
  }
  prepare_installed_managed_capture_plan_owned(
    prepared,
    request,
    [],
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    false,
    retained_output~,
    provider_factory~,
    query_time~,
    runtime_admission~,
    whole_sources=sources,
  )
}

///|
pub fn prepare_installed_managed_whole_sources_plan_at_query_time(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  sources : Array[ClientInstalledWholeSourceCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
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
  runtime_admission? : Bool = false,
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
  prepare_installed_managed_whole_sources_plan(
    prepared,
    request,
    sources,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    query_time=Some(original),
    retained_output~,
    provider_factory~,
    runtime_admission~,
  )
}

///|
/// Fixed native projection of the original checked complete input. The same
/// installed SQL byte policy bounds escaping before any quoted SQL is built.
pub fn render_installed_catalog_source_sql(
  capacity : ClientInstalledWholeSourceCapacity,
  database_schema : String,
  table : String,
  max_bytes : Int,
) -> Result[String, @row_source_host.RowHostIssue] {
  if @sourceviews.parameterized_request_field_count(
      @sourceviews.source_acquisition_request(capacity.original),
    ) !=
    0 {
    return Err(@row_source_host.InvalidSpecification)
  }
  if database_schema.is_empty() || table.is_empty() {
    return Err(@row_source_host.InvalidSpecification)
  }
  let columns = @row_source_host.row_input_acquisition_columns(
    installed_whole_source_acquisition(capacity),
  )
  // Preflight the SAME installed SQL limit before materializing quoted names.
  if max_bytes < 13 {
    return Err(@row_source_host.InvalidSpecification)
  }
  let mut remaining = max_bytes - 13 // SELECT and FROM keywords
  let reserve_name = fn(name : String) {
    if remaining < 2 {
      return false
    }
    remaining -= 2
    for character in name {
      let scalar = character.to_int()
      if scalar >= 0xD800 && scalar <= 0xDFFF {
        return false
      }
      let bytes = if scalar <= 0x7F {
        1
      } else if scalar <= 0x7FF {
        2
      } else if scalar <= 0xFFFF {
        3
      } else {
        4
      }
      let bytes = bytes + (if character == '"' { 1 } else { 0 })
      if remaining < bytes {
        return false
      }
      remaining -= bytes
    }
    true
  }
  for index, name in columns {
    if index > 0 {
      if remaining < 2 {
        return Err(@row_source_host.InvalidSpecification)
      }
      remaining -= 2
    }
    if !reserve_name(name) {
      return Err(@row_source_host.InvalidSpecification)
    }
  }
  if !reserve_name(database_schema) || !reserve_name(table) || remaining < 1 {
    return Err(@row_source_host.InvalidSpecification)
  }
  let quote = fn(name : String) {
    let output = StringBuilder()
    output.write_char('"')
    for character in name {
      if character == '"' {
        output.write_char('"')
      }
      output.write_char(character)
    }
    output.write_char('"')
    output.to_string()
  }
  Ok(
    "SELECT " +
    columns.map(quote).join(", ") +
    " FROM " +
    quote(database_schema) +
    "." +
    quote(table),
  )
}
