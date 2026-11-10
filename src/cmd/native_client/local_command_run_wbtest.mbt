///|
test "Original submission lookup selects only its same command Read and no business Run" {
  for
    (operation, options) in [
      ("lookup-submission", ["--submission-ref-file", "original.json"]),
      ("lookup-request", ["--request-id", "sha256:" + "a".repeat(64)]),
    ] {
    let argv = ["--mode", "local", operation]
    for option in options {
      argv.push(option)
    }
    let parsed = command().parse(argv~)
    assert_true(local_command_preparation_selected(parsed))
    assert_true(
      local_command_preparation_operation_selected(parsed, operation, false),
    )
    for foreign in ["new-submission", "cancel", "result"] {
      assert_false(
        local_command_preparation_operation_selected(parsed, foreign, true),
      )
    }
    let original = native_storage_finite_arithmetic_profile()
    let (profile, business) = local_command_profile_selection(original, parsed)
    assert_true(business is None)
    assert_eq(profile.control_bytes, original.control_bytes)
    assert_eq(profile.arena_bytes, original.arena_bytes)
    argv[1] = "remote"
    assert_false(local_command_preparation_selected(command().parse(argv~)))
  }
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Explicit submission reference selects original preparation without a business Run" {
  let parsed = command().parse(argv=[
    "--mode", "local", "new-submission", "--request-id", "original-control",
  ])
  assert_true(local_command_preparation_selected(parsed))
  assert_true(
    local_command_preparation_operation_selected(
      parsed, "new-submission", false,
    ),
  )
  assert_false(
    local_command_preparation_operation_selected(parsed, "cancel", false),
  )
  let original = native_storage_finite_arithmetic_profile()
  let (profile, business) = local_command_profile_selection(original, parsed)
  assert_true(business is None)
  assert_eq(profile.control_bytes, original.control_bytes)
  assert_eq(profile.arena_bytes, original.arena_bytes)
  let remote = command().parse(argv=[
    "--mode", "remote", "new-submission", "--request-id", "original-control",
  ])
  assert_false(local_command_preparation_selected(remote))
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Both preparation carriers select only the supplied exact public Run operation" {
  let local_command = command().parse(argv=[
    "--mode", "local", "run", "program.aql",
  ])
  assert_true(
    local_command_preparation_operation_selected(
      local_command,
      local_run_original_operation(),
      true,
    ),
  )
  assert_false(
    local_command_preparation_operation_selected(
      local_command,
      local_run_original_operation(),
      false,
    ),
  )
  assert_false(
    local_command_preparation_operation_selected(local_command, "result", true),
  )
  let private = command().parse(argv=[
    "--mode", "local", "start", "--program-file", "program.sql", "--submission-ref-file",
    "original.json", "--operation-attempt-id", "original-attempt",
  ])
  assert_false(
    local_command_preparation_operation_selected(
      private,
      local_run_original_operation(),
      true,
    ),
  )
  for operation in ["check", "explain", "adopt"] {
    assert_true(
      local_command_preparation_operation_selected(
        local_command, operation, false,
      ),
    )
  }
}

///|
test "Selected public Run chooses its operational preparation before any physical acquisition" {
  let local_command = command().parse(argv=[
    "--mode", "local", "run", "program.aql",
  ])
  assert_true(local_command_preparation_selected(local_command))
  assert_true(command_preparation_invocation.val is None)
  let remote = command().parse(argv=["--mode", "remote", "run", "program.aql"])
  assert_false(local_command_preparation_selected(remote))
  let private = command().parse(argv=[
    "--mode", "local", "start", "--program-file", "program.sql", "--submission-ref-file",
    "original.json", "--operation-attempt-id", "original-attempt",
  ])
  assert_false(local_command_preparation_selected(private))
}

///|
test "Selected public Run refuses unmeasured original command input before acquisition" {
  let local_command = command().parse(argv=[
    "--mode", "local", "--config-file", "operator.json", "run", "program.aql",
  ])
  assert_true(command_preargument_retained_context() is Err(CommandUnavailable))
  let issue = try {
    prepare_native_command_invocation(local_command)
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "LocalCommandPreparationUnavailable")
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Saved status preparation refuses foreign operations and conflicting references" {
  let status = command().parse(argv=[
    "--mode", "local", "status", "original-run",
  ])
  assert_false(
    local_command_preparation_operation_selected(status, "result", false),
  )
  let child = status.subcommand.unwrap().1
  child.values["ref-file"] = ["foreign.json"]
  assert_false(
    local_command_preparation_operation_selected(status, "status", false),
  )
  ignore(child.values.remove("ref-file"))
  child.values["submission-ref-file"] = ["foreign.json"]
  assert_false(
    local_command_preparation_operation_selected(status, "status", false),
  )
  ignore(child.values.remove("submission-ref-file"))
  ignore(child.values.remove("run"))
  assert_false(
    local_command_preparation_operation_selected(status, "status", false),
  )
}

