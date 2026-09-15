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
  environment : CheckEnvironment
  inventory : RequestInventory
  diagnostic : CheckDiagnostic
}

///|
priv enum RequestInventory {
  Parameters(@parameters.MissingNames)
  CapacityPolicy
  TextTimePolicy
}

///|
pub enum InputRequestKind {
  ParameterValue(@parameters.Declaration)
  HostCapacityPolicy
  HostTextTimePolicy
}

///|
pub struct InputRequest {
  program : @syntax.Program
  environment : CheckEnvironment
  kind : InputRequestKind
}

///|
pub fn input_request_count(value : InputRequests) -> Int {
  match value.inventory {
    Parameters(missing) => @parameters.missing_count(missing)
    CapacityPolicy | TextTimePolicy => 1
  }
}

///|
/// Exact declarations retain name, required type, metadata and original source
/// location. This O(1) reader neither reconstructs the declaration nor resumes
/// checking. Supplied responses must enter the ordinary checking path again.
pub fn input_request_at(value : InputRequests, index : Int) -> InputRequest? {
  let kind = match value.inventory {
    Parameters(missing) => {
      guard @parameters.missing_at(missing, index) is Some(declaration) else {
        return None
      }
      ParameterValue(declaration)
    }
    CapacityPolicy => {
      if index != 0 {
        return None
      }
      HostCapacityPolicy
    }
    TextTimePolicy => {
      if index != 0 {
        return None
      }
      HostTextTimePolicy
    }
  }
  Some({ program: value.program, environment: value.environment, kind, })
}

///|
/// Paths are relative to the Program for ParameterValue and to the admitted
/// Check Environment for Host policies. Missing properties have no span.
pub fn input_request_path(value : InputRequest) -> Array[@decode.PathSegment] {
  match value.kind {
    ParameterValue(declaration) =>
      @decode.cursor_path(@parameters.declaration_source(declaration))
    HostCapacityPolicy => [Key("host_policy_profile"), Key("capacity")]
    HostTextTimePolicy =>
      [Key("host_policy_profile"), Key("text_time_evaluation")]
  }
}

///|
pub fn input_request_source(value : InputRequest) -> @decode.Cursor? {
  match value.kind {
    ParameterValue(declaration) =>
      Some(@parameters.declaration_source(declaration))
    HostCapacityPolicy | HostTextTimePolicy => None
  }
}

///|
fn rejected(cause : LocalConstructionFailure) -> CheckOutcome {
  Rejected({ cause, })
}

///|
/// Retain the failure that established this partial request frontier. Its typed
/// cause is not a claim that later checks would succeed after supplementation.
pub fn input_requests_diagnostic(value : InputRequests) -> CheckDiagnostic {
  value.diagnostic
}

///|
fn checking_outcome(
  program : @syntax.Program,
  environment : CheckEnvironment,
  run : () -> CheckedProgram raise LocalConstructionFailure,
) -> CheckOutcome {
  Checked(run()) catch {
    error => {
      let inventory = match error {
        Source(SourceView(Binding(NeedsBindings(missing)))) =>
          Parameters(missing)
        Source(SourceView(Context(Policy(MissingCapacity)))) => CapacityPolicy
        Source(Checks(Patterns(Timestamp(MissingPolicy(_)))))
        | Source(Checks(Patterns(Regex(MissingPolicy(_)))))
        | Source(Checks(TextBounds(MissingPolicy(_)))) => TextTimePolicy
        _ => return rejected(error)
      }
      NeedsInputs({
        program,
        environment,
        inventory,
        diagnostic: { cause: error, },
      })
    }
  }
}
