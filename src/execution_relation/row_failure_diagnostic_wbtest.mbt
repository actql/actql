///|
test "closed row diagnosis preserves remaining row constructors without a dimension or payload inference" {
  let cases : Array[(RowIssue, String)] = [
    (OwnerMismatch, "rows.owner_mismatch"),
    (InputMismatch, "rows.input_mismatch"),
    (InvalidRows, "rows.invalid_rows"),
    (MissingOrderedResourceContext, "rows.missing_ordered_resource_context"),
    (LogicalRows(InvalidLogicalLimits), "logical.invalid_limits"),
    (LogicalRows(FailedLogicalBudget), "logical.failed_budget"),
    (LogicalRows(InputRowLimit), "logical.input_row_limit"),
    (LogicalRows(WorkLimit), "logical.work_limit"),
    (LogicalRows(LiveValueLimit), "logical.live_value_limit"),
    (LogicalRows(InvalidRootLifetime), "logical.invalid_root_lifetime"),
    (
      LogicalRows(ValueMeasure(InvalidMeasureLimits)),
      "logical.measure.invalid_limits",
    ),
    (LogicalRows(ValueMeasure(LogicalWorkLimit)), "logical.measure.work_limit"),
    (LogicalRows(ValueMeasure(HostMeasureLimit)), "logical.measure.host_limit"),
    (
      LogicalRows(ValueMeasure(WireMeasureFailure)),
      "logical.measure.wire_failure",
    ),
    (
      LogicalRows(ValueMeasure(ReferenceUnavailable)),
      "logical.measure.reference_unavailable",
    ),
    (WindowTime(999), "window.time"),
    (WindowArithmetic(999), "window.arithmetic"),
    (AnalyticEnvelope(InputWireBytes), "analytic.input_wire_bytes"),
    (AnalyticEnvelope(OutputWireBytes), "analytic.output_wire_bytes"),
    (AnalyticEnvelope(PartitionWireBytes), "analytic.partition_wire_bytes"),
    (AnalyticEnvelope(FrameMemberships), "analytic.frame_memberships"),
    (AnalyticEnvelope(OutputRows), "analytic.output_rows"),
    (AnalyticEnvelope(Measurement), "analytic.measurement"),
    (NestItemLimitRequired, "nest.item_limit_required"),
    (NestItemLimit(999), "nest.item_limit"),
    (NestEnvelope(GroupedBytes), "nest.grouped_bytes"),
    (NestEnvelope(AttachedBytes), "nest.attached_bytes"),
    (NestEnvelope(Measurement), "nest.measurement"),
  ]
  for (original, expected) in cases {
    assert_eq(row_failure_diagnostic_cause(original), Some(expected))
  }
}

///|
test "closed evaluation diagnosis keeps original logical cause and never renders the original expression" {
  let expression = lowered("\"'private-payload'\"")
  let causes : Array[(EvalIssueKind, String)] = [
    (InvalidControlLimits, "evaluation.invalid_control_limits"),
    (ControlLimit, "evaluation.control_limit"),
    (WorkspaceLimit, "evaluation.workspace_limit"),
    (LogicalEntry(InvalidLogicalLimits), "logical.invalid_limits"),
    (LogicalEntry(WorkLimit), "logical.work_limit"),
    (LogicalValue(LiveValueLimit), "logical.live_value_limit"),
    (LogicalValue(ValueMeasure(HostMeasureLimit)), "logical.measure.host_limit"),
  ]
  for (kind, expected) in causes {
    let original : EvalIssue = { kind, expression, }
    assert_eq(
      row_failure_diagnostic_cause(Evaluation(991, 992, original)),
      Some(expected),
    )
    assert_true(physical_equal(original.expression, expression))
    assert_eq(original.kind, kind)
  }
}
