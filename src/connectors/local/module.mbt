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
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
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
    sequence_match_ceilings~,
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
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
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
  for (step, matches, output) in sequence_match_ceilings {
    sequence = match
      @execution.constrain_generated_sequence_match_limits(
        sequence, step, matches, output,
      ) {
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
pub(all) enum LocalBoundedTemporalRelationCheck {
  TimeSeries
  IntervalJoin
  AsOfJoin
  SequenceMatch
}

///|
fn local_sequence_contains_exact_step(
  sequence : @execution.GeneratedSequence,
  step : Int,
) -> Bool {
  let mut occurrences = 0
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    if @execution.generated_sequence_step_index_at(sequence, index) ==
      Some(step) {
      occurrences += 1
    }
  }
  occurrences == 1
}

///|
/// Temporal Relation obligations require the registered bounded family child,
/// either alone or inside the selected linear Relation-chain owner.
pub fn local_module_bounded_temporal_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
  check : LocalBoundedTemporalRelationCheck,
) -> Bool {
  local_module_bounded_family_relation_obligation(installed, slot, step, selected => {
    match (@execution.generated_sequence_step_at(selected, 0), check) {
      (Some(@lower.TimeSeriesStep(_)), TimeSeries)
      | (Some(@lower.IntervalJoinStep(_)), IntervalJoin)
      | (Some(@lower.AsOfJoinStep(_)), AsOfJoin)
      | (Some(@lower.SequenceMatchStep(_)), SequenceMatch) => true
      _ => false
    }
  })
}

///|
/// Session-only Relation admission leaves the public temporal selector enum
/// unchanged. Events-producing occurrences keep their managed Carrier route.
pub fn local_module_bounded_session_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_module_bounded_family_relation_obligation(installed, slot, step, selected => {
    @execution.generated_sequence_step_at(selected, 0)
    is Some(@lower.EventStep(_)) &&
    @lower.node_at(
      @lower.bound_preparation(@execution.generated_sequence_owner(selected)),
      step,
    ).map(node => @lower.operation(node)) ==
    Some("TEA.window.session_assign")
  })
}

///|
fn local_module_bounded_family_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
  matches : (@execution.GeneratedSequence) -> Bool,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    local_sequence_contains_exact_step(sequence, step) &&
    @execution.select_generated_sequence_step(sequence, step) is Some(selected) &&
    !local_sequence_outputs_carrier(selected) else {
    return false
  }
  if !matches(selected) ||
    !installed.managed_providers.any(provider => {
      managed_provider_accepts(provider, selected) &&
      managed_provider_capacity(provider, selected) is Some(_)
    }) {
    return false
  }
  if @execution.generated_sequence_step_count(sequence) == 1 {
    return @execution.generated_sequence_step_index_at(sequence, 0) ==
      Some(step)
  }
  // A different fused family provider cannot prove this child's execution.
  if installed.managed_providers.any(provider => {
      managed_provider_accepts(provider, sequence)
    }) {
    return false
  }
  let provider = selected_relation_provider(
    installed.execution,
    installed.measurement,
    family=installed.managed_providers,
  )
  managed_provider_accepts(provider, sequence) &&
  managed_provider_capacity(provider, sequence) is Some(_)
}

///|
/// Ranking checks belong to the exact finite-list occurrence owned by the
/// registered bounded family provider, not a generic Relation fallback.
pub fn local_module_bounded_ranking_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    @execution.generated_sequence_step_index_at(sequence, 0) == Some(step) &&
    @execution.generated_sequence_step_index_at(sequence, 1) is None &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.VectorStep(_)) &&
    @lower.node_at(
      @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
      step,
    )
    is Some(node) &&
    @lower.operation(node) == "VEC.merge_rankings" else {
    return false
  }
  installed.managed_providers.any(provider => {
    managed_provider_accepts(provider, sequence)
  })
}

