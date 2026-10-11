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
