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
