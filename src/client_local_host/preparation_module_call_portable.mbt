///|
/// Portable typed returns share the same original construction occupancy.
/// Node's raw JavaScript callback exceptions require its separate fixed scope.
fn[T, E] preparation_module_call(
  body : () -> Result[T, E],
  finish : () -> Unit,
) -> Result[T, E] {
  defer finish()
  body()
}

///|
// Only the JS boundary can receive an untyped foreign throw. Portable typed
// callbacks cannot raise one; retain the same nominal failure slot unused.
#warnings("-struct_never_constructed")
pub struct QueryBindingForeignFailure {
  cause : Error
}

///|
fn[T] query_binding_protected_call(
  body : () -> Result[T, ClientRequestPreparationIssue],
  finish : () -> Unit,
) -> Result[
  Result[T, ClientRequestPreparationIssue],
  QueryBindingForeignFailure,
] {
  defer finish()
  Ok(body())
}
