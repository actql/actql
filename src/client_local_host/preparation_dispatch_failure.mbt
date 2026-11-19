///|
// Entry controls are paid by the existing capture before any later dispatch:
// original-body/holder/current observations (8 shells H8/R4/W8), the extent
// Result+pair (H2/R2/W1), three checked sums (H3/W3), current/task/report
// rechecks and return/error alternatives (H5/R4/W14), the fixed Node callback
// plus environment (H2/R3), the scope's attempted-read latch and the
// existing Node explanation record's acknowledged dispatch-ready bit (W2).
// Both typed accessor results coexist through the current recheck: two
// Some+task/issue tuples (4H/4R/4W), four issue/kind reference roots and two
// report-eligibility/recheck words (4R/2W). These fixed 176 bytes are paid
// BEFORE either accessor, by the same original capture construction.
// The SAME Run publication-holder lookup retains its selected reference and
// Result alternatives across current (2H/3R/2W = 72 bytes). A pre-adoption
// construction-input loan remains lifetime-only, never a running grow port.
// Sequential alternatives are conservatively co-counted, not refunded.
let original_dispatch_failure_entry_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 26L,
    reference_slots: 24L,
    scalar_words: 36L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
// Complete simultaneous bounded DATA, not a wire/history/graph copy:
// Common tuple H1/R4/W4, array H1/W1, Some+Ok H2/R2/W2;
// Node DTO H1/R6/W4, array H1/W1, weak entry H1/R2, cached wrapper H1/R1.
// Common Array::makei and Node map callback/environments H4/R2 coexist
// conservatively with both arrays until projection is complete.
// Each item co-counts Common pair+optional code H2/R2/W2, array slot R1,
// Node record H1/R1/W1 and array slot R1. Codes are borrowed module literals.
let original_dispatch_failure_fixed_bytes : Int64 = 424L

///|
let original_dispatch_failure_item_bytes : Int64 = 112L

///|
/// Optional failure DATA from the SAME existing Run/Request capture and
/// configured dispatch. It neither retries search nor repeats a feasibility
/// or implementation callback. One attempt is latched before current/grow:
/// refusal, retirement or reentry cannot replace or reobserve the primary.
pub fn observe_installed_original_dispatch_failure(
  value : ClientOriginalExplanationCapture,
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Result[
  (String, String, Int, Int, Bool, Bool, Array[(Int, String?)], String)?,
  ClientOriginalExplanationCaptureIssue,
] {
  guard !value.dispatch_failure_observed &&
    original_explanation_capture_body(value) is Some(prepared) &&
    value.original is Some((run, _, _)) else {
    return Ok(None)
  }
  let captured = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(host),
  )
  let runtime = @builtin.configured_host_runtime(host)
  guard run.source_free_captured is Some(original) &&
    physical_equal(original, captured) &&
    run.ledger is Some(ledger) &&
    physical_equal(ledger, @strategy.captured_dag_ledger(captured)) &&
    @host_driver.compute_host_original_estimate_failure(runtime)
    is Some((task, failure)) else {
    return Ok(None)
  }
  value.dispatch_failure_observed = true
  guard require_installed_managed_run(run) is Ok(_) else {
    return Err(ForeignOriginal)
  }
  // The normal manager retained this capture before adoption. Its original
  // construction-input holder observes lifetime, but intentionally cannot
  // grow a running phase. Use the SAME Run's existing publication body;
  // neither another borrower nor a replacement preparation is issued here.
  let holder = match managed_run_publication_body(run, prepared) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  let kind = match failure {
    NoStrategy => "no_strategy"
    InvalidConfiguration => "invalid_configuration"
    ForeignSelection => "foreign_selection"
    EstimateOverflow => "estimate_overflow"
    Resources(_) => "resources"
    Search(_) => "search"
    Implementation(_) => "implementation"
  }
  // Only NoStrategy was issued by this search's completed/deferred decision.
  // Other Estimate variants can precede search and leave an older report.
  let has_report = failure is NoStrategy
  let total = if has_report {
    @strategy.strategy_report_count(captured)
  } else {
    0
  }
  let count = Int::min(8, total)
  let complete = has_report && @strategy.strategy_report_complete(captured)
  let (retained, execution) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(Capacity(issue))
    Ok(extents) => extents
  }
  guard @execution.checked_preparation_add_product(
      original_dispatch_failure_fixed_bytes,
      count.to_int64(),
      original_dispatch_failure_item_bytes,
    )
    is Some(extra) &&
    @execution.checked_preparation_add_product(retained, extra, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(execution, extra, 1L) is Some(e) else {
    return Err(ConstructionUnavailable)
  }
  // Later phases share this holder. Grow its CURRENT extents; never reuse a
  // stale base/max that could overlap a sibling's still-live material.
  match
    @resources.reserve_preparation_publication_phase(holder, prepared, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard require_installed_managed_run(run) is Ok(_) &&
    original_explanation_capture_body(value) is Some(current) &&
    physical_equal(prepared, current) &&
    run.source_free_captured is Some(original) &&
    physical_equal(original, captured) &&
    @host_driver.compute_host_original_estimate_failure(runtime)
    is Some((current_task, current_failure)) &&
    current_task == task &&
    physical_equal(current_failure, failure) &&
    (
      !has_report ||
      (
        @strategy.strategy_report_count(captured) == total &&
        @strategy.strategy_report_complete(captured) == complete
      )
    ) else {
    return Err(ForeignOriginal)
  }
  value.held_retained = r
  value.held_execution = e
  let assessments = Array::makei(count, index => {
    let original = @strategy.strategy_report_at(captured, index).unwrap()
    (original.position, @strategy.strategy_assessment_rejection_code(original))
  })
  // The collapsed decision and feasible-count were not retained. Do not
  // manufacture them from a stopped driver, report length or error shape.
  Ok(
    Some(
      (
        "adaptive_dispatch",
        kind,
        task,
        total,
        complete,
        total > count,
        assessments,
        "unavailable",
      ),
    ),
  )
}
