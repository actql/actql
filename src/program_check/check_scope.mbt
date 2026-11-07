///|
pub(all) enum CheckScope {
  TemplateOnly
  BoundInput
} derive(Eq, Debug)

///|
pub(all) enum CheckRequestIssue {
  BindingsInTemplateScope
} derive(Eq, Debug)

///|
pub enum ScopedCheckOutcome {
  InvalidRequest(CheckRequestIssue)
  BoundInput(CheckOutcome)
  TemplateOnly(TemplateCheckOutcome)
}

///|
pub enum TemplateCheckOutcome {
  Verified(TemplateCheckedProgram)
  Rejected(CheckDiagnostic)
  Unresolved(TemplateCheckFrontier)
}

///|
priv enum TemplateCheckProgress {
  Stopped(CheckDiagnostic)
  Declarations(TemplateDeclarationPreparation, CheckDiagnostic)
}

///|
/// A frontier under the original template scope. Prepared declarations and
/// wiring are explicitly partial. Only TemplateCheckedProgram can close this
/// original scope; a frontier retains the typed reason closure stopped.
struct TemplateCheckFrontier {
  program : @syntax.Program
  environment : CheckEnvironment
  progress : TemplateCheckProgress
}

///|
/// Select the requested scope before admission/preparation. A submitted binding
/// object, including an empty object or null, is an invalid template request.
/// The bound branch keeps the existing full checker and actual value binding.
pub fn check_parsed_scoped(
  program : @syntax.Program,
  environment : CheckEnvironment,
  scope : CheckScope,
  supplied : @decode.Cursor?,
  limits : CheckLimits,
  source_preparation? : @stages.Source? = None,
) -> ScopedCheckOutcome {
  match scope {
    BoundInput =>
      BoundInput(
        check_parsed(
          program,
          environment,
          supplied,
          limits,
          source_preparation~,
        ),
      )
    TemplateOnly => {
      if supplied is Some(_) {
        return InvalidRequest(BindingsInTemplateScope)
      }
      match
        prepare_template_declarations(
          program,
          environment,
          limits,
          source_preparation~,
        ) {
        Ok(prepared) =>
          match complete_template_check(prepared) {
            Ok(checked) => TemplateOnly(Verified(checked))
            Err(issue) => {
              let cause = LocalConstructionFailure::Template(prepared, issue)
              let diagnostic : CheckDiagnostic = {
                cause,
                category: classify_diagnostic_cause(cause),
                independent_supplied: None,
              }
              if diagnostic.category == InvalidInput {
                TemplateOnly(Rejected(diagnostic))
              } else {
                TemplateOnly(
                  Unresolved({
                    program,
                    environment,
                    progress: Declarations(prepared, diagnostic),
                  }),
                )
              }
            }
          }
        Err(cause) => {
          let diagnostic : CheckDiagnostic = {
            cause,
            category: classify_diagnostic_cause(cause),
            independent_supplied: None,
          }
          if diagnostic.category == InvalidInput {
            TemplateOnly(Rejected(diagnostic))
          } else {
            TemplateOnly(
              Unresolved({
                program,
                environment,
                progress: Stopped(diagnostic),
              }),
            )
          }
        }
      }
    }
  }
}

///|
pub fn template_frontier_program(
  value : TemplateCheckFrontier,
) -> @syntax.Program {
  value.program
}

///|
pub fn template_frontier_environment(
  value : TemplateCheckFrontier,
) -> CheckEnvironment {
  value.environment
}

///|
pub fn template_frontier_diagnostic(
  value : TemplateCheckFrontier,
) -> CheckDiagnostic? {
  match value.progress {
    Stopped(diagnostic) => Some(diagnostic)
    Declarations(_, diagnostic) => Some(diagnostic)
  }
}

///|
pub fn template_frontier_declarations(
  value : TemplateCheckFrontier,
) -> TemplateDeclarationPreparation? {
  match value.progress {
    Stopped(_) => None
    Declarations(prepared, _) => Some(prepared)
  }
}
