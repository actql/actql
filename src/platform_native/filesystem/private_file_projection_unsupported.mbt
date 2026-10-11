///|
type PrivateFileProjection

///|
pub fn Root::adopt_private_file_projection(
  _self : Root,
  _name : String,
) -> Result[PrivateFileProjection, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}
