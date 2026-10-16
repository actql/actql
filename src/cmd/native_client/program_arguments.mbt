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
