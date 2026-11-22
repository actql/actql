///|
test "Native saved operations do not prepare an installation Environment" {
  for
    argv in [
      ["result", "original-run"],
      ["status", "original-run"],
      ["approve", "original-checkpoint"],
      ["reject", "original-checkpoint"],
      ["explain", "--run", "original-run"],
    ] {
    let parsed = command().parse(argv~)
    let (operation, child) = parsed.subcommand.unwrap()
    // There is deliberately no new Program Environment to admit. This is
    // selection DATA only; the actual saved Run/Checkpoint and permissions
    // are still required by the existing command consumer.
    assert_true(
      local_command_check_environment(operation, child, "not json", "absent")
      is None,
    )
  }
  // The unselected compatibility entrance still performs full admission.
  assert_true(local_admitted_check_environment("not json", "absent") is None)
}

///|
test "Native fresh preparation retains strict typed Environment admission" {
  for
    argv in [
      ["check", "--program-file", "original.sql", "--format", "sql"],
      ["explain", "--program-file", "original.sql", "--format", "sql"],
      ["run", "original.aql"],
      ["sql", "SELECT 1"],
    ] {
    let parsed = command().parse(argv~)
    let (operation, child) = parsed.subcommand.unwrap()
    let failure = try {
      ignore(
        local_command_check_environment(operation, child, "not json", "absent"),
      )
      "unexpected success"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(failure, "InvalidLocalCheckEnvironment")
    // A valid original wire with a well-formed foreign CID must also refuse.
    let mismatched = try {
      ignore(
        local_command_check_environment(
          operation, child, explain_update_environment_wire, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        ),
      )
      "unexpected success"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(mismatched, "InvalidLocalCheckEnvironment")
    let admitted = local_command_check_environment(
      operation, child, explain_update_environment_wire, "sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
    ).unwrap()
    assert_eq(
      @checked.checking_environment_cid(admitted),
      "sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
    )
  }
}

///|
test "Native original Environment selects text-time only when a Policy is installed" {
  let assets = @run_host.client_local_product_assets()
  let original = @decode.open_object(local_input_cursor(assets.environment)).unwrap()
  let evidence = run_text(original, "evidence_bundle_cid")
  let installed = local_admitted_check_environment(assets.environment, evidence).unwrap()
  assert_eq(@checked.checking_environment_cid(installed), evidence)
  let selection = @checked.checking_environment_profile_selection(installed)
  assert_true(selection.expressions.text_time)
  assert_false(selection.expressions.veca)
  assert_eq(
    selection.numeric_profile_cid,
    Some(@numeric.cid(@numeric.builtin_profile())),
  )

  let without_policy = local_admitted_check_environment(
    explain_update_environment_wire, "sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
  ).unwrap()
  assert_false(
    @checked.checking_environment_profile_selection(without_policy).expressions.text_time,
  )
  let program =
    #|{"version":"actql/0.1","id":"text-profile","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"a,b"}]},"as":"input"},{"derive":{"part":"split_part(text, ',', -1)"},"as":"selected"}],"results":{"r":{"from":"selected","fields":["part"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  let limits = @run_host.client_standard_program_preparation_limits().checking
  assert_true(
    @checked.check_document(program, installed, None, limits, format=Json)
    is Checked(_),
  )
  guard @checked.check_document(
      program,
      without_policy,
      None,
      limits,
      format=Json,
    )
    is NeedsInputs(requests) else {
    fail("Missing text-time policy must retain its original input request")
  }
  assert_eq(@checked.input_request_count(requests), 1)
  assert_true(
    @checked.input_request_at(requests, 0).unwrap().kind is HostTextTimePolicy,
  )
}
