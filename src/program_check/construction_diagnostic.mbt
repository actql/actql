///|
/// Project an original declaration failure through the common classification.
/// This does not check a Program or establish permission to execute it.
pub fn source_declarations_diagnostic(issue : @stages.Issue) -> CheckDiagnostic {
  construction_failure_diagnostic(Source(Declarations(issue)))
}

///|
/// Retain the original registration cause without disclosing Catalog metadata.
pub fn source_registration_diagnostic(
  issue : @context.SourceRegistrationIssue,
) -> CheckDiagnostic {
  construction_failure_diagnostic(Source(Registration(issue)))
}

///|
/// Retain a context failure under the same wrappers used by normal checking.
pub fn source_context_diagnostic(
  issue : @context.SourceViewContextIssue,
) -> CheckDiagnostic {
  construction_failure_diagnostic(Source(SourceView(issue)))
}

///|
/// Preserve request preparation failures under the original common Owner.
pub fn source_requests_diagnostic(
  issue : @context.PrepareSourcesIssue,
) -> CheckDiagnostic {
  construction_failure_diagnostic(Source(Requests(issue)))
}

///|
/// Authored request form checking grants no acquisition or execution authority.
pub fn source_request_form_diagnostic(
  issue : @sourceviews.RequestFormIssue,
) -> CheckDiagnostic {
  construction_failure_diagnostic(Source(RequestForm(issue)))
}

///|
/// Preserve an already refused Program input through the same semantic
/// classification as document checking. This does not parse or check it again.
pub fn program_input_diagnostic(issue : @syntax.SyntaxError) -> CheckDiagnostic {
  construction_failure_diagnostic(Program(issue))
}

///|
/// Retain the SAME already-issued diagnostic as its negative check outcome.
/// This projects an original constructor refusal; it performs no input read,
/// semantic check, remaining work, successful preparation or authority issue.
/// Keeping this wrapper here preserves the checker's read-only outcome type.
pub fn original_check_diagnostic_outcome(
  original : CheckDiagnostic,
) -> CheckOutcome {
  Rejected(original)
}
