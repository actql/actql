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
  TextRankSelection
  TextRankArtifact(@environment.TextRankSelection)
  CalendarSelection
  CalendarArtifact(@environment.CalendarSelection)
}

///|
pub enum InputRequestKind {
  ParameterValue(@parameters.Declaration)
  HostCapacityPolicy
  HostTextTimePolicy
  HostTextRankSelection
  TextRankProfileArtifact(@environment.TextRankSelection)
  HostCalendarSelection
  CalendarProfileArtifact(@environment.CalendarSelection)
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
    CapacityPolicy
    | TextTimePolicy
    | TextRankSelection
    | TextRankArtifact(_)
    | CalendarSelection
    | CalendarArtifact(_) => 1
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
    TextRankSelection => {
      if index != 0 {
        return None
      }
      HostTextRankSelection
    }
    TextRankArtifact(selection) => {
      if index != 0 {
        return None
      }
      TextRankProfileArtifact(selection)
    }
    CalendarSelection => {
      if index != 0 {
        return None
      }
      HostCalendarSelection
    }
    CalendarArtifact(selection) => {
      if index != 0 {
        return None
      }
      CalendarProfileArtifact(selection)
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
    HostTextRankSelection => [Key("host_policy_profile"), Key("text_rank")]
    TextRankProfileArtifact(_) =>
      [Key("host_policy_profile"), Key("text_rank"), Key("profile_bytes_cid")]
    HostCalendarSelection => [Key("host_policy_profile"), Key("calendar")]
    CalendarProfileArtifact(_) =>
      [Key("host_policy_profile"), Key("calendar"), Key("table_bytes_cid")]
  }
}

///|
pub fn input_request_source(value : InputRequest) -> @decode.Cursor? {
  match value.kind {
    ParameterValue(declaration) =>
      Some(@parameters.declaration_source(declaration))
    HostCapacityPolicy
    | HostTextTimePolicy
    | HostTextRankSelection
    | HostCalendarSelection => None
    TextRankProfileArtifact(selection) =>
      Some(@environment.text_rank_selection_source(selection))
    CalendarProfileArtifact(selection) =>
      Some(@environment.calendar_selection_source(selection))
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
        Closure(Operations(Lexical(MissingArtifact(selection)))) =>
          TextRankArtifact(selection)
        Closure(Operations(Lexical(MissingProfile(_, _, _)))) =>
          TextRankSelection
        Source(SourceView(Program(MissingCalendarArtifact(selection)))) =>
          CalendarArtifact(selection)
        Closure(Operations(Calendar(MissingArtifact(selection)))) =>
          CalendarArtifact(selection)
        Source(SourceView(Program(MissingCalendarSelection(_, _)))) =>
          CalendarSelection
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
