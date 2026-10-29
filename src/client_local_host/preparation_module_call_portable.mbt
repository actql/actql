///|
/// Portable typed returns share the same original construction occupancy.
/// Node's raw JavaScript callback exceptions require its separate fixed scope.
fn[E] preparation_module_call(
  body : () -> Result[Unit, E],
  finish : () -> Unit,
) -> Result[Unit, E] {
  defer finish()
  body()
}
