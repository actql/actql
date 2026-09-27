///|
/// Host-fixed Local implementation configuration. Entries are private sequence
/// handles, not shared planner payloads or reconstructed checked owners.
struct LocalComputeModule {
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  sequences : Array[@execution.GeneratedSequence]
  managed_providers : Array[ManagedProvider]
  managed_capacity : @connector.FixedComputeCapacity
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  max_work : Int
}

///|
pub(all) enum LocalModuleIssue {
  Candidate(@connector.FixedComputeIssue)
  NotSelected
  Capacity
  Execution(@connector.FixedComputeIssue)
  Materializing(LocalMaterializingIssue)
}

///|
/// Pure bounded installation. This snapshots only the sequence-handle container;
/// it does not admit values, execute a sequence, or allocate task resources.
pub fn prepare_local_compute_module(
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  sequences : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_work : Int,
  max_sequences : Int,
  managed_capacity? : @connector.FixedComputeCapacity,
  managed_providers? : Array[ManagedProvider] = [],
) -> Result[LocalComputeModule, @connector.FixedComputeIssue] {
  if max_work < 1 || max_sequences < 0 || sequences.length() > max_sequences {
    return Err(InvalidLimits)
  }
  if !@connector.capability_registration_matches(registration, registry) {
    return Err(ForeignCapability(0))
  }
  if !@connector.capability_description(registration).fixed_compute {
    return Err(ComputeUnsupported)
  }
  for sequence in sequences {
    let mut matches = 0
    for provider in managed_providers {
      if managed_provider_accepts(provider, sequence) {
        matches += 1
        if matches > 1 || managed_provider_capacity(provider, sequence) is None {
          return Err(ForeignPreparation)
        }
      }
    }
  }
  Ok({
    registry,
    registration,
    sequences: sequences.copy(),
    managed_providers: managed_providers.copy(),
    managed_capacity: managed_capacity.unwrap_or({
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: execution.rows.max_rows,
      max_value_bytes: measurement.max_bytes,
      common_fragment: None,
    }),
    execution,
    measurement,
    max_work,
  })
}

///|
/// Pure product preparation for the finite managed Local connection. No
/// representation is opened and no task reservation is started here.
pub fn[T] prepare_local_module_managed_compute(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.ManagedFixedComputeRequest[T],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
) -> Result[
  (
    @connector.PreparedManagedCompute[T, @execution.GeneratedSequence],
    @connector.ManagedFixedComputeChoice[T],
  ),
  LocalModuleIssue,
] {
  prepare_local_module_managed_compute_with_estimates(
    installed,
    slot,
    request,
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
    interval_search_ceilings~,
    asof_search_ceilings~,
  )
}

///|
/// Compatible extension used by Site-aware automatic comparison. The caller
/// supplies connector-owned duration estimates without changing the existing
/// finite Local preparation entrypoint.
pub fn[T] prepare_local_module_managed_compute_with_estimates(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.ManagedFixedComputeRequest[T],
  estimates : Array[@cost.SerialEstimateLine],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
) -> Result[
  (
    @connector.PreparedManagedCompute[T, @execution.GeneratedSequence],
    @connector.ManagedFixedComputeChoice[T],
  ),
  LocalModuleIssue,
] {
  guard installed.sequences.get(slot) is Some(configured) else {
    return Err(Candidate(ComputeUnsupported))
  }
  let mut sequence = configured
  for (step, ceiling) in interval_search_ceilings {
    sequence = match
      @execution.constrain_generated_interval_search(sequence, step, ceiling) {
      Ok(value) => value
      Err(_) => return Err(Candidate(ForeignPreparation))
    }
  }
  for (step, ceiling) in asof_search_ceilings {
    sequence = match
      @execution.constrain_generated_asof_search(sequence, step, ceiling) {
      Ok(value) => value
      Err(issue) => return Err(Candidate(Execution(issue)))
    }
  }
  let provider = local_module_managed_provider(installed, sequence)
  let candidate = match
    local_managed_fixed_compute_candidate(
      installed.registration,
      request,
      sequence,
      estimates,
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      installed.max_work,
      provider_supported=provider is Some(_),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let choice = match
    @connector.choose_managed_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_managed_compute_candidate(candidate)],
      None,
      installed.max_work,
    ) {
    Ok(Proposed(value)) => value
    Ok(_) => return Err(NotSelected)
    Err(issue) => return Err(Candidate(issue))
  }
  Ok((candidate, choice))
}

