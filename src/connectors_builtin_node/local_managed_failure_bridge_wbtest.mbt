///|
test "managed advance bridge retains only the typed failed-result work cause" {
  assert_eq(
    local_managed_advance_control_work_limit(
      Err(@local_driver.ControlWorkLimit(100000)),
    ),
    Some(100000),
  )
  assert_eq(
    local_managed_advance_control_work_limit(
      Err(
        @local_driver.Execution(@strategy.Physical(@resources.ExecutionLimit)),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_control_work_limit(
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Rows(0, @execution.RowLimit)),
        ),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_control_work_limit(
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