///|
/// Nearest checks require the registered bounded family provider for the
/// exact selected occurrence. A generic Relation fallback is insufficient.
pub fn local_module_bounded_nearest_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    @execution.generated_sequence_step_index_at(sequence, 0) == Some(step) &&
    @execution.generated_sequence_step_index_at(sequence, 1) is None &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.VectorStep(_)) &&
    @lower.node_at(
      @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
      step,
    )
    is Some(node) &&
    @lower.operation(node) == "VEC.knn_join" else {
    return false
  }
  installed.managed_providers.any(provider => {
    managed_provider_accepts(provider, sequence)
  })
}

///|
/// An operation obligation is discharged only by the bounded provider for
/// the exact source step, inside the provider selected for the whole task.
priv enum LocalBinaryRelationOperation {
  Append
  Set
  CrossJoin
}

///|
fn local_bounded_binary_relation_step(
  installed : LocalComputeModule,
  slot : Int,
  required_step : Int,
  operation : LocalBinaryRelationOperation,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  let count = @execution.generated_sequence_step_count(sequence)
  let mut position = -1
  for index in 0..<count {
    if @execution.generated_sequence_step_index_at(sequence, index) ==
      Some(required_step) {
      if position >= 0 {
        return false
      }
      position = index
    }
  }
  guard position >= 0 &&
    @execution.select_generated_sequence_step(sequence, required_step)
    is Some(selected) else {
    return false
  }
  let matches = match
    @execution.generated_sequence_step_at(sequence, position) {
    Some(@lower.AppendStep(_)) => operation is Append
    Some(@lower.SetStep(_)) => operation is Set
    Some(@lower.CrossJoinStep(_)) => operation is CrossJoin
    _ => false
  }
  if !matches {
    return false
  }
  // Family registrations precede the built-in Relation providers. Do not
  // discharge a Relation check with a different provider's acceptance.
  for provider in installed.managed_providers {
    if managed_provider_accepts(provider, sequence) {
      return false
    }
  }
  if count > 1 &&
    !managed_provider_accepts(
      selected_relation_provider(
        installed.execution,
        installed.measurement,
        family=installed.managed_providers,
      ),
      sequence,
    ) {
    return false
  }
  let provider = match operation {
    Append => append_provider(installed.execution, installed.measurement)
    Set => set_provider(installed.execution, installed.measurement)
    CrossJoin => cross_join_provider(installed.execution, installed.measurement)
  }
  managed_provider_accepts(provider, selected)
}

///|
pub fn local_module_bounded_append_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_bounded_binary_relation_step(installed, slot, step, Append)
}

///|
pub fn local_module_bounded_set_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_bounded_binary_relation_step(installed, slot, step, Set)
}

///|
pub fn local_module_bounded_cross_join_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_bounded_binary_relation_step(installed, slot, step, CrossJoin)
}

///|
/// A retained Relation check is discharged by the exact bounded child of the
/// selected task. A registered family provider cannot stand in for that child.
pub(all) enum LocalBoundedRelationCheck {
  Group
  Analytic
  Pivot
  RowWindow
  TopK
  Lag
  JsonPick
  Watermark
  Dedupe
  Assertion
  Expansion
}

