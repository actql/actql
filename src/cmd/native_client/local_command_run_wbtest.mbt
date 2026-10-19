///|
test "Both preparation carriers select only the supplied exact public Run operation" {
  let local = command().parse(argv=["--mode", "local", "run", "program.aql"])
  assert_true(
    local_command_preparation_operation_selected(
      local,
      local_run_original_operation(),
      true,
    ),
  )
  assert_false(
    local_command_preparation_operation_selected(
      local,
      local_run_original_operation(),
      false,
    ),
  )
  assert_false(
    local_command_preparation_operation_selected(local, "result", true),
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
      local_command_preparation_operation_selected(local, operation, false),
    )
  }
}

///|
test "Selected public Run chooses its operational preparation before any physical acquisition" {
  let local = command().parse(argv=["--mode", "local", "run", "program.aql"])
  assert_true(local_command_preparation_selected(local))
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
test "Selected public Run refuses an unsupplied explicit legacy configuration before acquisition" {
  let local = command().parse(argv=[
    "--mode", "local", "--config-file", "operator.json", "run", "program.aql",
  ])
  let issue = try {
    prepare_native_command_invocation(local)
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "ExplicitLocalConfigurationRequiresOriginalSupplier")
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
test "Public Result refuses explicit unsupplied configuration before original acquisition" {
  let parsed = command().parse(argv=[
    "--mode", "local", "--config-file", "operator.json", "result", "original-run",
  ])
  let issue = try {
    prepare_native_command_invocation(parsed)
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "ExplicitLocalConfigurationRequiresOriginalSupplier")
  assert_true(command_preparation_invocation.val is None)
}
