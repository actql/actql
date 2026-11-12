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

///|
test "managed advance preserves the original Capture step and selected work allowance without classifying generic bounds" {
  let original = Configuration(
    @connector.Execution(
      @execution.Capture(41, @execution.CaptureWorkLimit(100000)),
    ),
  )
  assert_eq(local_managed_advance_capture_work(original), Some([41, 100000]))
  assert_eq(local_managed_advance_control_work_limit(original), None)
  for
    issue in [
      Configuration(
        @connector.Execution(@execution.Capture(41, @execution.CaptureLimit)),
      ),
      Configuration(
        @connector.Execution(
          @execution.Capture(-1, @execution.CaptureWorkLimit(100000)),
        ),
      ),
      Configuration(
        @connector.Execution(
          @execution.Capture(41, @execution.CaptureWorkLimit(-1)),
        ),
      ),
      Execution(@strategy.Physical(@resources.ExecutionLimit)),
      Configuration(
        @connector.Execution(@execution.Rows(41, @execution.RowLimit)),
      ),
      ControlWorkLimit(100000),
    ] {
    assert_eq(local_managed_advance_capture_work(issue), None)
  }
}
