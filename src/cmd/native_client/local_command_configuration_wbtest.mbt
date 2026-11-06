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
