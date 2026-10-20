///|
// Public command spellings select the existing input fields only. No Program,
// Submission, authorization or execution state is issued by argument parsing.
fn normalize_native_program_arguments(
  matches : @argparse.Matches,
) -> Unit raise ClientStop {
  guard matches.subcommand is Some((operation, child)) &&
    ["check", "explain", "run"].contains(operation) else {
    return
  }
  if operation == "run" {
    ignore(native_requested_stop_before(child))
  }
  if operation == "explain" && optional(child, "run") is Some(id) {
    if id.is_empty() || @utf8.encode(id).length() > 4096 {
      stop("InvalidLocalSavedPlanSelection")
    }
    for
      field in [
        "program", "program-file", "format", "parameters-file", "params", "parameter-declarations-file",
      ] {
      if optional(child, field) is Some(_) {
        stop("ConflictingLocalSavedPlanSelection")
      }
    }
    return // Saved bytes never resolve another Program or current parameters.
  }
  match (optional(child, "program"), optional(child, "program-file")) {
    (Some(_), Some(_)) => stop("ConflictingProgramInputs")
    (Some(path), None) => {
      // Programs are GoogleSQL/Pipe text by default. A filename suffix is not
      // a parser, and never silently selects a JSON/YAML representation.
      child.values["program-file"] = [path]
      ignore(child.values.remove("program"))
      if optional(child, "format") is None {
        child.values["format"] = ["aql-text"]
      }
    }
    (None, Some(_)) =>
      // Preserve explicit legacy source interpretation, including its exact
      // submitted intent bytes; do not reinterpret an old JSON/YAML input.
      if optional(child, "format") is None {
        stop("ProgramSourceFormatRequired")
      }
    (None, None) => stop("ProgramFileRequired")
  }
  match (optional(child, "params"), optional(child, "parameters-file")) {
    (Some(_), Some(_)) => stop("ConflictingParameterInputs")
    (Some(path), None) => {
      child.values["parameters-file"] = [path]
      ignore(child.values.remove("params"))
    }
    _ => ()
  }
}

///|
// The existing closed intent option is a continuation restriction, never an
// Account decision, approval, Checkpoint or permission to start physical work.
fn native_requested_stop_before(
  child : @argparse.Matches,
) -> String? raise ClientStop {
  match optional(child, "stop-before") {
    None => None
    Some("commit") => Some("commit")
    Some(_) => stop("UnsupportedStopBeforeBoundary")
  }
}
