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
  sequence : @execution.GeneratedSequence
  inputs : Array[(Int, Int, @execution.ProducerRead)]
}

///|
pub fn start_client_original_composed_keyed_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  sources : Array[@query.CapturedInputSource],
  input_prefix : @execution.GeneratedSequence,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  let ledger = match
    @publication_host.borrow_client_original_composed_keyed_ledger(
      scope, compiled, definition, plan, keyed, sources,
    ) {
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
  start_serialization_prefix_provider(
    sequence,
    provider,
    capacity,
    actual,
    execution,
    measurement,
    ledger,
    None,
  ).map(prefix => {
    prefix,
    scope,
    compiled,
    definition,
    plan,
    keyed,
    sources: sources.copy(),
    sequence,
    inputs,
  })
}

///|
pub fn client_original_composed_keyed_prefix_execution(
  value : ClientOriginalComposedKeyedPrefix,
) -> ClientSerializationPrefix {
  value.prefix
}

///|
pub fn complete_client_original_composed_keyed_prefix(
  value : ClientOriginalComposedKeyedPrefix,
  output : @execution.CompletedOutput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[
  @publication_host.ClientKeyedLeftRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.prepare_client_original_composed_keyed_left(
    value.scope,
    value.compiled,
    value.definition,
    value.plan,
    value.keyed,
    value.sources,
    value.sequence,
    value.inputs,
    output,
    value.prefix.reservation,
    max_entries,
    max_name_bytes,
  )
}