///|
pub fn local_module_managed_provider(
  installed : LocalComputeModule,
  sequence : @execution.GeneratedSequence,
) -> ManagedProvider? {
  local_managed_provider_for(
    installed.managed_providers,
    installed.execution,
    installed.measurement,
    sequence,
  )
}

///|
/// A Values publication check is discharged only by the exact one-step
/// bounded Values provider. Its admitted output and typed row construction
/// enforce the checked source obligation before completion is exposed.
pub fn local_module_bounded_values_publication(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  @execution.generated_sequence_step_index_at(sequence, 0) is Some(_) &&
  @execution.generated_sequence_step_index_at(sequence, 1) is None &&
  @execution.generated_sequence_step_at(sequence, 0)
  is Some(@lower.ValuesStep(_)) &&
  local_module_managed_provider(installed, sequence) is Some(_)
}

///|
/// The bounded provider owning `sequence`: a registered family provider first,
/// then the built-in relation providers bound to the module limits.
fn local_managed_provider_for(
  family : Array[ManagedProvider],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  sequence : @execution.GeneratedSequence,
) -> ManagedProvider? {
  for provider in family {
    if managed_provider_accepts(provider, sequence) {
      return Some(provider)
    }
  }
  let relation = selected_relation_provider(execution, measurement)
  if managed_provider_accepts(relation, sequence) {
    return Some(relation)
  }
  let global_count = global_count_provider(execution, measurement)
  if managed_provider_accepts(global_count, sequence) {
    return Some(global_count)
  }
  let group = group_provider(execution, measurement)
  if managed_provider_accepts(group, sequence) {
    return Some(group)
  }
  let row_window = row_window_provider(execution, measurement)
  if managed_provider_accepts(row_window, sequence) {
    return Some(row_window)
  }
  let unpivot = unpivot_provider(execution, measurement)
  if managed_provider_accepts(unpivot, sequence) {
    return Some(unpivot)
  }
  let unnest = unnest_provider(execution, measurement)
  if managed_provider_accepts(unnest, sequence) {
    return Some(unnest)
  }
  let cross_join = cross_join_provider(execution, measurement)
  if managed_provider_accepts(cross_join, sequence) {
    return Some(cross_join)
  }
  let append = append_provider(execution, measurement)
  if managed_provider_accepts(append, sequence) {
    return Some(append)
  }
  let set = set_provider(execution, measurement)
  if managed_provider_accepts(set, sequence) {
    return Some(set)
  }
  let nest = nest_provider(execution, measurement)
  if managed_provider_accepts(nest, sequence) {
    return Some(nest)
  }
  let values = values_provider(execution, measurement)
  if managed_provider_accepts(values, sequence) {
    return Some(values)
  }
  None
}

///|
/// Exact installed sequence capability used by candidate estimation. This is
/// the same bounded provider decision used during preparation: managed Local
/// work never falls back to the synchronous whole-sequence evaluator.
pub fn local_module_managed_sequence_supported(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_module_managed_provider(installed, sequence) is Some(_)
}

///|
pub fn local_module_managed_capacity(
  installed : LocalComputeModule,
) -> @connector.FixedComputeCapacity {
  installed.managed_capacity
}

///|
pub fn local_module_execution_limits(
  installed : LocalComputeModule,
) -> @execution.SequenceExecutionLimits {
  installed.execution
}

