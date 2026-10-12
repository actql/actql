///|
/// Original physical installation facts retained by the private-root Owner.
/// Restored only from authenticated private custody; never an authorization token.
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
#borrow(projection, output)
extern "C" fn export_private_file_projection_ffi(
  projection : PrivateFileProjection,
  output : Bytes,
  capacity : Int,
) -> Int = "actql_native_filesystem_export_private_file_projection"

///|
#borrow(root, original)
extern "C" fn restore_private_file_projection_ffi(
  root : Root,
  original : Bytes,
  length : Int,
) -> PrivateFileProjection = "actql_native_filesystem_restore_private_file_projection"

///|
/// Export at most 234 private bytes of original physical facts. Trusted Host
/// assembly must durably bind them to the adopted installation before ACK.
/// These bytes contain no secret and confer no read, grant or send authority.
pub fn PrivateFileProjection::export_original(
  self : PrivateFileProjection,
) -> Result[Bytes, NativeFilesystemIssue] {
  let output = Bytes::make(234, 0)
  let length = export_private_file_projection_ffi(self, output, output.length())
  if length > 106 && length <= 234 {
    Ok(output[:length].to_owned())
  } else {
    Err(GenerationMismatch)
  }
}

///|
/// Low-level comparison of authenticated original Host custody with current
/// root/file facts. The caller must obtain original bytes from its existing
/// private journal binding, not from user-supplied stat or a public identity.
/// This operation neither adopts a replacement nor authorizes protected I/O.
pub fn Root::restore_private_file_projection(
  self : Root,
  original : Bytes,
) -> Result[PrivateFileProjection, NativeFilesystemIssue] {
  if original.length() <= 106 || original.length() > 234 {
    return Err(GenerationMismatch)
  }
  let projection = restore_private_file_projection_ffi(
    self,
    original,
    original.length(),
  )
  if private_file_projection_ready_ffi(projection) {
    Ok(projection)
  } else {
    Err(GenerationMismatch)
  }
}

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
