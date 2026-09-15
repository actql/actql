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
}

///|
priv enum RequestInventory {
  Parameters(@parameters.MissingNames)
  CapacityPolicy
}

///|
pub enum InputRequestKind {
  ParameterValue(@parameters.Declaration)
  HostCapacityPolicy
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
    CapacityPolicy => 1
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
  }
  Some({ program: value.program, environment: value.environment, kind, })
}

///|
/// Paths are relative to the Program for ParameterValue and to the admitted
/// Check Environment for HostCapacityPolicy. Missing properties have no span.
pub fn input_request_path(value : InputRequest) -> Array[@decode.PathSegment] {
  match value.kind {
    ParameterValue(declaration) =>
      @decode.cursor_path(@parameters.declaration_source(declaration))
    HostCapacityPolicy => [Key("host_policy_profile"), Key("capacity")]
  }
}

///|
pub fn input_request_source(value : InputRequest) -> @decode.Cursor? {
  match value.kind {
    ParameterValue(declaration) =>
      Some(@parameters.declaration_source(declaration))
    HostCapacityPolicy => None
  }
}

///|
fn rejected(cause : LocalConstructionFailure) -> CheckOutcome {
  Rejected({ cause, })
}

///|
fn checking_outcome(
  program : @syntax.Program,
  environment : CheckEnvironment,
  run : () -> CheckedProgram raise LocalConstructionFailure,
) -> CheckOutcome {
  Checked(run()) catch {
    Source(SourceView(Binding(NeedsBindings(missing)))) =>
      NeedsInputs({ program, environment, inventory: Parameters(missing), })
    Source(SourceView(Context(Policy(MissingCapacity)))) =>
      NeedsInputs({ program, environment, inventory: CapacityPolicy, })
    error => rejected(error)
  }
}
