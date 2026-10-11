///|
type PrivateFileProjection

///|
pub fn PrivateFileProjection::export_original(
  _self : PrivateFileProjection,
) -> Result[Bytes, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::restore_private_file_projection(
  _self : Root,
  _original : Bytes,
) -> Result[PrivateFileProjection, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::adopt_private_file_projection(
  _self : Root,
  _name : String,
) -> Result[PrivateFileProjection, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}
