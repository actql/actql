///|
test "managed advance bridge retains only the typed failed-result work cause" {
  assert_eq(
    local_managed_advance_failure_kind(
      Err(@local_driver.Configuration(@connector.ControlWorkLimit)),
    ),
    Some("control_work"),
  )
  assert_eq(
    local_managed_advance_failure_kind(
      Err(
        @local_driver.Execution(@strategy.Physical(@resources.ExecutionLimit)),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_failure_kind(
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Rows(0, @execution.RowLimit)),
        ),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_failure_kind(
      Ok({
        complete: false,
        waiting: false,
        settlement: None,
        progress: 1L,
        work: 1L,
      }),
    ),
    None,
  )
}
