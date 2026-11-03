///|
/// One original Content family selected before the Effect managed Plan. The
/// existing task dispatch quotes and starts this same provider; this creates
/// neither a prefix attempt nor a second Ledger or physical cleanup owner.
struct ClientInstalledEffectContentPreparation {
  prepared : @publication_host.PreparedClientEffectComputation
  compiled : @publication_host.ClientCompiledRun
  compilation : @publication_host.ClientEffectCompilation
  definition : @publication.PublicationContract
  component : @publication_host.ClientSerializationPlanGraph
  provider : @local.ManagedProvider
  reference_nodes : Int
  reference_bytes : Int
}

///|
fn installed_effect_content_preparation_matches(
  original : ClientInstalledEffectContentPreparation,
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Bool {
  physical_equal(original.prepared, prepared) &&
  @publication_host.client_compiled_run_matches_effect(
    original.compiled,
    prepared,
    original.compilation,
  ) &&
  @publication_host.check_client_compiled_run_definition(
    original.compiled,
    original.definition,
  )
  is Ok(_) &&
  @strategy.graph_captured_prefix(
    installed_managed_owner_graph(Effect(prepared)),
  ) ==
  0 &&
  @publication_host.prepared_client_effect_infer_occurrence(prepared) is None &&
  @publication_host.prepared_client_effect_serialization_occurrences(prepared) ==
  [(original.component.task, original.component.step)]
}

///|
pub fn prepare_installed_effect_content(
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientCompiledRun,
  compilation : @publication_host.ClientEffectCompilation,
  definition : @publication.PublicationContract,
  component : @publication_host.ClientSerializationPlanGraph,
  contracts : ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : ClientSerializationWorkspaceLimits,
  physical : ClientLocalContentPhysicalPort,
  retain : (ClientLocalContentStep) -> Bool,
) -> Result[
  ClientInstalledEffectContentPreparation,
  ClientInstalledManagedRunIssue,
] {
  guard @publication_host.client_compiled_run_matches_effect(
      compiled, prepared, compilation,
    ) &&
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Ok(_) &&
    @publication_host.client_compiled_run_serialization(compiled)
    is Some(actual) &&
    physical_equal(actual, component) else {
    return Err(ForeignOriginal)
  }
  if @strategy.graph_captured_prefix(
      installed_managed_owner_graph(Effect(prepared)),
    ) !=
    0 ||
    @publication_host.prepared_client_effect_infer_occurrence(prepared)
    is Some(_) ||
    @publication_host.prepared_client_effect_serialization_occurrences(prepared) !=
    [(component.task, component.step)] {
    return Err(Unsupported)
  }
  guard client_effect_content_local_provider(
      prepared,
      component.task,
      component.step,
      contracts,
      values,
      fragment,
      ordered,
      execution,
      measurement,
      workspace,
      physical,
      retain,
    )
    is Some(provider) else {
    return Err(Unsupported)
  }
  Ok({
    prepared,
    compiled,
    compilation,
    definition,
    component,
    provider,
    reference_nodes: workspace.reference_nodes,
    reference_bytes: workspace.reference_bytes,
  })
}

///|
pub fn installed_effect_content_provider(
  original : ClientInstalledEffectContentPreparation,
) -> @local.ManagedProvider {
  original.provider
}
