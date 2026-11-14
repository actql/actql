///|
test "retained preparation control work keeps its original typed phase distinct from other resource failures" {
  let original = @local_driver.Preparation(
    @local_connector.Materializing(
      @local_connector.Candidate(@connector.ControlWorkLimit),
    ),
  )
  assert_true(strategy_fixture_retained_control_work_limit(original))
  assert_false(strategy_fixture_retained_row_limit(original))
  for
    other in [
      @local_driver.Configuration(@connector.ControlWorkLimit),
      @local_driver.ControlWorkLimit(51),
      @local_driver.Preparation(
        @local_connector.Materializing(
          @local_connector.Candidate(
            @connector.Execution(@execution.InputLimit),
          ),
        ),
      ),
      @local_driver.Preparation(
        @local_connector.Materializing(
          @local_connector.Candidate(
            @connector.Execution(@execution.Rows(0, @execution.RowLimit)),
          ),
        ),
      ),
      @local_driver.Configuration(
        @connector.Execution(
          @execution.Capture(0, @execution.CaptureWorkLimit(51)),
        ),
      ),
      @local_driver.Configuration(
        @connector.Execution(@execution.Capture(0, @execution.CaptureLimit)),
      ),
    ] {
    assert_false(strategy_fixture_retained_control_work_limit(other))
  }
}
