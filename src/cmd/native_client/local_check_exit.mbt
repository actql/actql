///|
// Presentation status for this single CLI invocation, never Run state or an
// authorization. Only local_check_for_host sets it from the original outcome.
let command_check_invalid_exit : Ref[Bool] = Ref(false)

///|
// Project only the existing completed CheckOutcome's original verdict. This
// does not check the Program again, interpret reason text or use runnable as
// validity. The report body is preserved unchanged for stdout.
fn local_check_invalid_exit(wire : String) -> Bool raise ClientStop {
  let root = @decode.open_object(local_input_cursor(wire)).unwrap_or_else(() => {
    stop("LocalCheckOutcomeUnavailable")
  })
  let text = fn(object, name) {
    @decode.lookup(object, name).bind(value => @decode.text(value).to_option())
  }
  let (reason, outcome) = @preparation.client_program_check_reporting_schema_cids()
  if text(root, "version") != Some("actql-check-outcome/0.1") ||
    text(root, "reason_schema_cid") != Some(reason) ||
    text(root, "outcome_schema_cid") != Some(outcome) {
    stop("LocalCheckOutcomeUnavailable")
  }
  if text(root, "outcome") != Some("completed") {
    return false // Preserve the other original outcome paths independently.
  }
  guard @decode.lookup(root, "report") is Some(report) &&
    @decode.open_object(report) is Ok(report) else {
    stop("LocalCheckOutcomeUnavailable")
  }
  match text(report, "verdict") {
    Some("invalid") => true
    Some("verified" | "undetermined") => false
    _ => stop("LocalCheckOutcomeUnavailable")
  }
}
