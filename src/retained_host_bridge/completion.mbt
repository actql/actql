///|
suberror RetainedCompletionFailure {
  Evidence(@execution.RetainedCompletionEvidenceIssue)
}

///|
#export_name("retainedCompletionEvidence")
pub fn retained_completion_evidence(
  output : @execution.CompletedOutput,
  max_inputs : Int,
  max_columns : Int,
) -> @execution.RetainedCompletionEvidence raise RetainedCompletionFailure {
  match @execution.retain_completion_evidence(output, max_inputs, max_columns) {
    Ok(value) => value
    Err(issue) => raise Evidence(issue)
  }
}

///|
#export_name("retainedCompletionDescriptor")
pub fn retained_completion_descriptor(
  value : @execution.RetainedCompletionEvidence,
) -> @execution.RetainedCompletionDescriptor {
  @execution.retained_completion_descriptor(value)
}

///|
#export_name("retainedCompletionCanHandoff")
pub fn retained_completion_can_handoff(
  value : @execution.RetainedCompletionEvidence,
  output : @execution.CompletedOutput,
) -> Bool {
  @execution.retained_completion_can_handoff(value, output)
}

///|
#export_name("retainedCompletionMaterial")
pub fn retained_completion_material(
  value : @execution.RetainedCompletionEvidence,
  output : @execution.CompletedOutput,
) -> @execution.RetainedOutputMaterial? {
  @execution.retained_completion_material(value, output)
}
