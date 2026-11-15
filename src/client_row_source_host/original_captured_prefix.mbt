///|
// Return only the original checked requirement after same-Ledger/token/phase
// checks. Never project the capture's Ledger or resource tokens to a caller.
// This remains data/custody, not Source permission or Model admission.
pub fn row_capture_original_prefix_requirement(
  capture : RowSourceCapture,
  ledger : @resources.Ledger,
  prefix? : @resources.Reservation? = None,
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
    (match prefix {
      None =>
        @resources.original_captured_prefix_available(
          ledger,
          physical.reservation,
          holding,
        )
      Some(token) =>
        @resources.original_captured_prefix_reservation_available(
          ledger,
          physical.reservation,
          holding,
          token,
        )
    }) else {
    return None
  }
  Some(configuration.requirement)
}

///|
/// Borrow this exact accounted capture among its original Run's live children.
/// This does not claim the legacy standalone prefix opportunity or issue a
/// Source read. Every original token remains a live member of the same census.
pub fn row_capture_original_borrowed_requirement(
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
  // The original transport verifier may synchronously close this same Run.
  // Check all custody after it returns; neither equal bytes nor a dead token
  // can replace the original allocation retained by the accounted Row owner.
  guard !run.closed &&
    run.physical is Some(physical) &&
    physical_equal(physical.ledger, ledger) &&
    physical.dag is None &&
    physical.holding is Some(holding) &&
    @resources.original_borrowed_captured_allocation_available(
      ledger,
      physical.reservation,
      holding,
    ) else {
    return None
  }
  Some(configuration.requirement)
}
