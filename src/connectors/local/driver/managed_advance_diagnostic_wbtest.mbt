///|
test "managed advance diagnoses only the original control-work constructor" {
  assert_eq(
    local_managed_advance_failure_kind(
      Configuration(@connector.ControlWorkLimit),
    ),
    Some("control_work"),
  )
  for
    issue in [
      Execution(@strategy.Physical(@resources.ExecutionLimit)),
      Execution(@strategy.Physical(@resources.RetentionLimit)),
      Configuration(
        @connector.Execution(@execution.Rows(3, @execution.RowLimit)),
      ),
      Configuration(@connector.Execution(@execution.InputLimit)),
      Configuration(@connector.InvalidLimits),
      Configuration(@connector.InputUnavailable),
      Execution(@strategy.Stopped),
    ] {
    assert_eq(local_managed_advance_failure_kind(issue), None)
  }
}
