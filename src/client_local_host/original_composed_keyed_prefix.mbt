///|
// The existing managed prefix with its borrowed original port inventory.
// There is no second executor, admission or Ledger in this composition.
struct ClientOriginalComposedKeyedPrefix {
  prefix : ClientSerializationPrefix
  scope : @publication_host.ClientModelReadScope
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  plan : @publication_host.ClientInferPlanGraph
  keyed : @publication_host.ClientKeyedAcquisition
  sources : Array[@query.CapturedInputSource]
  captures : @row_source_host.RowCapturedInputs
  sequence : @execution.GeneratedSequence
  inputs : Array[(Int, Int, @execution.ProducerRead)]
  mut output : @execution.CompletedOutput?
  mut left : @publication_host.ClientKeyedLeftRead?
}

///|
pub fn start_client_original_composed_keyed_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowSourceCapture],
  input_prefix : @execution.GeneratedSequence,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  let inputs = rows.filter_map(@row_source_host.row_capture_input)
  if inputs.length() != rows.length() {
    return Err(Unavailable)
  }
  start_client_original_composed_keyed_prefix_owned(
    scope,
    compiled,
    definition,
    plan,
    keyed,
    inputs,
    input_prefix,
    execution,
    measurement,
    None,
  )
}

///|
// The shared ordinary Effect Run already owns its finite sequence and its
// one prefix slot. A failed constructor stays attached to that SAME owner.
pub fn start_installed_original_composed_keyed_input_prefix(
  owner : ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowCapturedInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  if owner.source_free_opening || owner.serialization_prefix is Some(_) {
    return Err(Unavailable)
  }
  owner.source_free_opening = true
  preparation_module_call(
    () => {
      guard require_installed_managed_run(owner) is Ok(_) &&
        owner.preparation is Some(PlannedEffectManaged(_, selected)) &&
        selected.model is Some(model) &&
        physical_equal(model.compiled, compiled) &&
        physical_equal(model.definition, definition) &&
        physical_equal(model.graph, plan) else {
        return Err(Unavailable)
      }
      let (task, _, _) = @publication_host.client_infer_occurrence_coordinates(
        model._occurrence,
      )
      guard selected.sequences.get(task) is Some(input_prefix) else {
        return Err(Unavailable)
      }
      start_client_original_composed_keyed_prefix_owned(
        scope,
        compiled,
        definition,
        plan,
        keyed,
        rows,
        input_prefix,
        execution,
        measurement,
        Some(owner),
      )
    },
    () => owner.source_free_opening = false,
  )
}

///|
fn start_client_original_composed_keyed_prefix_owned(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowCapturedInput],
  input_prefix : @execution.GeneratedSequence,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  installed : ClientInstalledManagedRun?,
  borrowed_inputs? : Bool = false,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  let selected = @publication_host.borrow_client_original_composed_keyed_input_captures(
    scope,
    compiled,
    definition,
    plan,
    keyed,
    rows,
    installed=borrowed_inputs || installed is Some(_),
  )
  let (ledger, captures, sources) = match selected {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  let owner = @publication_host.client_keyed_acquisition_owner(keyed)
  guard @publication_host.client_keyed_acquisition_coordinates(keyed)
    is Some((_, _, join)) &&
    @lower.node_at(@lower.bound_preparation(owner), join) is Some(node) &&
    @lower.node_input_target(node, 0) is Some(@pipeline.Step(left)) &&
    left >= 0 &&
    left < join &&
    @execution.select_generated_sequence_range(input_prefix, 0, left)
    is Some(sequence) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return Err(Unavailable)
  }
  let inputs = match
    @publication_host.prepare_client_original_composed_keyed_inputs(
      scope,
      compiled,
      definition,
      plan,
      keyed,
      sources,
      captures,
      sequence,
      execution.rows.operation_entries,
      measurement.max_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  let actual = inputs.map(value => {
    @local.managed_provider_relation_input(value.2)
  })
  // The existing constructor retains its reservation before calling the
  // provider. Both actual inputs stay borrowed until its real cleanup ACK.
  let started = match installed {
    None =>
      start_serialization_prefix_provider(
        sequence,
        provider,
        capacity,
        actual,
        execution,
        measurement,
        ledger,
        None,
      )
    Some(original) => {
      guard require_installed_managed_run(original) is Ok(parent) &&
        physical_equal(parent, ledger) &&
        original.serialization_prefix is None else {
        return Err(Unavailable)
      }
      let reservation = match
        @resources.reserve_attempt(
          ledger,
          0L,
          @execution.execution_capacity_retained_bytes(capacity),
          @execution.execution_capacity_execution_bytes(capacity),
          quantities=@resources.quantity_neutral_amounts(ledger),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Physical(issue))
      }
      let prefix = serialization_prefix_reservation(ledger, reservation)
      // The existing opening latch excludes retirement during reservation.
      // No callback follows retention before the fallible provider start.
      original.serialization_prefix = Some(prefix)
      start_retained_serialization_prefix_provider(
        prefix, sequence, provider, actual, execution, measurement,
      )
    }
  }
  started.map(prefix => {
    prefix,
    scope,
    compiled,
    definition,
    plan,
    keyed,
    sources: sources.copy(),
    captures,
    sequence,
    inputs,
    output: None,
    left: None,
  })
}

///|
pub fn client_original_composed_keyed_prefix_execution(
  value : ClientOriginalComposedKeyedPrefix,
) -> ClientSerializationPrefix {
  value.prefix
}

///|
pub fn advance_client_original_composed_keyed_prefix(
  value : ClientOriginalComposedKeyedPrefix,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  let poll = match advance_client_serialization_prefix(value.prefix, quantum) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if poll is @local.Complete(output, ..) {
    guard @execution.retain_completed_segment_inputs(
        output,
        value.sequence,
        value.inputs,
        100000,
      )
      is Some(retained) &&
      @execution.completed_segment_inputs_output(
        retained,
        value.sequence,
        value.inputs,
      )
      is Some(actual) else {
      return Err(@connector.Execution(@execution.InputSet))
    }
    value.output = Some(actual)
  }
  Ok(poll)
}

///|
pub fn complete_client_original_composed_keyed_prefix(
  value : ClientOriginalComposedKeyedPrefix,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[
  @publication_host.ClientKeyedLeftRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  if value.left is Some(_) {
    return Err(Assembly("original_prefix_already_bound"))
  }
  guard value.output is Some(output) else { return Err(ForeignLeft) }
  let work = match client_serialization_prefix_work(value.prefix) {
    Ok(value) => value
    Err(_) => return Err(Assembly("prefix_work_unavailable"))
  }
  @publication_host.prepare_client_original_composed_keyed_left(
    value.scope,
    value.compiled,
    value.definition,
    value.plan,
    value.keyed,
    value.sources,
    value.captures,
    value.sequence,
    value.inputs,
    output,
    value.prefix.reservation,
    work,
    max_entries,
    max_name_bytes,
  ).map(left => {
    value.left = Some(left)
    left
  })
}

///|
pub fn start_installed_original_composed_keyed_prefix(
  owner : ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowSourceCapture],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  let inputs = rows.filter_map(@row_source_host.row_capture_input)
  if inputs.length() != rows.length() {
    return Err(Unavailable)
  }
  start_installed_original_composed_keyed_input_prefix(
    owner, scope, compiled, definition, plan, keyed, inputs, execution, measurement,
  )
}
