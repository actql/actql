///|
/// Original physical installation facts retained by the private-root Owner.
/// This is neither a serialized generation nor an authorization token.
type PrivateFileProjection

///|
#borrow(root, name)
extern "C" fn adopt_private_file_projection_ffi(
  root : Root,
  name : Bytes,
  length : Int,
) -> PrivateFileProjection = "actql_native_filesystem_adopt_private_file_projection"

///|
#borrow(projection)
extern "C" fn private_file_projection_ready_ffi(
  projection : PrivateFileProjection,
) -> Bool = "actql_native_filesystem_private_file_projection_ready"

///|
/// Explicit installation admission, before preparation. Trusted Host assembly
/// must retain this original material; obtaining a fresh projection at send or
/// restart does not restore a lost original installation.
pub fn Root::adopt_private_file_projection(
  self : Root,
  name : String,
) -> Result[PrivateFileProjection, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  let projection = adopt_private_file_projection_ffi(
    self,
    encoded,
    encoded.length(),
  )
  if private_file_projection_ready_ffi(projection) {
    Ok(projection)
  } else {
    Err(GenerationMismatch)
  }
}
