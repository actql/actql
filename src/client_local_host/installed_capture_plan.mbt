///|
/// Same original Pure computation, Source inventory and configured Compute
/// retained before its Run. This DATA supplies no new resource/read authority.
struct ClientInstalledManagedCapturePlan {
  prepared : @publication_host.PreparedClientProgram
  request : @publication_host.ClientRequestIdentity
  // Lifetime root for the same bound invocation; sequence owners retain its
  // context while this original also retains the definition/sample binding.
  _observed_query_time : @publication_host.ClientQueryTimePreparation?
  captures : Array[ClientInstalledCaptureCapacity]
  direct_occurrences : @publication_host.ClientDirectAcquisitionOccurrences?
  whole_input : ClientInstalledWholeSourceCapacity?
  graph : @strategy.CheckedDAG
  transport_bytes : Array[Int64]
  transport_execution_bytes : Array[Int64]
  installed_contracts : ClientInstalledSequenceContracts
  values_body : String
  fragment_body : String?
  ordered_body : String?
  sequences : Array[@execution.GeneratedSequence]
  compute_sequences : Array[@execution.GeneratedSequence]
  capacity_plan : ClientLocalCapacityPlan
  configuration : ClientPreparedLocalConfiguration
  mut model_input_prefix : @execution.GeneratedSequence?
  mut model_input_suffix : @execution.GeneratedSequence?
  mut compilation : @publication_host.ClientRunCompilation?
  limits : @resources.LedgerLimits
}

///|
/// Consume the caller's already prepared original capture inventory; never
/// reconstruct its queries/acquisitions merely to quote the same Source again.
/// Provider/reader/physical and this constructor overlap must already be backed
/// by the SAME Request. These immutable bounds are neither a grant nor knobs.
pub fn prepare_installed_managed_capture_plan(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  captures : Array[ClientInstalledCaptureCapacity],
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
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  prepare_installed_managed_capture_plan_owned(
    prepared,
    request,
    captures,
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
  )
}

