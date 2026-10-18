///|
// Caller retention of the original decoded input and pinned parser graph.
// This is initial control DATA, not a Host, Read or cleanup acknowledgement.
priv struct LocalCommandParsedInput {
  arguments : Array[String]
  definition : @argparse.Command
  matches : @argparse.Matches
  classes : LocalCommandArgumentClasses?
}

///|
// The synchronous foreign call observes only liveness, never MoonBit layout.
// Retain every original control alias through the final physical cleanup call.
#borrow(original)
extern "C" fn command_initial_control_keep_alive(
  original : LocalCommandParsedInput,
) -> Unit = "actql_native_client_keep_initial_command_control"

///|
fn parse_native_initial_arguments(
  arguments : Array[String],
  selected : Bool,
) -> LocalCommandParsedInput raise {
  let definition = command()
  // Explicit argv prevents the pinned default_argv from obtaining another
  // native argument array. Include argv0 in the retained original, not parse.
  let start = if arguments.is_empty() { 0 } else { 1 }
  let matches = definition.parse(argv=arguments[start:])
  let classes = if selected {
    let observed = command_preparation_result(command_preargument_classes())
    if observed.arguments != arguments.length() {
      stop("LocalCommandArgumentsChanged")
    }
    Some(observed)
  } else {
    None
  }
  { arguments, definition, matches, classes, }
}

///|
fn parse_native_initial_command(
  selected : Bool,
) -> LocalCommandParsedInput raise {
  // Exactly one native OS-to-managed copy after the raw bounds observation.
  parse_native_initial_arguments(@env.args(), selected)
}
