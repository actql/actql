///|
// Only JOIN and its checked downstream serialization-input/sort operations.
// The original completed left prefix and Source acquisition are not replayed.
fn original_keyed_serialization_suffix_provider(
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> (
  @execution.GeneratedSequence,
  @local.ManagedProvider,
  @execution.ExecutionCapacity,
)? {
  guard @publication_host.client_keyed_acquisition_matches_program(
      keyed, prepared,
    ) &&
    @publication_host.client_keyed_acquisition_coordinates(keyed)
    is Some((_, actual_task, join)) &&
    actual_task == task &&
    join < step &&
    prepare_client_serialization_prefix_owned(
      Pure(prepared),
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(prefix) &&
    @execution.generated_sequence_step_count(prefix) > 0 &&
    @execution.generated_sequence_step_index_at(
      prefix,
      @execution.generated_sequence_step_count(prefix) - 1,
    )
    is Some(terminal) &&
    terminal >= join &&
    @execution.select_generated_sequence_range(prefix, join, terminal)
    is Some(sequence) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return None
  }
  Some((sequence, provider, capacity))
}

///|
pub fn client_original_keyed_serialization_suffix_capacity(
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> @execution.ExecutionCapacity? {
  original_keyed_serialization_suffix_provider(
    prepared, keyed, task, step, installed_contracts, values_body, fragment_body, ordered_body,
    execution, measurement,
  ).map(value => value.2)
}

///|
// Borrow the actual completed left and key-set through the same original
// Scope before the existing managed provider's reserve-before-start. Bootstrap
// selection/control and simultaneous encoding workspace still need funding;
// this private entry supplies no normal numeric profile or I/O/send authority.
pub fn start_client_original_keyed_serialization_suffix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  value : @publication_host.ClientOriginalKeyedPrefixLookup,
  keyed : @publication_host.ClientKeyedAcquisition,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace? : @execution.ExecutionCapacity? = None,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  guard original_keyed_serialization_suffix_provider(
      prepared, keyed, task, step, installed_contracts, values_body, fragment_body, ordered_body,
      execution, measurement,
    )
    is Some((sequence, provider, capacity)) else {
    return Err(Unavailable)
  }
  let (ledger, left, right) = match
    @publication_host.borrow_client_original_keyed_serialization_inputs(
      scope, compiled, definition, plan, prepared, value, task, step, sequence,
    ) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  start_serialization_prefix_provider(
    sequence,
    provider,
    capacity,
    [
      @local.managed_provider_relation_input(left),
      @local.managed_provider_supplied_relation_input(right),
    ],
    execution,
    measurement,
    ledger,
    workspace,
  )
}
