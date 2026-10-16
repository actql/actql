///|
/// Consume the same-run charge for a bounded non-row protocol response.
/// This acknowledges byte-ticket consumption only: it appends no row, finishes
/// no scan, issues no evidence and does not confirm physical transport cleanup.
pub fn consume_row_run_response_charge(
  run : RowRun,
  charge : RowPageCharge,
) -> Result[Unit, RowHostIssue] {
  consume_row_page_charge(run, charge)
}
