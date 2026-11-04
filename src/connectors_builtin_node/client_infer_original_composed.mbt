///|
/// Same-original fixed consumer bounds DATA for the selected Root's separate
/// complete recipe. It issues no operational purpose, capacity or permission.
#export_name("clientProgramOriginalComposedInferBounds")
pub fn client_program_original_composed_infer_bounds(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[@infer_host.Limits, @infer_host.Issue] {
  original_composed_model_limits(compiled, definition, occurrence, graph)
}

///|
// The existing late consumers retain their exact refusal order and one
// selection. New prepared callers retain bounds before Run construction and
// invoke only the separate original binding port at the later boundary.
fn original_composed_model_limits(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[@infer_host.Limits, @infer_host.Issue] {
  match
    @infer_host.check_original_composed_preparation(
      compiled, definition, occurrence, graph,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  @infer_host.prepared_composed_bounds(occurrence, graph)
}

///|
#export_name("clientProgramPreparedComposedInferBounds")
pub fn client_program_prepared_composed_infer_bounds(
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[@infer_host.Limits, @infer_host.Issue] {
  @infer_host.prepared_composed_bounds(occurrence, graph)
}

///|
#export_name("clientProgramCheckOriginalComposedInferPreparation")
pub fn client_program_check_original_composed_infer_preparation(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.check_original_composed_preparation(
    compiled, definition, occurrence, graph,
  )
}

///|
/// Reattach authenticated saved input to the same original Model consumer.
/// The saved scope is checked by the existing Core owner before input starts.
#export_name("clientProgramStartOriginalRestoredComposedInferExecution")
pub fn client_program_start_original_restored_composed_infer_execution(
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  prefix : @execution.GeneratedSequence,
  provider : @model.ModelProvider,
  binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  saved_scope : @publication_host.ClientInferSavedCallScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  consumer : @publication_host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  reference_issuer : @admitted.ReferenceIssuer?,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_original_restored_composed(
    occurrence,
    graph,
    prefix,
    provider,
    binding,
    descriptor_wire,
    rows,
    custody_available,
    saved_scope,
    @infer_host.standard_limits(),
    compiled,
    definition,
    consumer,
    read_retained_bytes,
    read_execution_bytes,
    model_retained_bytes,
    model_execution_bytes,
    reference_issuer?,
  )
}

///|
/// Thin same-Owner composed input connection. The actual installation supplies
/// the original consumer and complete overlap; this entry issues no resources,
/// Model IO access, Account permission or dispatch admission.
#export_name("clientProgramStartOriginalComposedInferExecution")
pub fn client_program_start_original_composed_infer_execution(
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  prefix : @execution.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  provider : @model.ModelProvider,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  consumer : @publication_host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  sources : @publication_host.ClientInferComposedSources?,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_original_composed(
    occurrence,
    graph,
    prefix,
    inputs,
    provider,
    @infer_host.standard_limits(),
    compiled,
    definition,
    consumer,
    read_retained_bytes,
    read_execution_bytes,
    model_retained_bytes,
    model_execution_bytes,
    sources~,
  )
}
