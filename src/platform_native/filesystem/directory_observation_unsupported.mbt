///|
type NativeDirectoryObservation

///|
pub fn Root::observe_directory(
  _self : Root,
) -> Result[NativeDirectoryObservation, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeDirectoryObservation::check_current(
  _self : NativeDirectoryObservation,
) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeDirectoryObservation::identity(
  _self : NativeDirectoryObservation,
) -> Result[NativeFileOwnership, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}
