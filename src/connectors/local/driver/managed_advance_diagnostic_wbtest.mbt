///|
test "managed advance diagnoses only the original control-work constructor" {
  assert_eq(
    local_managed_advance_control_work_limit(
      local_managed_provider_failure(@connector.ControlWorkLimit, 100000),
    ),
    Some(100000),
  )
  assert_eq(
    local_managed_advance_control_work_limit(
      local_managed_provider_failure(@connector.InvalidLimits, 100000),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_control_work_limit(
      local_managed_provider_failure(@connector.ControlWorkLimit, 51),
    ),
    Some(51),
  )
  for
    issue in [
      Execution(@strategy.Physical(@resources.ExecutionLimit)),
      Execution(@strategy.Physical(@resources.RetentionLimit)),
      Configuration(
        @connector.Execution(@execution.Rows(3, @execution.RowLimit)),
      ),
      Configuration(@connector.Execution(@execution.InputLimit)),
      Configuration(@connector.ControlWorkLimit),
      ControlWorkLimit(-1),
      Configuration(@connector.InvalidLimits),
      Configuration(@connector.InputUnavailable),
      Execution(@strategy.Stopped),
    ] {
    assert_eq(local_managed_advance_control_work_limit(issue), None)
  }
}
