///|
/// Portable typed returns share the same original construction occupancy.
/// Node's raw JavaScript callback exceptions require its separate fixed scope.
fn closed_values_module_call(
  body : () -> Result[Unit, ClientClosedValuesPreparationIssue],
  finish : () -> Unit,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  defer finish()
  body()
}
