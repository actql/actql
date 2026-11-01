///|
pub(all) enum ClientSourceAcquisitionIssue {
  MissingStage
  MissingRequests
  UnsupportedAcquisition(@acquisition.SourceAcquisitionIssue)
}

///|
/// Select the actual Source input from this checked Program, without selecting
/// a Query residual or granting a physical read. The receiving Host still owns
/// whole-input capture, authority, parent backing and observation evidence.
pub fn prepare_client_source_acquisition(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
) -> Result[@acquisition.SourceAcquisition, ClientSourceAcquisitionIssue] {
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  guard @context.program_identity_stage_at(identity, stage) is Some(_) else {
    return Err(MissingStage)
  }
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return Err(MissingRequests)
  }
  @acquisition.derive_source_acquisition(requests, source_index, 1000000).map_err(issue => {
      UnsupportedAcquisition(issue)
    },
  )
}

///|
/// Use the existing same-original Effect-free view; this creates neither a
/// second checked Program nor an Effect/read authority from the input DATA.
pub fn prepare_client_effect_source_acquisition(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
) -> Result[@acquisition.SourceAcquisition, ClientSourceAcquisitionIssue] {
  prepare_client_source_acquisition(
    client_effect_program_view(prepared),
    stage,
    source_index,
  )
}

///|
/// Equal Programs and equal request wires cannot replace the issuing owner.
pub fn client_source_acquisition_matches_program(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
  acquisition : @acquisition.SourceAcquisition,
) -> Bool {
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return false
  }
  physical_equal(@acquisition.source_acquisition_owner(acquisition), requests) &&
  @acquisition.source_acquisition_source_index(acquisition) == source_index
}

///|
pub fn client_source_acquisition_matches_effect_program(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
  acquisition : @acquisition.SourceAcquisition,
) -> Bool {
  client_source_acquisition_matches_program(
    client_effect_program_view(prepared),
    stage,
    source_index,
    acquisition,
  )
}
