///|
#export_name("clientProgramEffectComposedModelKeyedAcquisition")
pub fn client_program_effect_composed_model_keyed_acquisition(
  prepared : @publication_host.PreparedClientEffectComputation,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[
  @publication_host.ClientKeyedAcquisition?,
  @publication_host.ClientKeyedAcquisitionIssue,
] {
  @publication_host.select_client_effect_composed_model_keyed_acquisition(
    prepared, plan,
  )
}

///|
#export_name("clientProgramStartOriginalComposedKeyedPrefix")
pub fn client_program_start_original_composed_keyed_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@client_row_source_host.RowSourceCapture],
  input_prefix : @execution.GeneratedSequence,
) -> Result[
  @client_local_host.ClientOriginalComposedKeyedPrefix,
  @client_local_host.ClientSerializationPrefixIssue,
] {
  let limits = @infer_host.standard_limits()
  @client_local_host.start_client_original_composed_keyed_prefix(
    scope,
    compiled,
    definition,
    plan,
    keyed,
    rows,
    input_prefix,
    limits.input,
    limits.measurement,
  )
}

///|
#export_name("clientProgramStartInstalledOriginalComposedKeyedPrefix")
pub fn client_program_start_installed_original_composed_keyed_prefix(
  owner : @client_local_host.ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@client_row_source_host.RowSourceCapture],
) -> Result[
  @client_local_host.ClientOriginalComposedKeyedPrefix,
  @client_local_host.ClientSerializationPrefixIssue,
] {
  let limits = @infer_host.standard_limits()
  @client_local_host.start_installed_original_composed_keyed_prefix(
    owner,
    scope,
    compiled,
    definition,
    plan,
    keyed,
    rows,
    limits.input,
    limits.measurement,
  )
}

///|
#export_name("clientProgramOriginalComposedKeyedPrefixExecution")
pub fn client_program_original_composed_keyed_prefix_execution(
  value : @client_local_host.ClientOriginalComposedKeyedPrefix,
) -> @client_local_host.ClientSerializationPrefix {
  @client_local_host.client_original_composed_keyed_prefix_execution(value)
}

///|
#export_name("clientProgramCompleteOriginalComposedKeyedPrefix")
pub fn client_program_complete_original_composed_keyed_prefix(
  value : @client_local_host.ClientOriginalComposedKeyedPrefix,
) -> Result[
  @publication_host.ClientKeyedLeftRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @client_local_host.complete_client_original_composed_keyed_prefix(
    value, 100000, 1000000,
  )
}

///|
#export_name("clientProgramOriginalComposedKeyedPrefixAdvance")
pub fn client_program_original_composed_keyed_prefix_advance(
  value : @client_local_host.ClientOriginalComposedKeyedPrefix,
  quantum : Int,
) -> Result[
  (Bool, Bool, @connector.FixedComputeIssue?),
  @connector.FixedComputeIssue,
] {
  @client_local_host.advance_client_original_composed_keyed_prefix(
    value, quantum,
  ).map(poll => {
    match poll {
      Complete(_, ..) => (true, true, None)
      Continue(..) | Waiting(..) | Settling(_, ..) => (false, false, None)
      Failed(issue, ..) => (false, true, Some(issue))
      Stopped(..) => (false, true, None)
      CarrierComplete(_, ..) =>
        (false, true, Some(@connector.Execution(@execution.InputSet)))
    }
  })
}

///|
#export_name("clientProgramInstalledEffectManagedKeyedHostOpen")
pub fn client_program_installed_effect_managed_keyed_host_open(
  owner : @client_local_host.ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[
  ClientLocalEffectHost?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.open_installed_effect_managed_keyed_host(
    owner, bound, sources, lookup,
  ).map(value => {
    value.map(tuple => {
      let (host, run, sequences) = tuple
      { host, run, prepared: bound, sequences, }
    })
  })
}

///|
#export_name("clientProgramComposedKeyedFileLocatorStart")
pub fn client_program_composed_keyed_file_locator_start(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
  sources : Array[@query.CapturedInputSource],
  reads : Array[@execution.SuppliedRelationRead?],
) -> Result[
  @publication_host.ClientKeyedFileLocator,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.start_client_composed_keyed_file_locator(
    lookup, request, sources, reads,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedDeferredKeyedHostOpen")
pub fn client_program_installed_effect_managed_deferred_keyed_host_open(
  owner : @client_local_host.ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  ClientLocalEffectHost?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.open_installed_effect_managed_deferred_keyed_host(
    owner, bound, sources,
  ).map(value => {
    value.map(tuple => {
      let (host, run, sequences) = tuple
      { host, run, prepared: bound, sequences, }
    })
  })
}

///|
#export_name("clientProgramStartInstalledOriginalComposedKeyedHostPrefix")
pub fn client_program_start_installed_original_composed_keyed_host_prefix(
  owner : @client_local_host.ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@client_row_source_host.RowCapturedInput],
  host : ClientLocalEffectHost,
) -> Result[
  @client_local_host.ClientOriginalComposedKeyedPrefix,
  @client_local_host.ClientSerializationPrefixIssue,
] {
  let limits = @infer_host.standard_limits()
  @client_local_host.start_installed_original_composed_keyed_host_prefix(
    owner,
    scope,
    compiled,
    definition,
    plan,
    keyed,
    rows,
    host.run,
    limits.input,
    limits.measurement,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedKeyedHostBind")
pub fn client_program_installed_effect_managed_keyed_host_bind(
  owner : @client_local_host.ClientInstalledManagedRun,
  host : ClientLocalEffectHost,
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.bind_installed_effect_managed_keyed_host(
    owner,
    host.run,
    lookup,
  )
}

///|
#export_name("clientProgramInstalledOriginalComposedKeyedHostInputLeft")
pub fn client_program_installed_original_composed_keyed_host_input_left(
  owner : @client_local_host.ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@client_row_source_host.RowCapturedInput],
  host : ClientLocalEffectHost,
) -> Result[
  @publication_host.ClientKeyedLeftRead?,
  @publication_host.ClientKeyedRequestIssue,
] {
  @client_local_host.prepare_installed_original_composed_keyed_host_input_left(
    owner,
    scope,
    compiled,
    definition,
    plan,
    keyed,
    rows,
    host.run,
    100000,
    1000000,
  )
}
