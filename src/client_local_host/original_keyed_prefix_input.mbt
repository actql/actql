///|
// Closed borrowed view of the existing managed prefix, only for this path.
// These seven references/control slots and completion overlap require original
// bootstrap funding; this record provides no numeric normal-profile supplier.
struct ClientOriginalKeyedPrefixInput {
  mut prefix : ClientSerializationPrefix?
  mut scope : @publication_host.ClientModelReadScope?
  mut keyed : @publication_host.ClientKeyedAcquisition?
  mut source : @query.CapturedInputSource?
  mut input : @execution.ProducerRead?
  mut output : @execution.CompletedOutput?
  mut lookup : @publication_host.ClientOriginalKeyedPrefixLookup?
}

///|
pub fn start_client_original_keyed_prefix_input(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  capture : @row_source_host.RowSourceCapture,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_entries : Int,
  max_name_bytes : Int,
  workspace? : @execution.ExecutionCapacity? = None,
) -> Result[ClientOriginalKeyedPrefixInput, ClientSerializationPrefixIssue] {
  start_client_original_keyed_left_prefix_owned(
    scope, compiled, definition, plan, prepared, keyed, capture, installed_contracts,
    values_body, fragment_body, ordered_body, execution, measurement, max_entries,
    max_name_bytes, workspace,
  ).map(tuple => {
    let (prefix, source, input) = tuple
    {
      prefix: Some(prefix),
      scope: Some(scope),
      keyed: Some(keyed),
      source: Some(source),
      input: Some(input),
      output: None,
      lookup: None,
    }
  })
}

///|
pub fn advance_client_original_keyed_prefix_input(
  value : ClientOriginalKeyedPrefixInput,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  guard value.prefix is Some(prefix) else {
    return Ok(@local.managed_provider_stopped_poll(0L, 0L))
  }
  let poll = match advance_client_serialization_prefix(prefix, quantum) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if poll is @local.Complete(output, ..) {
    guard value.input is Some(input) &&
      @execution.retain_completed_segment_input(output, input) is Some(retained) else {
      return Err(@connector.Execution(@execution.InputSet))
    }
    // The only donor is this actual managed execution and the exact read it
    // received at start. Keep the underlying terminal poll and work unchanged.
    value.output = Some(retained)
  }
  Ok(poll)
}

///|
pub fn cleanup_client_original_keyed_prefix_input(
  value : ClientOriginalKeyedPrefixInput,
) -> Result[Bool, ClientSerializationPrefixIssue] {
  guard value.prefix is Some(prefix) else { return Ok(true) }
  if (
      value.lookup is Some(lookup) &&
      @publication_host.client_original_keyed_prefix_lookup_input(lookup)
      is Some(_)
    ) ||
    (
      !prefix.released &&
      !@resources.original_keyed_prefix_dependents_retired(
        prefix.ledger,
        prefix.reservation,
      )
    ) {
    return Ok(false)
  }
  let complete = match cleanup_client_serialization_prefix(prefix) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if complete {
    value.output = None
    value.scope = None
    value.keyed = None
    value.source = None
    value.input = None
    value.lookup = None
    value.prefix = None
  }
  Ok(complete)
}

///|
// This capability-free view can expose only the actual prefix completion.
// A retired/foreign prefix cannot supply an equal-looking replacement output.
pub fn start_client_original_keyed_prefix_lookup_input(
  value : ClientOriginalKeyedPrefixInput,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  capture : @row_source_host.RowSourceCapture,
  max_entries : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_work : Int,
) -> Result[
  @publication_host.ClientOriginalKeyedPrefixLookup,
  ClientOriginalKeyedLookupIssue,
] {
  guard value.scope is Some(original_scope) &&
    physical_equal(original_scope, scope) &&
    value.keyed is Some(original_keyed) &&
    physical_equal(original_keyed, keyed) &&
    value.source is Some(source) &&
    value.input is Some(input) &&
    value.lookup is None &&
    value.prefix is Some(prefix) &&
    !prefix.child_cleaned &&
    !prefix.released &&
    value.output is Some(output) &&
    @row_source_host.row_capture_original_prefix_requirement(
      capture,
      prefix.ledger,
      prefix=Some(prefix.reservation),
    )
    is Some(_) else {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  let retained = @execution.restrict_completed_output(output, () => {
    value.prefix is Some(current) &&
    !current.child_cleaned &&
    !current.released &&
    @resources.reservation_open(current.reservation) &&
    value.source is Some(source) &&
    @query.captured_source_available(source)
  })
  @publication_host.start_client_original_keyed_prefix_lookup(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    source,
    retained,
    input,
    prefix.reservation,
    max_entries,
    max_name_bytes,
    max_bytes,
    max_work,
  )
  .map(lookup => {
    value.lookup = Some(lookup)
    lookup
  })
  .map_err(issue => Lookup(issue))
}
