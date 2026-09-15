///|
/// Missing inputs are a partial checking frontier, not a valid remainder or a
/// partially constructed CheckedProgram. Rejection retains its typed cause.
pub enum CheckOutcome {
  Checked(CheckedProgram)
  NeedsInputs(InputRequests)
  Rejected(CheckDiagnostic)
}

///|
struct CheckDiagnostic {
  cause : LocalConstructionFailure
}

///|
pub fn diagnostic_cause(value : CheckDiagnostic) -> LocalConstructionFailure {
  value.cause
}

///|
struct InputRequests {
  program : @syntax.Program
  parameters : @parameters.MissingNames
}

///|
pub enum InputRequestKind {
  ParameterValue(@parameters.Declaration)
}

///|
pub struct InputRequest {
  program : @syntax.Program
  kind : InputRequestKind
}

///|
pub fn input_request_count(value : InputRequests) -> Int {
  @parameters.missing_count(value.parameters)
}

///|
/// Exact declarations retain name, required type, metadata and original source
/// location. This O(1) reader neither reconstructs the declaration nor resumes
/// checking. Supplied responses must enter the ordinary checking path again.
pub fn input_request_at(value : InputRequests, index : Int) -> InputRequest? {
  @parameters.missing_at(value.parameters, index).map(declaration => {
    program: value.program,
    kind: ParameterValue(declaration),
  })
}

///|
fn rejected(cause : LocalConstructionFailure) -> CheckOutcome {
  Rejected({ cause, })
}

///|
fn checking_outcome(
  program : @syntax.Program,
  run : () -> CheckedProgram raise LocalConstructionFailure,
) -> CheckOutcome {
  Checked(run()) catch {
    Source(SourceView(Binding(NeedsBindings(missing)))) =>
      NeedsInputs({ program, parameters: missing, })
    error => rejected(error)
  }
}
