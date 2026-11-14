///|
/// Project the original failed raw input admission, without parsing/checking
/// it again. The trusted Request caller retains that exact failure and funds
/// this report. Source-dependent semantic outcomes use the separate original
/// checker projection; this entry can disclose only authored input failures.
pub(all) enum ClientCheckOriginalInputIssue {
  OriginalParametersIssue(LocalProgramInputIssue)
  OriginalProgramIssue(@syntax.SyntaxError)
  OriginalDeclarationsIssue
  OriginalDeclarationInput(@stage_parameters.Issue)
  OriginalParameterDeclarationInput(@parameters.Issue)
}

///|
pub fn client_program_project_original_input_issue(
  issue : ClientCheckOriginalInputIssue,
  document : String,
  format : @syntax.Format,
  context_ref : String,
  input_revision : String,
  input_bytes : Int,
  declarations_revision : String?,
  declarations_bytes : Int,
  parameters_revision : String?,
  parameters_bytes : Int,
  correlation_ref : String,
  structured_program? : Bool = true,
  original_body? : @decode.Cursor? = None,
) -> String {
  let findings : Array[CheckFinding] = []
  let mut pointer = None
  let stop = match issue {
    OriginalParametersIssue(SuppliedSyntax(issue)) => {
      findings.push(
        if check_parse_budget(issue.issue) {
          Limit("analysis_budget_exhausted")
        } else {
          SuppliedParseViolation(None)
        },
      )
      Report
    }
    OriginalParametersIssue(SuppliedAdmission(issue)) => {
      findings.push(
        if issue.kind is BudgetExceeded {
          Limit("analysis_budget_exhausted")
        } else {
          SuppliedViolation(None)
        },
      )
      Report
    }
    OriginalParametersIssue(InvalidFormat) => Failed("check_request_invalid")
    OriginalProgramIssue(issue) =>
      check_program_diagnostic(
        findings,
        @checked.program_input_diagnostic(issue),
        document,
        None,
        None,
        value => pointer = value,
        format~,
        original_body~,
      )
    OriginalParameterDeclarationInput(issue) =>
      check_program_diagnostic(
        findings,
        @checked.source_declarations_diagnostic(
          @stage_parameters.Declarations(issue),
        ),
        document,
        None,
        None,
        value => pointer = value,
        format~,
      )
    OriginalDeclarationInput(issue) =>
      check_program_diagnostic(
        findings,
        @checked.source_declarations_diagnostic(issue),
        document,
        None,
        None,
        value => pointer = value,
        format~,
      )
    OriginalDeclarationsIssue => {
      findings.push(DeclarationViolation(None))
      Report
    }
  }
  check_outcome_json(findings, stop, context_ref, correlation_ref, {
    scope: BoundInput,
    structured_program,
    program_pointer: pointer,
    source_revision: input_revision,
    source_bytes: input_bytes,
    declarations_revision,
    declarations_bytes,
    parameters_revision,
    parameters_bytes,
  })
}
