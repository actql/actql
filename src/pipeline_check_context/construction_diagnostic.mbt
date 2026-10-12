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

///|
/// Preserve selected Source and request failures in their owning error domains.
/// These projections do not resolve, prepare, acquire or authorize a Source.
pub fn source_selection_diagnostic_issue(
  issue : @sourceviews.Issue,
) -> SourceRegistrationIssue {
  Selection(issue)
}

///|
pub fn source_request_bindings_diagnostic_issue(
  issue : @binding_declarations.Issue,
) -> PrepareSourcesIssue {
  Declarations(issue)
}

///|
pub fn source_request_slots_diagnostic_issue(
  issue : @request_slots.Issue,
) -> PrepareSourcesIssue {
  Slots(issue)
}

///|
pub fn source_request_context_diagnostic_issue(
  issue : @sourceviews.RequestIssue,
) -> PrepareSourcesIssue {
  Requests(Context(issue))
}
