///|
/// Closed cause DATA from the original row failure. Never format the retained
/// expression, field names, row values or exception text. A RowLimit alone
/// does not identify memory versus control/workspace, or retain any amounts.
pub fn row_failure_diagnostic_cause(issue : RowIssue) -> String? {
  match issue {
    Evaluation(_, _, original) =>
      match original.kind {
        Scalar(InvalidOperand) => Some("evaluation.invalid_operand")
        Scalar(ArithmeticFailure) => Some("evaluation.arithmetic_failure")
        Scalar(ComparisonDomainNotImplemented) =>
          Some("evaluation.comparison_domain_not_implemented")
        MissingValue => Some("evaluation.missing_value")
        QueryEvaluationTimeUnavailable =>
          Some("evaluation.query_evaluation_time_unavailable")
        NumberConversion(_) => Some("evaluation.number_conversion_failure")
        TimestampCanonicalRequired =>
          Some("evaluation.timestamp_canonical_required")
        InvalidControlLimits => Some("evaluation.invalid_control_limits")
        ControlLimit => Some("evaluation.control_limit")
        WorkspaceLimit => Some("evaluation.workspace_limit")
        LogicalEntry(original) | LogicalValue(original) =>
          Some(row_logical_failure_diagnostic_cause(original))
        TextBounds(cause) =>
          match cause {
            @text_bounds.InvalidLimits =>
              Some("evaluation.text_bounds.invalid_limits")
            @text_bounds.BudgetExceeded =>
              Some("evaluation.text_bounds.budget_exceeded")
            @text_bounds.InvalidInputType =>
              Some("evaluation.text_bounds.invalid_input_type")
            @text_bounds.InputCeiling =>
              Some("evaluation.text_bounds.input_ceiling")
            @text_bounds.OutputCeiling =>
              Some("evaluation.text_bounds.output_ceiling")
            @text_bounds.ReplacementCeiling =>
              Some("evaluation.text_bounds.replacement_ceiling")
            @text_bounds.InvalidPatternMode =>
              Some("evaluation.text_bounds.invalid_pattern_mode")
          }
      }
    Comparison(InvalidOperand) => Some("comparison.invalid_operand")
    Comparison(ArithmeticFailure) => Some("comparison.arithmetic_failure")
    Comparison(ComparisonDomainNotImplemented) =>
      Some("comparison.comparison_domain_not_implemented")
    Aggregation(InvalidOperand) => Some("aggregation.invalid_operand")
    Aggregation(ArithmeticFailure) => Some("aggregation.arithmetic_failure")
    Aggregation(ComparisonDomainNotImplemented) =>
      Some("aggregation.comparison_domain_not_implemented")
    RowLimit => Some("rows.row_limit")
    InvalidRowLimits => Some("rows.invalid_limits")
    AssertionPredicate(_) => Some("assertion.predicate_failed")
    AssertionNullKey(_, _) => Some("assertion.null_key")
    AssertionDuplicate(_, _) => Some("assertion.duplicate_key")
    JoinNullKey(_, _, _) => Some("join.null_key")
    JoinDuplicateKey(_, _, _) => Some("join.duplicate_key")
    DedupeTopTie(_, _) => Some("dedupe.top_tie")
    DedupeIdentityCollision => Some("dedupe.identity_collision")
    AsOfTopTie(_, _, _) => Some("asof.top_tie")
    TemporalPrecisionUnavailable => Some("rows.temporal_precision_unavailable")
    OwnerMismatch => Some("rows.owner_mismatch")
    InputMismatch => Some("rows.input_mismatch")
    InvalidRows => Some("rows.invalid_rows")
    MissingOrderedResourceContext =>
      Some("rows.missing_ordered_resource_context")
    LogicalRows(original) =>
      Some(row_logical_failure_diagnostic_cause(original))
    WindowTime(_) => Some("window.time")
    WindowArithmetic(_) => Some("window.arithmetic")
    AnalyticEnvelope(original) =>
      Some(
        match original {
          InputWireBytes => "analytic.input_wire_bytes"
          OutputWireBytes => "analytic.output_wire_bytes"
          PartitionWireBytes => "analytic.partition_wire_bytes"
          FrameMemberships => "analytic.frame_memberships"
          OutputRows => "analytic.output_rows"
          Measurement => "analytic.measurement"
        },
      )
    NestItemLimitRequired => Some("nest.item_limit_required")
    NestItemLimit(_) => Some("nest.item_limit")
    NestEnvelope(original) =>
      Some(
        match original {
          GroupedBytes => "nest.grouped_bytes"
          AttachedBytes => "nest.attached_bytes"
          Measurement => "nest.measurement"
        },
      )
  }
}

///|
/// Only the closed logical-work constructor selects this dimension. Generic
/// RowLimit, control/workspace, failed-budget and live-value refusals do not.
pub fn row_failure_is_logical_work_limit(issue : RowIssue) -> Bool {
  match issue {
    LogicalRows(WorkLimit) => true
    Evaluation(_, _, original) =>
      match original.kind {
        LogicalEntry(WorkLimit) | LogicalValue(WorkLimit) => true
        _ => false
      }
    _ => false
  }
}

///|
// The same LogicalBudget owner supplies these constructors in row and scalar
// contexts. Preserve its original reason without formatting payloads, adding
// a second decision table in Node, or guessing a physical dimension/setting.
fn row_logical_failure_diagnostic_cause(issue : LogicalBudgetIssue) -> String {
  match issue {
    InvalidLogicalLimits => "logical.invalid_limits"
    FailedLogicalBudget => "logical.failed_budget"
    InputRowLimit => "logical.input_row_limit"
    WorkLimit => "logical.work_limit"
    LiveValueLimit => "logical.live_value_limit"
    InvalidRootLifetime => "logical.invalid_root_lifetime"
    ValueMeasure(original) =>
      match original {
        InvalidMeasureLimits => "logical.measure.invalid_limits"
        LogicalWorkLimit => "logical.measure.work_limit"
        HostMeasureLimit => "logical.measure.host_limit"
        WireMeasureFailure => "logical.measure.wire_failure"
        ReferenceUnavailable => "logical.measure.reference_unavailable"
      }
  }
}

///|
/// Presentation DATA for an existing closed execution cause, not evidence
/// that a failure occurred. Never inspect or echo the rejected input value.
/// The canonical TIMESTAMP conversion boundary owns this fixed explanation;
/// pattern-based PARSE/FORMAT keep their separate existing grammar.
pub fn row_failure_diagnostic_explanation(cause : String) -> String? {
  if cause == "evaluation.timestamp_canonical_required" {
    Some(
      "Expected a canonical UTC TIMESTAMP such as 2026-01-02T03:04:05.123Z: use T, Z and 3-9 fractional digits, with no redundant trailing zeros beyond 3 digits; no spaces or offsets.",
    )
  } else {
    None
  }
}
