///|
// Consumers requiring an operation proof must not cast an acquired input
// ceiling into a fabricated StepBound. Source-root conversion is separate.
fn require_step_target_rows(
  rows : @step_bounds.TargetRows,
) -> @step_bounds.StepBound raise UnitBuildFailure {
  match @step_bounds.target_rows_bound(rows) {
    Some(bound) => bound
    None => raise UnconvertedProofInput
  }
}
