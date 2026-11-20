///|
/// Project only the reached Request owner's typed limit. This reads the SAME
/// Result; it neither rechecks input nor classifies unrelated constructor,
/// current, foreign or encoding failures as a known submission refusal.
pub fn request_program_normalization_issue_code(
  result : Result[
    @publication_host.ClientLocalNormalization,
    ClientRequestNormalizationIssue,
  ],
) -> String? {
  match result {
    Err(Preparation(Work(WorkLimit))) =>
      Some("ClientProgramNormalizationWorkLimit")
    Err(Preparation(Capacity(Resource(RetentionLimit)))) =>
      Some("ClientProgramNormalizationRetentionLimit")
    Err(Preparation(Capacity(Resource(ExecutionLimit)))) =>
      Some("ClientProgramNormalizationExecutionLimit")
    _ => None
  }
}

///|
/// Keep authoring distinct from normalization even when the underlying Ledger
/// or work cause is the same. No quota amount or nonexecution ACK is invented.
pub fn request_program_authoring_context_issue_code(
  result : Result[
    @publication_host.ClientAuthoringContextPreparation,
    ClientRequestAuthoringIssue,
  ],
) -> String? {
  match result {
    Err(Preparation(Work(WorkLimit))) => Some("ClientProgramAuthoringWorkLimit")
    Err(Preparation(Capacity(Resource(RetentionLimit)))) =>
      Some("ClientProgramAuthoringRetentionLimit")
    Err(Preparation(Capacity(Resource(ExecutionLimit)))) =>
      Some("ClientProgramAuthoringExecutionLimit")
    _ => None
  }
}
