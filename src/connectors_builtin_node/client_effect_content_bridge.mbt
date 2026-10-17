///|
// Private binding only: the caller must hold the actual prepared owner,
// captured input inventory and issued local Artifact, not their DATA CIDs.
#export_name("clientProgramEffectCommandContentPrepareArtifact")
pub fn client_program_effect_command_content_prepare_artifact(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  max_fields : Int,
  max_work : Int,
) -> Result[Unit, @publication_host.ClientEffectCommandContentIssue] {
  @publication_host.prepare_client_effect_command_content_artifact(
    owner, inputs, member_index, artifact, max_fields, max_work,
  )
}

///|
#export_name("clientProgramEffectCommandContentReleaseArtifact")
pub fn client_program_effect_command_content_release_artifact(
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  quantum : Int,
) -> Bool {
  @publication_host.advance_release_client_effect_command_content_artifact(
    artifact, quantum,
  )
}

///|
#export_name("clientProgramEffectCommandContentBorrow")
pub fn client_program_effect_command_content_borrow(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  row : Int,
  input_name : String,
  max_fields : Int,
  max_work : Int,
) -> Result[
  @publication_host.ClientEffectCommandContent,
  @publication_host.ClientEffectCommandContentIssue,
] {
  @publication_host.borrow_client_effect_command_content(
    owner, inputs, member_index, artifact, row, input_name, max_fields, max_work,
  )
}

///|
#export_name("clientProgramEffectCommandContentMatches")
pub fn client_program_effect_command_content_matches(
  value : @publication_host.ClientEffectCommandContent,
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  row : Int,
  input_name : String,
) -> Bool {
  @publication_host.client_effect_command_content_matches(
    value, owner, inputs, member_index, artifact, row, input_name,
  )
}

///|
#export_name("clientProgramEffectCommandContentWire")
pub fn client_program_effect_command_content_wire(
  value : @publication_host.ClientEffectCommandContent,
) -> Result[String, @publication_host.ClientEffectCommandContentIssue] {
  @publication_host.client_effect_command_content_wire(value)
}

///|
#export_name("clientProgramEffectCommandContentMatchesIssued")
pub fn client_program_effect_command_content_matches_issued(
  value : @publication_host.ClientEffectCommandContent,
  issued : @admitted.CheckedValue,
) -> Bool {
  @publication_host.client_effect_command_content_matches_issued(value, issued)
}

///|
#export_name("clientProgramEffectCommandContentRelease")
pub fn client_program_effect_command_content_release(
  value : @publication_host.ClientEffectCommandContent,
) -> Unit {
  @publication_host.release_client_effect_command_content(value)
}
