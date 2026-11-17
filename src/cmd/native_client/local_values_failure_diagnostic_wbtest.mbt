///|
test "Values command projects only the original typed row execution limit" {
  local_command_diagnostic_reset()
  local_values_command_diagnostic(
    @local_host.Execution(Driver(Configuration(Execution(Rows(7, RowLimit))))),
  )
  let (code, message) = local_command_primary_diagnostic(
    "private supplied query",
  )
  assert_eq(code, "ACTQL_E_EXECUTION_LIMIT")
  assert_eq(
    message, "Local row execution exceeded its admitted row or workspace limit.",
  )
  for json in [false, true] {
    let rendered = local_command_failure_text("private supplied query", json)
    assert_true(rendered.contains(code))
    assert_false(rendered.contains("private supplied query"))
  }
  let other : Array[@local_host.NativeClientValuesWorkIssue] = [
    @local_host.AuthorizationDenied,
    @local_host.Configuration,
    @local_host.Execution(Fenced),
    @local_host.Execution(UnsupportedGraph),
    @local_host.Journal(TransactionUnknown),
  ]
  for issue in other {
    local_command_diagnostic_reset()
    local_values_command_diagnostic(issue)
    assert_eq(
      local_command_primary_diagnostic("original primary"),
      ("ACTQL_E_COMMAND_FAILED", "original primary"),
    )
    command_preparation_diagnostic.val = ParameterMissing
    local_values_command_diagnostic(issue)
    assert_eq(
      local_command_primary_diagnostic("original primary").0,
      "ACTQL_E_PARAMETER_MISSING",
    )
  }
  local_command_diagnostic_reset()
}

///|
test "Values failure diagnostics distinguish normalization budget from graph and current" {
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = value
  local_values_failure_tags(
    @local_host.Normalization(CommonInventory(BudgetExceeded)),
    emit,
  )
  assert_eq(fields.get(10), Some(9L))
  assert_eq(fields.get(11), Some(7006L))
  assert_eq(fields.get(12), Some(102L))
  fields.clear()
  local_values_failure_tags(@local_host.Execution(Fenced), emit)
  assert_eq(fields.get(11), Some(7007L))
  assert_eq(fields.get(12), Some(2L))
  assert_eq(fields.get(15), None)
}

///|
test "Values failure diagnostics preserve configuration and physical transaction uncertainty" {
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = value
  local_values_failure_tags(@local_host.Configuration, emit)
  assert_eq(fields.get(11), Some(7003L))
  assert_eq(fields.length(), 2)
  fields.clear()
  local_values_failure_tags(@local_host.Journal(TransactionUnknown), emit)
  assert_eq(fields.get(11), Some(7004L))
  assert_eq(fields.get(12), Some(4L))
  fields.clear()
  local_values_failure_tags(@local_host.Journal(Physical(BodyTooLarge)), emit)
  assert_eq(fields.get(12), Some(5L))
  assert_eq(fields.get(15), Some(10L))
}
