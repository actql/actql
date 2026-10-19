///|
/// Enter the original read consumer before the existing composed input owner
/// allocates or advances. The Local driver retains its actual producer ports;
/// no serialization generation, replacement rows or second Ledger is invented.
pub fn start_original_composed(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  prefix : @relation.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  provider : @model.ModelProvider,
  limits : Limits,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  consumer : @publication_host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  sources? : @publication_host.ClientInferComposedSources? = None,
) -> Result[Execution, Issue] {
  if (
      sources is Some(value) &&
      !@publication_host.client_infer_composed_sources_matches(
        value, occurrence,
      )
    ) ||
    (
      @publication_host.client_infer_occurrence_has_captured_sources(occurrence) &&
      sources is None
    ) {
    return Err(OriginalCapacity(@publication_host.ForeignInput))
  }
  match
    enter_original_model_preparation(
      occurrence, compiled, definition, plan, consumer, read_retained_bytes, read_execution_bytes,
      model_retained_bytes, model_execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Any input refusal leaves this already-entered consumer with its existing
  // read/Scope cleanup owner. Never claim again or fall back to unowned start.
  start_composed(occurrence, plan, prefix, inputs, provider, limits, sources~).map(active => {
      retain_original_model_preparation(
        active, compiled, definition, consumer, model_retained_bytes, model_execution_bytes,
      )
      active
    },
  )
}
