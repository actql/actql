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
test "managed nonrow causes keep missing row step and never classify a quota dimension" {
  let cases : Array[(LocalDispatchIssue, String?)] = [
    (Execution(@strategy.Stopped), Some("execution.stopped")),
    (
      Execution(@strategy.Physical(@resources.ForeignOwner)),
      Some("resource.foreign_owner"),
    ),
    (
      Configuration(@connector.InputUnavailable),
      Some("compute.input_unavailable"),
    ),
    (
      Configuration(@connector.Execution(@execution.InputLimit)),
      Some("sequence.input_limit"),
    ),
    (
      Configuration(
        @connector.Execution(@execution.Rows(-1, @execution.RowLimit)),
      ),
      None,
    ),
    (ControlWorkLimit(100), Some("local.control_work_limit")),
  ]
  for (issue, expected) in cases {
    assert_eq(local_managed_failure_cause(issue), expected)
    assert_eq(local_managed_failure_row_step(issue), -1)
    assert_eq(local_managed_failure_resource_dimension(issue), None)
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

///|
test "managed closed cause projects original nonrow constructors without payloads or a quota inference" {
  let cases : Array[(LocalDispatchIssue, String)] = [
    (Configuration(@connector.InvalidLimits), "compute.invalid_limits"),
    (Configuration(@connector.ForeignRequest(789)), "compute.foreign_request"),
    (
      Configuration(@connector.Execution(@execution.InputLimit)),
      "sequence.input_limit",
    ),
    (
      Configuration(
        @connector.Execution(@execution.Capture(42, @execution.CaptureLimit)),
      ),
      "capture.capture_limit",
    ),
    (
      Configuration(
        @connector.Execution(
          @execution.Capture(42, @execution.MissingParameter("private-payload")),
        ),
      ),
      "capture.missing_parameter",
    ),
    (
      Execution(@strategy.Compute(@connector.InvalidLimits)),
      "compute.invalid_limits",
    ),
    (Execution(@strategy.Stopped), "execution.stopped"),
    (
      Execution(@strategy.Physical(@resources.ForeignOwner)),
      "resource.foreign_owner",
    ),
    (
      Execution(@strategy.Physical(@resources.ResourceParked)),
      "resource.resource_parked",
    ),
    (
      Execution(@strategy.Implementation(Failure("private exception text"))),
      "execution.implementation",
    ),
    (Preparation(@local.NotSelected), "local.preparation"),
  ]
  for (original, expected) in cases {
    assert_eq(local_managed_failure_cause(original), Some(expected))
    assert_eq(local_managed_failure_row_step(original), -1)
    assert_eq(local_managed_failure_resource_dimension(original), None)
    assert_eq(local_managed_advance_control_work_limit(original), None)
    assert_eq(local_managed_advance_capture_work(original), None)
    assert_eq(local_managed_failure_budget(original), None)
  }
}

///|
test "logical work failure keeps actual policy and closed origin without fabricated amounts" {
  for
    (origin, limit, setting) in [
      (SourceFreeInstallation, 20000000L, "installation.sourceFreeMaxWork"),
      (Unspecified, 10000000L, "unavailable"),
      (Unspecified, 20000000L, "unavailable"),
    ] {
    let issue = LogicalWorkLimit(43, limit, origin)
    assert_eq(
      local_managed_advance_logical_work_policy(issue),
      Some((43, limit, setting)),
    )
    assert_eq(local_managed_failure_cause(issue), Some("logical.work_limit"))
    assert_eq(local_managed_failure_row_step(issue), 43)
    assert_eq(local_managed_failure_budget(issue), None)
    assert_eq(local_managed_failure_resource_dimension(issue), None)
    assert_eq(local_managed_advance_control_work_limit(issue), None)
  }
  for
    issue in [
      Configuration(
        @connector.Execution(@execution.Rows(43, @execution.RowLimit)),
      ),
      Execution(@strategy.Stopped),
      Execution(@strategy.Physical(@resources.ForeignOwner)),
      LogicalWorkLimit(-1, 20000000L, SourceFreeInstallation),
      LogicalWorkLimit(43, -1L, SourceFreeInstallation),
    ] {
    assert_eq(local_managed_advance_logical_work_policy(issue), None)
  }
}