///|
test "Saved status selects the same static original without selecting a business Run" {
  let parsed = command().parse(argv=[
    "--mode", "local", "status", "original-run", "--json",
  ])
  assert_true(local_command_preparation_selected(parsed))
  assert_true(
    local_command_preparation_operation_selected(parsed, "status", false),
  )
  assert_false(
    local_command_preparation_operation_selected(
      parsed,
      local_run_original_operation(),
      true,
    ),
  )
  normalize_native_status_arguments(parsed)
  assert_true(
    local_command_preparation_operation_selected(parsed, "status", false),
  )
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Public Result selects original preparation only with its business Store supplier" {
  let parsed = command().parse(argv=[
    "--mode", "local", "result", "original-run",
  ])
  assert_true(local_command_preparation_selected(parsed))
  assert_true(
    local_command_preparation_operation_selected(parsed, "result", true),
  )
  assert_false(
    local_command_preparation_operation_selected(parsed, "result", false),
  )
  assert_false(
    local_command_preparation_operation_selected(
      parsed,
      local_run_original_operation(),
      true,
    ),
  )
  let child = parsed.subcommand.unwrap().1
  child.values["submission-ref-file"] = ["foreign.json"]
  assert_false(
    local_command_preparation_operation_selected(parsed, "result", true),
  )
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Public Result refuses unmeasured original command input before acquisition" {
  let parsed = command().parse(argv=[
    "--mode", "local", "--config-file", "operator.json", "result", "original-run",
  ])
  assert_true(command_preargument_retained_context() is Err(CommandUnavailable))
  let issue = try {
    prepare_native_command_invocation(parsed)
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "LocalCommandPreparationUnavailable")
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Original cancellation selects the same command Read without a business execution" {
  for operation in ["cancel", "lookup-cancellation"] {
    let args = [
      "--mode", "local", operation, "--submission-ref-file", "original-submission.json",
      "--ref-file", "original-run.json", "--cancel-id", "original-cancel", "--expected-revision",
      "1",
    ]
    if operation == "cancel" {
      args.push("--operation-attempt-id")
      args.push("original-cancel-attempt")
    }
    let parsed = command().parse(argv=args[:], env=Map([]))
    assert_true(local_command_preparation_selected(parsed))
    assert_true(
      local_command_preparation_operation_selected(parsed, operation, false),
    )
    assert_false(
      local_command_preparation_operation_selected(
        parsed, "new-submission", true,
      ),
    )
    let original = native_storage_finite_arithmetic_profile()
    let (selected, business) = local_command_profile_selection(original, parsed)
    assert_true(business is None)
    assert_eq(selected.control_bytes, original.control_bytes)
    assert_eq(selected.read_domain_bytes, original.read_domain_bytes)
    assert_eq(selected.sqlite_domain_bytes, original.sqlite_domain_bytes)
    args[1] = "remote"
    assert_false(
      local_command_preparation_selected(
        command().parse(argv=args[:], env=Map([])),
      ),
    )
  }
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Original cancellation recovery keeps Unknown and never fabricates a reference" {
  let original = "original-public-cancel-reference"
  for
    failure in [
      "LocalCancellationRecordUnconfirmed", "LocalCommandPreparationCleanupPending",
      "OriginalReadReturnPending",
    ] {
    let retained = local_cancellation_recovery_failure(Some(original), failure)
    assert_eq(
      retained,
      local_cancellation_unknown(original) + " reason=" + failure,
    )
    assert_true(retained.contains("lookup=lookup-cancellation"))
    assert_false(retained.contains("succeeded"))
    assert_eq(local_cancellation_recovery_failure(None, failure), failure)
    assert_eq(local_command_recovery_failure(failure), failure)
  }
  assert_true(command_preparation_invocation.val is None)
}
