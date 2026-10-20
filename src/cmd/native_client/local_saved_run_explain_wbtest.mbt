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

///|
test "saved explain canonicalizes the same actual compiler view before strict envelope admission" {
  let plan = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  ) catch {
    ClientStop(issue) => fail("saved-plan compiler fixture: " + issue)
  }
  let reference = Json::object(
    Map([
      ("namespaceId", Json::string("workspace:original")),
      ("authorityScopeCid", Json::string("sha256:" + "a".repeat(64))),
      ("runDefinitionCid", Json::string("sha256:" + "b".repeat(64))),
    ]),
  )
  let wire = local_saved_run_plan_reply(reference, plan) catch {
    ClientStop(issue) => fail("saved-plan reply: " + issue)
  }
  let value = @publication.parse_interactive_run_control_shape(
    "run_plan_view", wire, 65536, 8192, 64,
  ).unwrap()
  assert_eq(@canonical.stringify_value(value, 65536, 8192, 64), wire)
  assert_eq(local_saved_run_plan_reply(reference, plan), wire)
  let invalid = try {
    ignore(local_saved_run_plan_reply(reference, "{}"))
    false
  } catch {
    ClientStop(issue) => issue == "LocalOriginalRunPlanUnavailable"
  }
  assert_true(invalid)
}
