///|
test "saved explain selects the original Run without resolving Program parameters or a new Run" {
  let selected = command().parse(
    argv=["--mode", "local", "explain", "--run", "original-run", "--json"],
    env=Map([]),
  )
  normalize_native_program_arguments(selected)
  normalize_native_program_arguments(selected)
  let (_, child) = selected.subcommand.unwrap()
  assert_eq(optional(child, "run"), Some("original-run"))
  for
    field in [
      "program", "program-file", "format", "parameters-file", "parameter-declarations-file",
    ] {
    assert_eq(optional(child, field), None)
  }
  assert_true(local_command_preparation_selected(selected))
  assert_true(
    local_command_preparation_operation_selected(selected, "explain", false),
  )
  assert_false(
    local_command_preparation_operation_selected(selected, "result", false),
  )
  assert_true(command_preparation_invocation.val is None)
}

///|
test "saved explain rejects new input overrides in the real parser" {
  for
    extra in [
      ["program.aql"],
      ["--program-file", "program.aql"],
      ["--format", "sql"],
      ["--params", "new-parameters.json"],
      ["--parameters-file", "new-parameters.json"],
      ["--parameter-declarations-file", "new-declarations.json"],
    ] {
    let argv = ["--mode", "local", "explain", "--run", "original-run"]
    for arg in extra {
      argv.push(arg)
    }
    let refused = try {
      ignore(command().parse(argv=argv[:], env=Map([])))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "saved explain bounds an original ID without acquiring an invocation" {
  let selected = command().parse(
    argv=["--mode", "local", "explain", "--run", "x".repeat(4097)],
    env=Map([]),
  )
  let refused = try {
    normalize_native_program_arguments(selected)
    false
  } catch {
    ClientStop(issue) => issue == "InvalidLocalSavedPlanSelection"
  }
  assert_true(refused)
  assert_true(command_preparation_invocation.val is None)
}