///|
fn prepare_installed_managed_capture_plan_owned(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  captures : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  model_purpose : Bool,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
  direct_occurrences? : @publication_host.ClientDirectAcquisitionOccurrences? = None,
  model? : @publication_host.ClientInferPlanGraph? = None,
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_captured_prefix(graph)
  if !installed_managed_owner_shape_supported(
      Pure(prepared),
      model_purpose,
      model~,
    ) ||
    count < 1 ||
    captures.length() != count ||
    transport_bytes.length() != count ||
    transport_execution_bytes.length() != count {
    return Err(Unsupported)
  }
  let direct = match direct_occurrences {
    Some(value) => value
    None =>
      match installed_direct_occurrences_owned(Pure(prepared)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  if !installed_direct_occurrences_match_owner(direct, Pure(prepared)) ||
    @publication_host.client_direct_acquisition_occurrence_count(direct) !=
    count {
    return Err(ForeignOriginal)
  }
  for index, original in captures {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        direct, index,
      )
      is Some((stage, input, task)) &&
      task == index else {
      return Err(ForeignOriginal)
    }
    if !@publication_host.client_query_requirement_matches_original_query_time(
        prepared,
        stage,
        input,
        original.requirement,
        query_time,
        request,
      ) {
      return Err(ForeignOriginal)
    }
    if original.original_input {
      guard original.acquisition is Some(acquisition) &&
        physical_equal(
          original.requirement,
          @row_source_host.row_acquisition_requirement(acquisition),
        ) else {
        return Err(ForeignOriginal)
      }
      if original.provider is Some((selected, _)) &&
        !physical_equal(selected, acquisition) {
        return Err(ForeignOriginal)
      }
    } else if original.acquisition is Some(_) || original.provider is Some(_) {
      return Err(ForeignOriginal)
    }
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
  let compute = match
    prepare_installed_compute_preparation(
      Pure(prepared),
      None,
      sequences,
      captures,
      transport_bytes,
      transport_execution_bytes,
      retained_output,
      provider_factory,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard installed_direct_occurrences_layout(count)
    is Some((selector_retained, _)) &&
    @execution.checked_preparation_add_product(
      compute.limits.retained_bytes,
      selector_retained,
      1L,
    )
    is Some(retained_bytes) &&
    @execution.checked_preparation_add_product(
      compute.limits.execution_bytes,
      selector_retained,
      1L,
    )
    is Some(execution_bytes) else {
    return Err(InsufficientCapacity)
  }
  let limits = { ..compute.limits, retained_bytes, execution_bytes, }
  Ok({
    prepared,
    request,
    _observed_query_time: query_time,
    captures: captures.copy(),
    whole_input: None,
    direct_occurrences: Some(direct),
    graph: @publication_host.prepared_client_graph(prepared),
    transport_bytes: transport_bytes.copy(),
    transport_execution_bytes: transport_execution_bytes.copy(),
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    sequences,
    compute_sequences: compute.sequences,
    capacity_plan: compute.capacity_plan,
    configuration: compute.configuration,
    model_input_prefix: None,
    model_input_suffix: None,
    compilation: None,
    limits,
  })
}

///|
pub fn prepared_installed_managed_capture_requirements(
  original : ClientInstalledManagedCapturePlan,
) -> Array[Int64] {
  installed_effect_requirements(original.limits)
}

///|
/// The original Row acquisition, when this occurrence is a RowSource rather
/// than Native capture. No declaration, query or read token is reconstructed.
pub fn prepared_installed_managed_capture_acquisition(
  original : ClientInstalledManagedCapturePlan,
  occurrence : Int,
) -> @row_source_host.RowAcquisition? {
  match original.captures.get(occurrence) {
    Some(value) => value.acquisition
    None => None
  }
}

///|
fn prepare_retained_installed_capture_ledger(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledManagedCapturePlan,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  ledger : @resources.Ledger,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard value.captured_preparation is Some(original) &&
    physical_equal(original, plan) &&
    value.preparation is Some(PureManaged(_, prepared)) &&
    physical_equal(prepared, plan.prepared) &&
    physical_equal(value.request, plan.request) else {
    return Err(ForeignOriginal)
  }
  if !physical_equal(installed_contracts, plan.installed_contracts) ||
    values_body != plan.values_body ||
    fragment_body != plan.fragment_body ||
    ordered_body != plan.ordered_body ||
    transport_bytes != plan.transport_bytes ||
    transport_execution_bytes != plan.transport_execution_bytes ||
    capacities.length() != plan.captures.length() ||
    value.reads.length() != plan.captures.length() {
    return Err(ForeignOriginal)
  }
  for index, capacity in capacities {
    if !physical_equal(capacity, plan.captures[index]) {
      return Err(ForeignOriginal)
    }
    if capacity.original_input {
      guard capacity.acquisition is Some(acquisition) &&
        value.reads[index] is Some(read) &&
        read.acquisition is Some(original) &&
        physical_equal(original, acquisition) &&
        read.requirement is Some(requirement) &&
        physical_equal(requirement, capacity.requirement) else {
        return Err(ForeignOriginal)
      }
      if capacity.provider is Some((selected, provider)) &&
        (
          !physical_equal(selected, acquisition) ||
          !installed_provider_row_capture_capacity_matches(
            capacity, acquisition, provider,
          )
        ) {
        return Err(ForeignOriginal)
      }
    } else if value.reads[index] is Some(_) || capacity.provider is Some(_) {
      return Err(ForeignOriginal)
    }
  }
  if !installed_effect_limits_fit(plan.limits, @resources.ledger_limits(ledger)) {
    return Err(InsufficientCapacity)
  }
  // The caller already crossed this Run's actual current boundary and its
  // post-callback original fence. No intervening callback/constructor here.
  Ok(ledger)
}

///|
pub fn installed_managed_capture_plan(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  guard value.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) else {
    return Err(ForeignOriginal)
  }
  match require_installed_managed_run(value) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(plan)
  }
}

///|
/// Typed cause from the actual original DAG constructor is never reclassified
/// as known nonacceptance or a successful None. Failed configuration retains
/// the issued DAG on its existing Run for original cleanup.
pub suberror ClientInstalledCaptureHostIssue {
  Managed(ClientInstalledManagedRunIssue)
  Run(@strategy.RunIssue)
  Configuration
}

///|
pub fn open_installed_managed_capture_host(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedDAG,
    Array[@execution.GeneratedSequence],
  ),
  ClientInstalledCaptureHostIssue,
] {
  if value.source_free_opening || value.source_free_captured is Some(_) {
    return Err(Managed(AlreadyBound))
  }
  guard value.captured_preparation is Some(plan) &&
    sources.length() ==
    (if plan.whole_input is Some(_) { 1 } else { plan.captures.length() }) else {
    return Err(Managed(ForeignOriginal))
  }
  // Bound the snapshot by the retained original occurrence inventory before
  // copying. The subsequent current callback may reenter, not alter this DATA.
  value.source_free_opening = true
  let result = open_installed_managed_capture_host_owned(
    value,
    prepared,
    request,
    sources.copy(),
  )
  value.source_free_opening = false
  result
}

