///|
/// The actual completed restored Model execution is the sole output issuer.
/// Retain the original OutputUse before this call and until this Host retires;
/// releasing it neither closes the Model owner nor acknowledges physical stop.
#export_name("clientProgramInstalledEffectManagedRestoredModelHostOpen")
pub fn client_program_installed_effect_managed_restored_model_host_open(
  owner : @client_local_host.ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  held : @infer_host.OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  ClientLocalEffectHost?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard @infer_host.borrow_original_restored_host_output(
      held, compiled, definition, graph,
    )
    is Some((output, completed_model)) else {
    return Err(ForeignOriginal)
  }
  // The caller already owns held before this fallible boundary. An exception,
  // rejection or absent Host cannot orphan the output pin or authorize replay.
  @client_local_host.open_installed_effect_retained_model_host(
    owner, bound, sources, compiled, definition, graph, output, completed_model,
  ).map(value => {
    value.map(tuple => {
      let (host, run, sequences) = tuple
      { host, run, prepared: bound, sequences, }
    })
  })
}

///|
/// The original parent, not absence of a returned Host, owns partial cleanup.
#export_name("clientProgramRetireInstalledEffectCapturedConsumers")
pub fn client_program_retire_installed_effect_captured_consumers(
  owner : @client_local_host.ClientInstalledManagedRun,
) -> Result[Bool, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.retire_installed_effect_captured_consumers(owner)
}

///|
/// Project authenticated original Source evidence from this same Saved scope.
/// No Source observation, logical identity or capture is issued here.
#export_name("clientProgramRestoredInferSourceOriginals")
pub fn client_program_restored_infer_source_originals(
  scope : @publication_host.ClientInferSavedCallScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  Array[(@publication.RunEvidenceValue, @publication.RunEvidenceValue)],
  @publication_host.ClientInferCallScopeIssue,
] {
  @publication_host.client_infer_saved_source_originals(
    scope, compiled, definition, occurrence, graph,
  )
}
