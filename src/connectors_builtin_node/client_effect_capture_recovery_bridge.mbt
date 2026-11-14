///|
#export_name("clientProgramInstalledEffectCapturePreparedAvailable")
pub fn client_program_installed_effect_capture_prepared_available(
  owner : @client_local_host.ClientInstalledEffectCaptureRecovery,
) -> Bool {
  @client_local_host.installed_effect_capture_prepared_available(owner)
}

///|
#export_name("clientProgramAdmitInstalledEffectCapturedRun")
pub fn client_program_admit_installed_effect_captured_run(
  owner : @client_local_host.ClientInstalledEffectCaptureRecovery,
  wire : String,
) -> Result[
  @publication.PreparedCapturedEffectRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.admit_installed_effect_captured_run(owner, wire)
}

///|
#export_name("clientProgramReserveInstalledEffectCaptureEncrypted")
pub fn client_program_reserve_installed_effect_capture_encrypted(
  owner : @client_local_host.ClientInstalledEffectCaptureRecovery,
  bytes : Int,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.reserve_installed_effect_capture_encrypted(owner, bytes)
}

///|
#export_name("clientProgramReserveInstalledEffectCaptureEnvelope")
pub fn client_program_reserve_installed_effect_capture_envelope(
  owner : @client_local_host.ClientInstalledEffectCaptureRecovery,
  wire : String,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.reserve_installed_effect_capture_envelope(owner, wire)
}

///|
#export_name("clientProgramReserveRequestEffectCaptureEncrypted")
pub fn client_program_reserve_request_effect_capture_encrypted(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_effect_capture_encrypted(
    parent, input, request, definition, bytes, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramReserveRequestEffectCaptureEnvelope")
pub fn client_program_reserve_request_effect_capture_envelope(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_effect_capture_envelope(
    parent, input, request, definition, wire,
  )
}

///|
#export_name("clientProgramReserveRequestEffectCaptureDecoded")
pub fn client_program_reserve_request_effect_capture_decoded(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_effect_capture_decoded(
    parent, input, request, definition, wire,
  )
}

///|
#export_name("clientProgramAdmitRequestEffectCapturedRun")
pub fn client_program_admit_request_effect_captured_run(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[
  @publication.PreparedCapturedEffectRun,
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.admit_request_effect_captured_run(
    parent, input, request, definition, wire,
  )
}

///|
#export_name("clientProgramRecoveredEffectCapturedRunContract")
pub fn client_program_recovered_effect_captured_run_contract(
  value : @publication.PreparedCapturedEffectRun,
) -> @publication.PublicationContract {
  @publication.prepared_captured_effect_run_contract(value)
}

///|
#export_name("clientProgramRecoveredEffectCapturedRunLimits")
pub fn client_program_recovered_effect_captured_run_limits(
  value : @publication.PreparedCapturedEffectRun,
) -> (Int, Int, Int) {
  @publication.prepared_captured_effect_run_limits(value)
}

///|
#export_name("clientProgramRecoveredEffectCapturedRunSchemas")
pub fn client_program_recovered_effect_captured_run_schemas(
  value : @publication.PreparedCapturedEffectRun,
) -> Array[(String, String)] {
  @publication.prepared_captured_effect_run_schemas(value)
}

///|
#export_name("clientProgramRecoveredEffectCapturedRunPayloads")
pub fn client_program_recovered_effect_captured_run_payloads(
  value : @publication.PreparedCapturedEffectRun,
) -> Array[String] {
  @publication.prepared_captured_effect_run_payloads(value)
}

///|
#export_name("clientProgramRecoveredEffectCapturedRunChainValid")
pub fn client_program_recovered_effect_captured_run_chain_valid(
  run : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  prepared : @publication.PreparedCapturedEffectRun,
  preview : @publication.EffectPreviewIdentity,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  @publication.validate_prepared_effectful_computation_evidence_chain(
    run, invocation, definitions, artifacts, manifest, receipt, captured, prepared,
    preview, max_bytes, max_nodes, max_depth,
  )
  is Ok(_)
}

///|
#export_name("clientProgramRecoveredEffectCapturedRunSources")
pub fn client_program_recovered_effect_captured_run_sources(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  result_artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  prepared : @publication.PreparedCapturedEffectRun,
  preview : @publication.EffectPreviewIdentity,
  member_indices : Array[Int],
  artifacts : Array[@publication.PublicationContract],
  store_authority_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[@publication.CapturedEffectSourceArtifact],
  @publication.RunEvidenceChainIssue,
] {
  @publication.prepared_captured_effect_run_sources(
    run_definition, invocation, definitions, result_artifacts, manifest, receipt,
    captured, prepared, preview, member_indices, artifacts, store_authority_cid,
    max_bytes, max_nodes, max_depth,
  )
}
