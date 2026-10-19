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
    "--mode", "local", "start", "--program-file", "program.sql", "--format", "sql",
    "--submission-ref-file", "original.json", "--operation-attempt-id", "original-attempt",
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
    "--mode", "local", "start", "--program-file", "program.sql", "--format", "sql",
    "--submission-ref-file", "original.json", "--operation-attempt-id", "original-attempt",
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
