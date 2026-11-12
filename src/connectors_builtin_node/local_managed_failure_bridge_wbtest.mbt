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

///|
test "managed resource bridge retains the original failed-result dimension" {
  assert_eq(
    local_managed_advance_resource_dimension(
      Err(
        @local_driver.Execution(@strategy.Physical(@resources.RetentionLimit)),
      ),
    ),
    Some("retained_bytes"),
  )
  assert_eq(
    local_managed_advance_resource_dimension(
      Err(@local_driver.Execution(@strategy.Physical(@resources.ForeignOwner))),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_resource_dimension(
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

///|
test "managed advance Capture bridge keeps the SAME Result typed step and allowance only" {
  assert_eq(
    local_managed_advance_capture_work(
      Err(
        @local_driver.Configuration(
          @connector.Execution(
            @execution.Capture(41, @execution.CaptureWorkLimit(100000)),
          ),
        ),
      ),
    ),
    Some([41, 100000]),
  )
  assert_eq(
    local_managed_advance_capture_work(
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Capture(41, @execution.CaptureLimit)),
        ),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_capture_work(
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
