///|
test "managed row cause preserves the original typed branch and step without a quota inference" {
  for
    original in [
      Configuration(
        @connector.Execution(
          @execution.Rows(
            41,
            @execution.Comparison(@execution.ArithmeticFailure),
          ),
        ),
      ),
      Execution(
        @strategy.Compute(
          @connector.Execution(
            @execution.Rows(
              41,
              @execution.Comparison(@execution.ArithmeticFailure),
            ),
          ),
        ),
      ),
    ] {
    assert_eq(
      local_managed_failure_cause(original),
      Some("comparison.arithmetic_failure"),
    )
    assert_eq(local_managed_failure_row_step(original), 41)
    assert_eq(local_managed_failure_resource_dimension(original), None)
    assert_eq(local_managed_failure_budget(original), None)
  }
  let row_limit = Configuration(
    @connector.Execution(@execution.Rows(42, @execution.RowLimit)),
  )
  assert_eq(local_managed_failure_cause(row_limit), Some("rows.row_limit"))
  assert_eq(local_managed_failure_row_step(row_limit), 42)
  assert_eq(local_managed_failure_resource_dimension(row_limit), None)
  assert_eq(local_managed_failure_budget(row_limit), None)
}

///|
test "managed row cause does not classify success current foreign cleanup or generic input refusal" {
  for
    issue in [
      Execution(@strategy.Stopped),
      Execution(@strategy.Physical(@resources.ForeignOwner)),
      Configuration(@connector.InputUnavailable),
      Configuration(@connector.Execution(@execution.InputLimit)),
      Configuration(
        @connector.Execution(@execution.Rows(-1, @execution.RowLimit)),
      ),
      ControlWorkLimit(100),
    ] {
    assert_eq(local_managed_failure_cause(issue), None)
    assert_eq(local_managed_failure_row_step(issue), -1)
  }
}

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
test "managed resource diagnostic projects only exact physical quota causes" {
  assert_eq(
    local_managed_failure_resource_dimension(
      Execution(@strategy.Physical(@resources.RetentionLimit)),
    ),
    Some("retained_bytes"),
  )
  assert_eq(
    local_managed_failure_resource_dimension(
      Execution(@strategy.Physical(@resources.ExecutionLimit)),
    ),
    Some("execution_bytes"),
  )
  for
    issue in [
      Execution(@strategy.Physical(@resources.ForeignOwner)),
      Execution(@strategy.Physical(@resources.InvalidCharge)),
      Execution(@strategy.Stopped),
      Configuration(@connector.InvalidLimits),
      Configuration(@connector.Execution(@execution.InputLimit)),
      ControlWorkLimit(100000),
    ] {
    assert_eq(local_managed_failure_resource_dimension(issue), None)
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

///|
test "original memory refusal retains failed delta remaining and policy without later ledger reads" {
  let issue = ExecutionCapacityRefusal(@resources.RetentionLimit, 19L, 7L, 512L)
  assert_eq(
    local_managed_failure_resource_dimension(issue),
    Some("retained_bytes"),
  )
  assert_eq(
    local_managed_failure_budget(issue),
    Some(("retained_bytes", true, 19L, 7L, 512L)),
  )
  assert_eq(
    local_managed_failure_budget(
      ExecutionCapacityRefusal(@resources.ExecutionLimit, 23L, 5L, 1024L),
    ),
    Some(("execution_bytes", true, 23L, 5L, 1024L)),
  )
  for
    issue in [
      ExecutionCapacityRefusal(@resources.ForeignOwner, 19L, 7L, 512L),
      ExecutionCapacityRefusal(@resources.RetentionLimit, 7L, 7L, 512L),
      ExecutionCapacityRefusal(@resources.RetentionLimit, 19L, -1L, 512L),
      Execution(@strategy.Physical(@resources.RetentionLimit)),
      Execution(@strategy.Stopped),
    ] {
    assert_eq(local_managed_failure_budget(issue), None)
  }
}

///|
test "original UTF8 work refusal retains remaining and only a proved demand lower bound" {
  let issue = Configuration(
    @connector.Execution(
      @execution.Capture(41, @execution.CaptureWorkRefusal(100, 7)),
    ),
  )
  assert_eq(local_managed_advance_capture_work(issue), Some([41, 100]))
  assert_eq(
    local_managed_failure_budget(issue),
    Some(("value_capture_work", false, 8L, 7L, 100L)),
  )
  assert_eq(
    local_managed_failure_budget(
      Configuration(
        @connector.Execution(
          @execution.Capture(41, @execution.CaptureWorkLimit(100)),
        ),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_failure_budget(
      Configuration(
        @connector.Execution(
          @execution.Capture(41, @execution.CaptureWorkRefusal(7, 8)),
        ),
      ),
    ),
    None,
  )
}
