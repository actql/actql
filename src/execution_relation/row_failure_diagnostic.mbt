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
        // These carry a different resource/lifetime domain. Do not infer a
        // memory setting or treat them as a scalar semantic failure.
        _ => None
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
    _ => None
  }
}
