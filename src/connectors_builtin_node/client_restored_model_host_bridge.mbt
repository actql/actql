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
