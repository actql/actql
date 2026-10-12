///|
/// Preserve an existing declaration failure in the registration diagnostic
/// domain. This does not resolve a Source or construct a registration.
pub fn source_declaration_diagnostic_issue(
  issue : @source_inputs.Issue,
) -> SourceRegistrationIssue {
  Declarations(issue)
}

///|
/// Preserve an existing Source program failure without preparing a context.
pub fn source_program_diagnostic_issue(
  issue : SourceViewProgramIssue,
) -> SourceViewContextIssue {
  Program(issue)
}

///|
/// Retain the existing local topology failure under the Source program wrappers.
/// This does not construct topology, a checked Program or an execution grant.
pub fn local_program_diagnostic_issue(
  issue : @stage_results.LocalProgramIssue,
) -> SourceViewContextIssue {
  Program(Program(issue))
}
