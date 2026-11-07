///|
// Presentation of the one irreversible preparation rejection in this command.
// Retain only a closed tag across the original Read return: no Cursor, supplied
// value, diagnostic source, managed text alias or physical receiver escapes.
priv enum LocalCommandDiagnosticKind {
  Unspecified
  ParameterInvalid
  ParameterMissing
  ParameterDeclarations
  ParameterBinding
  ProgramInvalid
  QuerySyntaxInvalid
  ConfigurationInvalid
  UnsupportedPreparation
  PreparationLimit
  InputRequired
  PreparationFailed
  ReadOnlyEffect
  RunObservationFailed
  JournalMaintenanceFailed
}

///|
let command_preparation_diagnostic : Ref[LocalCommandDiagnosticKind] = Ref(
  Unspecified,
)

///|
let command_diagnostic_json : Ref[Bool] = Ref(false)

///|
fn local_command_diagnostic_reset() -> Unit {
  command_preparation_diagnostic.val = Unspecified
  command_diagnostic_json.val = false
}

///|
fn local_command_json_selected(matches : @argparse.Matches) -> Bool {
  if matches.flags.get("json").unwrap_or(false) {
    return true
  }
  match matches.subcommand {
    Some((_, child)) => local_command_json_selected(child)
    None => false
  }
}

///|
// Parse failure has no Matches. Select only error presentation from an exact
// standalone flag before `--`. This command grammar has no hyphen-value
// arguments; `=value` and positional text cannot supply this selector. The
// pinned parser alone validates arguments; accepted Matches override this bit.
fn local_command_argument_diagnostic_json(arguments : Array[String]) -> Bool {
  for index in 1..<arguments.length() {
    if arguments[index] == "--" {
      return false
    }
    if arguments[index] == "--json" {
      return true
    }
  }
  false
}

///|
fn local_check_diagnostic_kind(
  diagnostic : @checked.CheckDiagnostic,
) -> LocalCommandDiagnosticKind {
  match @checked.diagnostic_category(diagnostic) {
    InvalidInput =>
      if @checked.diagnostic_origin(diagnostic) == Some(@checked.SuppliedValues) {
        ParameterInvalid
      } else {
        ProgramInvalid
      }
    InvalidConfiguration => ConfigurationInvalid
    UnsupportedImplementation => UnsupportedPreparation
    CompileLimit => PreparationLimit
    MissingInput => InputRequired
    UnclassifiedFailure => PreparationFailed
  }
}

///|
fn local_frontend_diagnostic_kind(
  issue : @frontend.Issue,
) -> LocalCommandDiagnosticKind {
  match issue {
    QuerySyntax({ issue: Syntax(_) | Lexical(_), .. }) => QuerySyntaxInvalid
    QuerySyntax({ issue: Limit(_) | Source(InputLimit), .. }) =>
      PreparationLimit
    InvalidFormat | WrongQueryForm | QuerySyntax(_) => ProgramInvalid
    _ => PreparationFailed
  }
}

///|
fn local_native_preparation_diagnostic_kind(
  issue : @local_host.NativeClientPreparationIssue,
) -> LocalCommandDiagnosticKind {
  match issue {
    Syntax(_) => ProgramInvalid
    Frontend(issue) => local_frontend_diagnostic_kind(issue)
    Computation(Check(diagnostic)) => local_check_diagnostic_kind(diagnostic)
    Computation(NeedsInputs(requests)) => {
      for index in 0..<@checked.input_request_count(requests) {
        if @checked.input_request_at(requests, index) is Some(request) &&
          request.kind is @checked.ParameterValue(_) {
          return ParameterMissing
        }
      }
      local_check_diagnostic_kind(@checked.input_requests_diagnostic(requests))
    }
    Computation(Syntax(_)) => ProgramInvalid
    Computation(Binding(_)) => ParameterBinding
    Computation(_) | EffectComputation(_) => PreparationFailed
  }
}

///|
fn[T] local_stop_submitted_preparation(
  issue : @local_host.NativeClientSubmittedPreparationIssue,
) -> T raise ClientStop {
  command_preparation_diagnostic.val = match issue {
    InvalidSubmittedInput => ProgramInvalid
    SubmittedInputLimit => PreparationLimit
    Declarations(_) => ParameterDeclarations
    Preparation(original) => local_native_preparation_diagnostic_kind(original)
    ReadOnlyEffect => ReadOnlyEffect
    Request(CheckOutcome(outcome)) =>
      match outcome {
        @checked.Rejected(diagnostic) => local_check_diagnostic_kind(diagnostic)
        @checked.NeedsInputs(requests) =>
          local_check_diagnostic_kind(
            @checked.input_requests_diagnostic(requests),
          )
        @checked.Checked(_) => PreparationFailed
      }
    Request(_) | RequestPreparation(_) => PreparationFailed
    RequestBranchUnavailable => UnsupportedPreparation
  }
  // The existing caller propagates this rejection; it never retries another
  // checker. Preserve its old private carrier and cleanup routing unchanged.
  stop("LocalPreparationNotReady")
}

