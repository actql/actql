///|
// Return only the original checked requirement after same-Ledger/token/phase
// checks. Never project the capture's Ledger or resource tokens to a caller.
// This remains data/custody, not Source permission or Model admission.
pub fn row_capture_original_prefix_requirement(
  capture : RowSourceCapture,
  ledger : @resources.Ledger,
) -> @planning.QueryRequirement? {
  let run = capture.run
  guard !run.closed &&
    run.configuration is DirectConfiguration(configuration) &&
    run.physical is Some(physical) &&
    physical_equal(physical.ledger, ledger) &&
    physical.dag is None &&
    physical.holding is Some(holding) &&
    @resources.original_captured_prefix_available(
      ledger, physical.reservation, holding,
    ) &&
    row_capture_source(capture) is Ok(_) else {
    return None
  }
  Some(configuration.requirement)
}