///|
pub fn local_module_measurement_limits(
  installed : LocalComputeModule,
) -> @execution.FixedInputGuardMeasureLimits {
  installed.measurement
}

///|
pub fn local_module_max_work(installed : LocalComputeModule) -> Int {
  installed.max_work
}

///|
/// The slot is this module's bounded configuration index, not a semantic task
/// identity. Candidate preparation still verifies the exact request owner.
pub fn prepare_local_module_compute(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.FixedComputeRequest,
  join_output_ceiling : (Int, Int64)?,
  join_output_ceilings? : Array[(Int, Int64)] = [],
) -> Result[@connector.SynchronousCompute, LocalModuleIssue] {
  let (candidate, choice) = match
    local_module_candidate(installed, slot, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    prepare_local_compute_execution(
      choice,
      candidate,
      installed.execution,
      installed.measurement,
      join_output_ceiling~,
      join_output_ceilings~,
    ) {
    Ok(compute) => Ok(compute)
    Err(InvalidLimits) => Err(Capacity)
    Err(issue) => Err(Execution(issue))
  }
}

///|
/// Both execution forms select the exact installed sequence and request. A
/// conversion changes representation, never the selected computation or owner.
fn local_module_candidate(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.FixedComputeRequest,
) -> Result[
  (
    @connector.PreparedCompute[@execution.GeneratedSequence],
    @connector.FixedComputeChoice,
  ),
  LocalModuleIssue,
] {
  guard installed.sequences.get(slot) is Some(sequence) else {
    return Err(Candidate(ForeignPreparation))
  }
  let candidate = match
    local_fixed_compute_candidate(
      installed.registration,
      request,
      sequence,
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      installed.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let choice = match
    @connector.choose_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_compute_candidate(candidate)],
      Some([0]),
      installed.max_work,
    ) {
    Ok(Proposed(choice)) => choice
    Ok(_) => return Err(NotSelected)
    Err(issue) => return Err(Candidate(issue))
  }
  Ok((candidate, choice))
}

///|
/// Pure preparation for an installed Local implementation receiving retained
/// inputs. The common Host must reserve and start the returned execution before
/// a Store reader is invoked. No file or transport implementation is selected here.
pub fn[E] prepare_local_module_materializing_compute(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.FixedComputeRequest,
  imports : LocalImportLimits,
  issue : (LocalMaterializingIssue) -> E,
  join_output_ceiling : (Int, Int64)?,
  output_limits? : LocalExportLimits? = None,
  join_output_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  aggregate_output_ceilings? : Array[@connector.AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[@connector.AnalyticEnvelope] = [],
) -> Result[
  @connector.PreparedExecution[LocalMaterializingAttempt, E],
  LocalModuleIssue,
] {
  let (candidate, choice) = match
    local_module_candidate(installed, slot, request) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  prepare_local_materializing_execution(
    choice,
    candidate,
    installed.execution,
    installed.measurement,
    imports,
    issue,
    join_output_ceiling~,
    output_limits~,
    join_output_ceilings~,
    interval_search_ceilings~,
    asof_search_ceilings~,
    aggregate_output_ceilings~,
    analytic_envelopes~,
    family_providers=installed.managed_providers,
    provider_capacity=Some(installed.managed_capacity),
  ).map_err(error => Materializing(error))
}

///|
/// Capacity for the module's actual fixed sequence and selected limits, not an
/// estimate derived from output cardinality or an exported mutable sequence.
pub fn local_module_capacity(
  installed : LocalComputeModule,
  slot : Int,
) -> @execution.ExecutionCapacity? {
  guard installed.sequences.get(slot) is Some(sequence) else { return None }
  // Managed Local work reserves its bounded provider's capacity, so offers
  // advertise that same envelope.
  match local_module_managed_provider(installed, sequence) {
    Some(provider) => managed_provider_capacity(provider, sequence)
    None =>
      @execution.generated_sequence_capacity(
        sequence,
        installed.execution,
        installed.measurement,
      )
  }
}
