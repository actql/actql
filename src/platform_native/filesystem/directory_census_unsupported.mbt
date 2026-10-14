///|
pub fn Root::check_directory_members(
  _self : Root,
  _expected : Array[NativeDirectoryMember],
) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}
