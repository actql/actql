///|
// Return only the original checked requirement after same-Ledger/token/phase
// checks. Never project the capture's Ledger or resource tokens to a caller.
// This remains data/custody, not Source permission or Model admission.
pub fn row_capture_original_prefix_requirement(
  capture : RowSourceCapture,
  ledger : @resources.Ledger,
) -> @planning.QueryRequirement? {
  let run = capture.run
  guard run.configuration is DirectConfiguration(configuration) &&
    row_capture_source(capture) is Ok(source) &&
    @query.captured_source_matches_query(
      source,
      @planning.query_material_owner(
        @planning.query_requirement_material(configuration.requirement),
      ),
    ) else {
    return None
  }
  // Liveness invokes the original transport verifier. Recheck all custody
  // and phase facts AFTER that callback, including synchronous cancellation.
  guard !run.closed &&
    run.physical is Some(physical) &&
    physical_equal(physical.ledger, ledger) &&
    physical.dag is None &&
    physical.holding is Some(holding) &&
    @resources.original_captured_prefix_available(
      ledger,
      physical.reservation,
      holding,
    ) else {
    return None
  }
  Some(configuration.requirement)
}
