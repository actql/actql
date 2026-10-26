///|
/// Clear synchronous construction occupancy after foreign callback unwind.
/// This finalizer never clears an original, reservation, borrower or resource.
extern "js" fn closed_values_module_call(
  body : () -> Result[Unit, ClientClosedValuesPreparationIssue],
  finish : () -> Unit,
) -> Result[Unit, ClientClosedValuesPreparationIssue] =
  #|(body,finish) => { try { return body(); } finally { finish(); } }