///|
fn local_bounded_relation_check(
  installed : LocalComputeModule,
  slot : Int,
  required_step : Int,
  check : LocalBoundedRelationCheck,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  let count = @execution.generated_sequence_step_count(sequence)
  let mut position = -1
  for index in 0..<count {
    if @execution.generated_sequence_step_index_at(sequence, index) ==
      Some(required_step) {
      if position >= 0 {
        return false
      }
      position = index
    }
  }
  guard position >= 0 &&
    @execution.select_generated_sequence_step(sequence, required_step)
    is Some(selected) else {
    return false
  }
  let matches = match
    @execution.generated_sequence_step_at(sequence, position) {
    Some(@lower.RowStep(kernel)) =>
      match check {
        Group =>
          (match @lower.kernel_group(kernel) {
            Some(group) =>
              @execution.group_execution_supported_with_numeric(group)
            None => false
          }) ||
          @lower.kernel_count_group(kernel) is Some(_)
        Analytic =>
          match @lower.kernel_analytic(kernel) {
            Some(analytic) =>
              @execution.analytic_execution_supported_with_numeric(analytic)
            None => false
          }
        Pivot =>
          match @lower.kernel_pivot(kernel) {
            Some(pivot) =>
              @execution.pivot_execution_supported_with_numeric(pivot)
            None => false
          }
        RowWindow => false
        TopK =>
          match @lower.kernel_body(kernel) {
            @lower.TopK(_, _) | @lower.PartitionedTopK(_, _) => true
            _ => false
          }
        Lag => @lower.kernel_body(kernel) is @lower.Lag(_, _)
        JsonPick => @lower.kernel_body(kernel) is @lower.JsonPick(_, _, _)
        Watermark => @lower.kernel_body(kernel) is @lower.Watermark(_, _, _, _)
        Dedupe => @lower.kernel_body(kernel) is @lower.DedupeRows
        Assertion =>
          match @lower.kernel_body(kernel) {
            @lower.AssertAll(_) | @lower.AssertUnique(_) => true
            _ => false
          }
        Expansion =>
          match @lower.kernel_body(kernel) {
            @lower.Unpivot(_, _, _, _) | @lower.Unnest(_, _, _, _, _) => true
            _ => false
          }
      }
    Some(@lower.WindowStep(_)) => check is RowWindow
    _ => false
  }
  if !matches {
    return false
  }
  for provider in installed.managed_providers {
    if managed_provider_accepts(provider, sequence) {
      return false
    }
  }
  if count > 1 &&
    !managed_provider_accepts(
      selected_relation_provider(
        installed.execution,
        installed.measurement,
        family=installed.managed_providers,
      ),
      sequence,
    ) {
    return false
  }
  bounded_relation_step_provider(
    selected,
    installed.execution,
    installed.measurement,
  )
  is Some(_)
}

///|
pub fn local_module_bounded_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
  check : LocalBoundedRelationCheck,
) -> Bool {
  local_bounded_relation_check(installed, slot, step, check)
}

///|
/// Nest output checks belong to the exact bounded child of the selected task.
/// A family provider cannot discharge these retained Relation obligations.
pub fn local_module_bounded_nest_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    local_sequence_contains_exact_step(sequence, step) &&
    @execution.select_generated_sequence_step(sequence, step) is Some(selected) &&
    @execution.generated_sequence_step_at(selected, 0)
    is Some(@lower.NestStep(_)) else {
    return false
  }
  for provider in installed.managed_providers {
    if managed_provider_accepts(provider, sequence) {
      return false
    }
  }
  if @execution.generated_sequence_step_count(sequence) > 1 &&
    !managed_provider_accepts(
      selected_relation_provider(
        installed.execution,
        installed.measurement,
        family=installed.managed_providers,
      ),
      sequence,
    ) {
    return false
  }
  let provider = nest_provider(installed.execution, installed.measurement)
  managed_provider_accepts(provider, selected) &&
  managed_provider_capacity(provider, selected) is Some(_)
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
  let relation = selected_relation_provider(execution, measurement, family~)
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
/// Exact output kind of the installed physical task, including a selected
/// prefix whose target differs from the final Stage target.
pub fn local_module_sequence_outputs_carrier(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_sequence_outputs_carrier(sequence)
}

///|
pub fn local_module_sequence_contains_carrier_step(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_sequence_contains_carrier_step(sequence)
}

///|
pub fn local_module_sequence_has_carrier_input(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_sequence_has_carrier_input(sequence)
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
  expansion_output_ceilings? : Array[(Int, Int64)] = [],
  session_output_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
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
    expansion_output_ceilings~,
    session_output_ceilings~,
    interval_search_ceilings~,
    asof_search_ceilings~,
    sequence_match_ceilings~,
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