///|
fn open_installed_managed_capture_host_owned(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedDAG,
    Array[@execution.GeneratedSequence],
  ),
  ClientInstalledCaptureHostIssue,
] {
  guard value.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) else {
    return Err(Managed(ForeignOriginal))
  }
  let graph = plan.graph
  let first = if plan.whole_input is Some(_) {
    1
  } else {
    @strategy.graph_captured_prefix(graph)
  }
  if first < 1 ||
    sources.length() != first ||
    !client_local_capacity_plan_matches(
      plan.capacity_plan,
      plan.compute_sequences,
      plan.capacity_plan.admitted_rows,
    ) {
    return Err(Managed(ForeignOriginal))
  }
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(Managed(issue))
    Ok(ledger) => ledger
  }
  let opened = if plan.whole_input is Some(source) {
    if !@query.captured_source_matches_input_acquisition(
        sources[0],
        source.original,
      ) {
      return Err(Managed(ForeignOriginal))
    }
    @strategy.open_source_input_dag(graph, sources[0], ledger)
  } else if first == 1 {
    @strategy.open_captured_dag(graph, sources[0], ledger)
  } else {
    @strategy.open_multi_captured_dag(
      graph,
      Array::makei(first, index => (index, sources[index])),
      ledger,
    )
  }
  let run = match opened {
    Err(issue) => return Err(Run(issue))
    Ok(run) => run
  }
  value.source_free_captured = Some(run)
  let host = bind_client_local_configuration(
    run,
    plan.configuration,
    1L,
    0L,
    0L,
    0L,
  )
  match require_installed_managed_run(value) {
    Err(issue) => {
      ignore(reject_client_local_run(run))
      return Err(Managed(issue))
    }
    Ok(original) =>
      if !physical_equal(original, ledger) {
        ignore(reject_client_local_run(run))
        return Err(Managed(ForeignOriginal))
      }
  }
  match host {
    None => Err(Configuration)
    Some(host) => Ok((host, run, plan.sequences))
  }
}

///|
/// Attach this Plan's already admitted original acquisition without generating
/// another declaration/query/Row owner. The actual RowAcquisition retains its
/// full original declaration; no copied wire/CID can supply this constructor.
pub fn begin_installed_managed_capture_read(
  value : ClientInstalledManagedRun,
  occurrence : Int,
) -> Result[ClientInstalledSourceRead, ClientInstalledManagedRunIssue] {
  guard value.captured_preparation is Some(plan) &&
    plan.captures.get(occurrence) is Some(capacity) &&
    capacity.original_input &&
    capacity.acquisition is Some(acquisition) else {
    return Err(Unsupported)
  }
  let read = match begin_installed_managed_run_source_read(value, occurrence) {
    Err(issue) => return Err(issue)
    Ok(read) => read
  }
  // No callback/await separates the original Run fence and these assignments.
  read.requirement = Some(capacity.requirement)
  read.acquisition = Some(acquisition)
  Ok(read)
}
