///|
// Keep the original accounted capture alive until prefix cleanup succeeds,
// as required by the existing acquired-prefix Owner. This adapter creates no
// replacement capture, input, Ledger, ReferenceIssuer or Model send grant.
// Trusted bootstrap must already cover constructor/borrow/control overlap;
// no numeric normal-profile or public startup is supplied here.
pub fn start_client_original_captured_serialization_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  capture : @row_source_host.RowSourceCapture,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace? : @execution.ExecutionCapacity? = None,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  let source = match @row_source_host.row_capture_source(capture) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let ledger = match
    @publication_host.borrow_client_original_captured_prefix_ledger(
      scope, compiled, definition, plan, prepared, task, step, source,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  // Authenticate the original capture before deriving input bindings. The
  // existing acquired constructor checks it again after binding callbacks and
  // immediately before reserving its attempt on this same Ledger.
  guard @row_source_host.row_capture_original_prefix_requirement(
      capture, ledger,
    )
    is Some(_) else {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  start_client_acquired_serialization_prefix_owned(
    prepared,
    task,
    step,
    source,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    execution,
    measurement,
    ledger,
    workspace,
    None,
    Some(capture),
  )
}