///|
fn[T] local_stop_native_preparation(
  issue : @local_host.NativeClientPreparationIssue,
) -> T raise ClientStop {
  command_preparation_diagnostic.val = local_native_preparation_diagnostic_kind(
    issue,
  )
  stop("LocalPreparationNotReady")
}

///|
fn local_command_primary_diagnostic(message : String) -> (String, String) {
  match command_preparation_diagnostic.val {
    Unspecified | RunObservationFailed | JournalMaintenanceFailed =>
      ("ACTQL_E_COMMAND_FAILED", message)
    ParameterInvalid =>
      (
        "ACTQL_E_PARAMETER_INVALID", "A supplied parameter does not match its declared type or constraints.",
      )
    ParameterMissing =>
      (
        "ACTQL_E_PARAMETER_MISSING", "A required declared parameter has no supplied value or default.",
      )
    ParameterDeclarations =>
      (
        "ACTQL_E_PARAMETER_DECLARATIONS", "The original parameter declarations could not be admitted.",
      )
    ParameterBinding =>
      (
        "ACTQL_E_PARAMETER_BINDING", "The original parameter binding could not be completed.",
      )
    QuerySyntaxInvalid =>
      (
        "ACTQL_E_PROGRAM_INVALID", "The query syntax is invalid. Run actql check with the same input and format for syntax diagnostics.",
      )
    ProgramInvalid =>
      ("ACTQL_E_PROGRAM_INVALID", "The original Program input is invalid.")
    ConfigurationInvalid =>
      (
        "ACTQL_E_CONFIGURATION_INVALID", "The original preparation configuration is invalid.",
      )
    UnsupportedPreparation =>
      (
        "ACTQL_E_PREPARATION_UNSUPPORTED", "The selected implementation does not support the original preparation.",
      )
    PreparationLimit =>
      (
        "ACTQL_E_PREPARATION_LIMIT", "An original preparation limit was exceeded.",
      )
    InputRequired =>
      (
        "ACTQL_E_INPUT_REQUIRED", "The original preparation requires more input.",
      )
    PreparationFailed =>
      (
        "ACTQL_E_PREPARATION_FAILED", "The original preparation could not be completed.",
      )
    ReadOnlyEffect =>
      ("ACTQL_E_READ_ONLY_EFFECT", "The read-only request contains an Effect.")
  }
}

///|
// Fixed preparation messages contain no supplied values or authored text.
// Other original command messages are bounded and quoted for terminal safety.
fn local_command_failure_text(message : String, json : Bool) -> String {
  // Legacy failures can carry complete cancellation/Unknown or saved-Run
  // recovery metadata. Only the original typed preparation rejection selects
  // the new format; never parse, quote or truncate the legacy carrier.
  if command_preparation_diagnostic.val is Unspecified {
    return "actql-native-client: " + message
  }
  let (code, original_message) = local_command_primary_diagnostic(message)
  local_command_diagnostic_text(code, original_message, json)
}

///|
fn local_command_diagnostic_text(
  code : String,
  message : String,
  json : Bool,
) -> String {
  let bounded = StringBuilder()
  let mut count = 0
  for scalar in message.iter() {
    if count == 256 {
      bounded.write_string("…")
      break
    }
    bounded.write_char(scalar)
    count += 1
  }
  let text = bounded.to_string()
  if json {
    encode_request_json(
      Json::object(
        Map([("code", Json::string(code)), ("message", Json::string(text))]),
      ),
      4096,
    ) catch {
      ClientStop(_) =>
        // Codes are closed caller constants. Keep the original code if an
        // original message cannot be encoded.
        "{\"code\":\"" +
        code +
        "\",\"message\":\"The command failed; its diagnostic message could not be encoded.\"}"
    }
  } else {
    let quoted = encode_request_json(Json::string(text), 4096) catch {
      ClientStop(_) => "\"The command diagnostic could not be encoded.\""
    }
    "actql-native-client: " + code + ": " + quoted
  }
}

///|
// Add only closed primary read advice. The original failure and all Reader/Root
// custody stay with their owner; OS strings and protected paths are not facts.
fn local_bounded_file_diagnostic_message(
  original : String,
  issue : @files.NativeBoundedTextIssue,
) -> String {
  let hint = match issue {
    Missing =>
      Some(
        "The input file is missing. Check the selected file and configuration.",
      )
    CapacityExceeded =>
      Some("The input file does not fit the configured read limit.")
    InvalidUtf8 => Some("The input file is not valid UTF-8. Use UTF-8 text.")
    _ => None
  }
  match hint {
    Some(hint) => original + ": " + hint
    None => original
  }
}
