///|
/// Fixed ordinary Node publication growth on the original preparation owner.
/// The handle carries provenance, not caller-supplied byte/work quantities.
#export_name("clientProgramReservePublication")
pub fn client_program_reserve_publication(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  prepared : @publication_host.PreparedClientProgram,
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Result[
  @client_local_host.ClientProgramPublication[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.reserve_program_publication(owner, prepared, holder)
}

///|
/// Issue once through the existing Values invocation engine and bind that
/// exact returned original to the same preparation's publication lineage.
#export_name("clientProgramIssuePublicationInvocation")
pub fn client_program_issue_publication_invocation(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.issue_program_publication_invocation(
    owner, prepared, compiled, definition, data_policy_cid, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramPrepareCapture")
pub fn client_program_prepare_capture(
  publication : @client_local_host.ClientProgramPublication[
    ClientLocalPreparationInputOriginal,
  ],
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  authoring : @publication.RunEvidenceValue,
  models : Array[@publication.RunEvidenceValue],
) -> Result[
  @client_local_host.ClientProgramCapture[ClientLocalPreparationInputOriginal],
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.prepare_program_capture(
    publication, definition, invocation, definitions, artifacts, manifest, receipt,
    snapshots, authoring, models,
  )
}

///|
#export_name("clientProgramStartCapture")
pub fn client_program_start_capture(
  capture : @client_local_host.ClientProgramCapture[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @client_local_host.ClientProgramCapture[ClientLocalPreparationInputOriginal],
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.start_program_capture(capture)
}

///|
#export_name("clientProgramAdvanceCapture")
pub fn client_program_advance_capture(
  capture : @client_local_host.ClientProgramCapture[
    ClientLocalPreparationInputOriginal,
  ],
  quantum : Int,
) -> Result[(Bool, Int), @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.advance_program_capture(capture, quantum)
}

///|
#export_name("clientProgramFinishCapture")
pub fn client_program_finish_capture(
  capture : @client_local_host.ClientProgramCapture[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @publication.PublicationContract,
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.finish_program_capture(capture)
}

///|
#export_name("clientProgramCancelCapture")
pub fn client_program_cancel_capture(
  capture : @client_local_host.ClientProgramCapture[
    ClientLocalPreparationInputOriginal,
  ],
) -> Unit {
  @client_local_host.cancel_program_capture(capture)
}

///|
#export_name("clientProgramCaptureLimits")
pub fn client_program_capture_limits(
  capture : @client_local_host.ClientProgramCapture[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  (Int, Int, Int),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.program_capture_limits(capture)
}

///|
#export_name("clientProgramPrepareChainValidation")
pub fn client_program_prepare_chain_validation(
  capture : @client_local_host.ClientProgramCapture[
    ClientLocalPreparationInputOriginal,
  ],
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
) -> Result[
  @client_local_host.ClientProgramValidation[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientProgramValidationIssue,
] {
  @client_local_host.prepare_program_chain_validation(
    capture, definition, invocation, definitions, artifacts, manifest, receipt, captured_run,
  )
}

///|
#export_name("clientProgramPrepareCommitValidation")
pub fn client_program_prepare_commit_validation(
  capture : @client_local_host.ClientProgramCapture[
    ClientLocalPreparationInputOriginal,
  ],
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index : @publication.PublicationContract,
) -> Result[
  @client_local_host.ClientProgramValidation[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientProgramValidationIssue,
] {
  @client_local_host.prepare_program_commit_validation(
    capture, definition, invocation, definitions, artifacts, derivations, orderings,
    retentions, bindings, manifest, receipt, captured_run, request, attempt, index,
  )
}

///|
#export_name("clientProgramStartValidation")
pub fn client_program_start_validation(
  validation : @client_local_host.ClientProgramValidation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @client_local_host.ClientProgramValidation[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientProgramValidationIssue,
] {
  @client_local_host.start_program_validation(validation)
}

///|
#export_name("clientProgramAdvanceValidation")
pub fn client_program_advance_validation(
  validation : @client_local_host.ClientProgramValidation[
    ClientLocalPreparationInputOriginal,
  ],
  quantum : Int,
) -> Result[(Bool, Int), @client_local_host.ClientProgramValidationIssue] {
  @client_local_host.advance_program_validation(validation, quantum)
}

///|
#export_name("clientProgramFinishValidation")
pub fn client_program_finish_validation(
  validation : @client_local_host.ClientProgramValidation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @client_local_host.ClientProgramValidationIssue] {
  @client_local_host.finish_program_validation(validation)
}

///|
#export_name("clientProgramCancelValidation")
pub fn client_program_cancel_validation(
  validation : @client_local_host.ClientProgramValidation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Unit {
  @client_local_host.cancel_program_validation(validation)
}

///|
#export_name("clientProgramBeginSnapshot")
pub fn client_program_begin_snapshot(
  publication : @client_local_host.ClientProgramPublication[
    ClientLocalPreparationInputOriginal,
  ],
  output : StrategyHostOutputExport,
) -> Result[
  @client_local_host.ClientProgramSnapshot[ClientLocalPreparationInputOriginal],
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.begin_program_snapshot(publication, output.core)
}

///|
#export_name("clientProgramAdvanceSnapshot")
pub fn client_program_advance_snapshot(
  snapshot : @client_local_host.ClientProgramSnapshot[
    ClientLocalPreparationInputOriginal,
  ],
  quantum : Int,
) -> Result[(Bool, Int), @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.advance_program_snapshot(snapshot, quantum)
}

///|
#export_name("clientProgramFinishSnapshot")
pub fn client_program_finish_snapshot(
  snapshot : @client_local_host.ClientProgramSnapshot[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @publication.CapturedResultSnapshot,
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.finish_program_snapshot(snapshot)
}

///|
#export_name("clientProgramCancelSnapshot")
pub fn client_program_cancel_snapshot(
  snapshot : @client_local_host.ClientProgramSnapshot[
    ClientLocalPreparationInputOriginal,
  ],
) -> Unit {
  @client_local_host.cancel_program_snapshot(snapshot)
}
