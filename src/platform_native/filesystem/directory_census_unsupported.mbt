///|
pub fn Root::check_directory_members(
  _self : Root,
  _expected : Array[NativeDirectoryMember],
  command_preparation? : Bool = false,
) -> Result[Unit, NativeFilesystemIssue] {
  ignore(command_preparation)
  Err(UnsupportedTarget)
}
