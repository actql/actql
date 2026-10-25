///|
// Keep the original Host scope opaque. The only borrowed Ledger receiver is
// the existing synchronous prefix constructor, not an arbitrary executor or
// callback. The installing Host must fund derivation/backing/control overlap
// before this call; this connection supplies no numeric layout or permission.
pub fn start_client_original_serialization_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
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
  let ledger = match
    @publication_host.borrow_client_original_serialization_ledger(
      scope, compiled, definition, plan, prepared, task, step,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  start_client_serialization_prefix(
    prepared,
    task,
    step,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    execution,
    measurement,
    ledger,
    workspace~,
  )
}
