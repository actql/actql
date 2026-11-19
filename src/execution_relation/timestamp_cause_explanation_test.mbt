///|
test "canonical timestamp cause describes its expected existing input form without the rejected value" {
  let explanation = row_failure_diagnostic_explanation(
    "evaluation.timestamp_canonical_required",
  ).unwrap()
  assert_eq(
    explanation, "Expected a canonical UTC TIMESTAMP such as 2026-01-02T03:04:05.123Z: use T, Z and 3-9 fractional digits, with no redundant trailing zeros beyond 3 digits; no spaces or offsets.",
  )
  // This static catalogue value remains well inside the existing 512-unit
  // terminal-message envelope even with maximal task/step decimal ordinals.
  assert_true(explanation.length() < 256)
}

///|
test "unregistered causes and arbitrary text do not select a timestamp explanation" {
  for
    cause in [
      "",
      "evaluation.invalid_operand",
      "evaluation.timestamp_pattern_invalid",
      "TimestampCanonicalRequired",
      "evaluation.timestamp_canonical_required ",
      "evaluation.timestamp_canonical_required\n",
      "private-value".repeat(100),
    ] {
    assert_eq(row_failure_diagnostic_explanation(cause), None)
  }
}
