///|
test "CLI help uses the public name and describes the core workflow" {
  let help = command().render_help()
  assert_true(help.contains("Usage: actql"))
  assert_false(help.contains("actql-native-client"))
  for
    description in [
      "Check, explain, and run ActQL Programs", "Validate a Program without reading business data",
      "Show a Program plan or a saved Run plan", "Run a Program and report its state",
      "Host mode: local or remote", "Path to the project configuration file",
    ] {
    assert_true(help.contains(description))
  }
}

///|
test "CLI argument errors include useful command-specific help" {
  for
    (name, description) in [
      ("check", "Program syntax: json, yaml, aql, or sql"),
      ("explain", "Saved Run ID to explain"),
      ("sql", "--format controls Result rows"),
      ("result", "Result row format: table, json, jsonl, or csv"),
      ("status", "Watch the Run for state changes"),
    ] {
    let help = try {
      ignore(command().parse(argv=[name, "--unknown-help-test"], env=Map([])))
      fail("unknown option must be rejected")
    } catch {
      error => error.to_string()
    }
    assert_true(help.contains("Usage: actql " + name))
    assert_false(help.contains("actql-native-client"))
    assert_true(help.contains(description))
  }
}
