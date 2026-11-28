///|
fn original_composed_source_matches(
  occurrence : @publication_host.ClientInferOccurrence,
  sources : @publication_host.ClientInferComposedSources?,
) -> Bool {
  match sources {
    Some(original) =>
      @publication_host.client_infer_composed_sources_matches(
        original, occurrence,
      )
    None =>
      !@publication_host.client_infer_occurrence_has_captured_sources(
        occurrence,
      )
  }
}

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
  if !original_composed_source_matches(occurrence, sources) {
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
  let identity_body = match
    prepare_original_infer_identity_body(
      input_body_read, consumer, compiled, definition, plan, read_retained_bytes,
      read_execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
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
    active.identity_body = identity_body

    active
  })
}

///|
/// Start the installed Chat component with the original managed prefix and
/// its Scope. The Host retains that exact Read even if claim or startup
/// refuses. No Entry, transport or dispatch is opened by this operation.
pub fn start_scoped_portable_chat_composed(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  prefix : @relation.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  admitted : @model.AdmittedStructuredModelProvider,
  installation : @environment.ModelResponseProfileInstallation,
  limits : Limits,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  scope : @publication_host.ClientModelReadScope,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  retain_read : (@publication_host.ClientModelReadPreparation) -> Unit,
  sources? : @publication_host.ClientInferComposedSources? = None,
  prior_input_work? : Int64 = 0L,
) -> Result[Execution, Issue] {
  guard physical_equal(plan.occurrence, occurrence) &&
    original_composed_source_matches(occurrence, sources) &&
    @model.admitted_model_http_chat_provider(
      admitted,
      @publication_host.client_infer_plan_graph_execution_contract(plan),
      installation,
    )
    is Some(provider) else {
    return Err(OriginalCapacity(@publication_host.ForeignInput))
  }
  let (read, consumer) = match
    @publication_host.prepare_claimed_client_model_read(
      scope, compiled, definition, plan, read_retained_bytes, read_execution_bytes,
      retain_read,
    ) {
    Err(issue) => return Err(OriginalCapacity(@publication_host.Read(issue)))
    Ok(value) => value
  }
  start_original_composed(
    occurrence,
    plan,
    prefix,
    inputs,
    provider,
    limits,
    compiled,
    definition,
    consumer,
    read_retained_bytes,
    read_execution_bytes,
    model_retained_bytes,
    model_execution_bytes,
    sources~,
    prior_input_work~,
    input_body_read=Some(read),
  )
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
  let identity_body = match
    prepare_original_infer_identity_body(
      input_body_read, consumer, compiled, definition, plan, read_retained_bytes,
      read_execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The existing retained-input owner checks binding, descriptor, rows and
  // current custody. Failure keeps the same entered consumer for cleanup.
  let original_read = identity_body.map(body => {
    (
      input_body_read.unwrap(),
      consumer,
      compiled,
      definition,
      plan,
      Ref((body.retained, body.execution)),
    )
  })
  let started = start_restored_composed_input(
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
    original_read~,
  )
  // A failed constructor still leaves its actual Resource growth retained.
  if identity_body is Some(body) && original_read is Some((_, _, _, _, _, held)) {
    body.retained = held.val.0
    body.execution = held.val.1
  }
  started.map(active => {
    retain_original_model_preparation(
      active,
      compiled,
      definition,
      consumer,
      model_retained_bytes,
      model_execution_bytes,
      shared_mock=true,
    )
    active.identity_body = identity_body

    active
  })
}

///|
/// Observe the same opened Whole Model on its original composed Run. The
/// constructor already validated the complete Source tuple before claiming
/// the Read. This immutable comparison is safe inside the Journal cut.
pub fn original_whole_model_journal_matches(
  active : Execution,
  plan : @publication_host.ClientInferPlanGraph,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  !active.reclaimed &&
  active.original_preparation is Some({ read: Claimed(_), .. }) &&
  active.run_binding is Some(binding) &&
  physical_equal(binding.compiled, compiled) &&
  physical_equal(binding.definition, definition) &&
  active.plan is Some(original_plan) &&
  physical_equal(original_plan, plan) &&
  active.composed_sources is Some(sources) &&
  @publication_host.client_infer_composed_whole_sources_original(
    sources,
    active.occurrence,
  )
}
