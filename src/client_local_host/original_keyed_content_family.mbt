///|
// Reuse the ordinary checked sequence's real SerializationBoundary. Unlike
// the byte-only suffix, the existing Content family owns its internal sort,
// input identity, piece ACK and generation barrier inside the managed chain.
fn original_keyed_content_suffix_provider(
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
  workspace : ClientSerializationWorkspaceLimits,
  physical : ClientLocalContentPhysicalPort,
  retain : (ClientLocalContentStep) -> Bool,
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
    prepare_client_local_sequences(
      prepared,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      task_count=Some(task + 1),
    ).bind(sequences => sequences.get(task))
    is Some(original) &&
    @execution.select_generated_sequence_range(original, join, step)
    is Some(sequence) &&
    client_content_local_provider(
      prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
      execution, measurement, workspace, physical, retain,
    )
    is Some(family) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence, family=[
      family,
    ])
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return None
  }
  Some((sequence, provider, capacity))
}

///|
// A canonical Local family capacity query, not an installed physical normal
// profile. Preparation must be funded before invoking this factory itself.
pub fn client_original_keyed_content_suffix_capacity(
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
  workspace : ClientSerializationWorkspaceLimits,
  physical : ClientLocalContentPhysicalPort,
  retain : (ClientLocalContentStep) -> Bool,
) -> @execution.ExecutionCapacity? {
  original_keyed_content_suffix_provider(
    prepared, keyed, task, step, installed_contracts, values_body, fragment_body,
    ordered_body, execution, measurement, workspace, physical, retain,
  ).map(value => value.2)
}

///|
// The original Source/prefix/key-set loan and same Ledger remain the only
// receiver. Store operations and byte custody remain in the supplied existing
// Content physical port; no callback can issue a Model permission or ACK.
pub fn start_client_original_keyed_content_suffix(
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
  workspace : ClientSerializationWorkspaceLimits,
  physical : ClientLocalContentPhysicalPort,
  retain : (ClientLocalContentStep) -> Bool,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  guard original_keyed_content_suffix_provider(
      prepared, keyed, task, step, installed_contracts, values_body, fragment_body,
      ordered_body, execution, measurement, workspace, physical, retain,
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
    None,
  )
}
