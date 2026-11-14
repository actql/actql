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
  input_body_read? : @publication_host.ClientModelReadPreparation? = None,
  prior_input_work? : Int64 = 0L,
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
  start_composed(
    occurrence,
    plan,
    prefix,
    inputs,
    provider,
    limits,
    sources~,
    prior_input_work~,
  ).map(active => {
    retain_original_model_preparation(
      active,
      compiled,
      definition,
      consumer,
      model_retained_bytes,
      model_execution_bytes,
      shared_mock=true,
    )
    if input_body_read is Some(read) {
      // DATA continuation only. The same entered consumer authenticates this
      // exact original Read again at its first actual construction boundary.
      active.identity_body = Some({
        read,
        base_retained: read_retained_bytes,
        base_execution: read_execution_bytes,
        retained: read_retained_bytes,
        execution: read_execution_bytes,
      })
    }
    active
  })
}

///|
/// Restore authenticated input on the same already funded read consumer.
/// The saved call scope remains its original Run binding; it is not a new
/// dispatch grant, a replacement Ledger or permission to resend a call.
pub fn start_original_restored_composed(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  prefix : @relation.GeneratedSequence,
  provider : @model.ModelProvider,
  binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  saved_scope : @publication_host.ClientInferSavedCallScope,
  limits : Limits,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  consumer : @publication_host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  reference_issuer? : @admitted.ReferenceIssuer,
  input_body_read? : @publication_host.ClientModelReadPreparation? = None,
) -> Result[Execution, Issue] {
  if !@publication_host.client_infer_saved_call_scope_matches_run(
      saved_scope, compiled, definition,
    ) ||
    !@publication_host.client_infer_saved_call_scope_matches_occurrence(
      saved_scope, occurrence, plan,
    ) {
    return Err(CallScope(ForeignInput))
  }
  match
    enter_original_model_preparation(
      occurrence, compiled, definition, plan, consumer, read_retained_bytes, read_execution_bytes,
      model_retained_bytes, model_execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The existing retained-input owner checks binding, descriptor, rows and
  // current custody. Failure keeps the same entered consumer for cleanup.
  start_restored_composed_input(
    occurrence,
    plan,
    prefix,
    provider,
    binding,
    binding,
    descriptor_wire,
    rows,
    custody_available,
    limits,
    saved_scope=Some(saved_scope),
    reference_issuer?,
  ).map(active => {
    retain_original_model_preparation(
      active,
      compiled,
      definition,
      consumer,
      model_retained_bytes,
      model_execution_bytes,
      shared_mock=true,
    )
    if input_body_read is Some(read) {
      // Retain body bytes in the SAME first input identity scan. The existing
      // grow authenticates this Read and entered consumer before construction;
      // restoring a scope cannot replace that ownership or issue a new Read.
      active.identity_body = Some({
        read,
        base_retained: read_retained_bytes,
        base_execution: read_execution_bytes,
        retained: read_retained_bytes,
        execution: read_execution_bytes,
      })
    }
    active
  })
}
