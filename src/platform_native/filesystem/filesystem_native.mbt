///|
/// Open directory descriptor used as the authority for relative operations.
type Root

///|
fn valid_object_name(name : String) -> Bool {
  if name.length() == 0 || name.length() > 128 || name == "." || name == ".." {
    return false
  }
  for character in name.iter() {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '-' ||
      character == '_' ||
      character == '.') {
      return false
    }
  }
  true
}

///|
/// Bounded writer that owns its staging and committed names until cleanup.
type Writer

///|
#borrow(path)
extern "C" fn open_root_ffi(path : Bytes, length : Int) -> Root = "actql_native_filesystem_open_root"

///|
#borrow(root)
extern "C" fn root_ready_ffi(root : Root) -> Bool = "actql_native_filesystem_root_ready"

///|
#borrow(root)
extern "C" fn root_error_ffi(root : Root) -> Bytes = "actql_native_filesystem_root_error"

///|
#borrow(root, name)
extern "C" fn create_writer_ffi(
  root : Root,
  name : Bytes,
  length : Int,
  max_bytes : Int64,
) -> Writer = "actql_native_filesystem_create_writer"

///|
#borrow(writer)
extern "C" fn writer_ready_ffi(writer : Writer) -> Bool = "actql_native_filesystem_writer_ready"

///|
#borrow(writer)
extern "C" fn writer_error_ffi(writer : Writer) -> Bytes = "actql_native_filesystem_writer_error"

///|
#borrow(writer, chunk)
extern "C" fn writer_append_ffi(
  writer : Writer,
  chunk : Bytes,
  length : Int,
) -> Int = "actql_native_filesystem_writer_append"

///|
#borrow(writer, name)
extern "C" fn writer_seal_ffi(
  writer : Writer,
  name : Bytes,
  length : Int,
) -> Int = "actql_native_filesystem_writer_seal"

///|
#borrow(writer)
extern "C" fn writer_cancel_ffi(writer : Writer) -> Int = "actql_native_filesystem_writer_cancel"

///|
#borrow(writer)
extern "C" fn writer_written_ffi(writer : Writer) -> Int64 = "actql_native_filesystem_writer_written"

///|
#borrow(writer)
extern "C" fn writer_sealed_ffi(writer : Writer) -> Bool = "actql_native_filesystem_writer_sealed"

///|
#borrow(writer)
extern "C" fn writer_pending_cleanup_ffi(writer : Writer) -> Bool = "actql_native_filesystem_writer_pending_cleanup"

///|
#borrow(writer)
extern "C" fn writer_device_ffi(writer : Writer) -> UInt64 = "actql_native_filesystem_writer_device"

///|
#borrow(writer)
extern "C" fn writer_inode_ffi(writer : Writer) -> UInt64 = "actql_native_filesystem_writer_inode"

///|
#borrow(root, name)
extern "C" fn verify_generation_ffi(
  root : Root,
  name : Bytes,
  length : Int,
  device : UInt64,
  inode : UInt64,
  size : Int64,
) -> Bool = "actql_native_filesystem_verify_generation"

///|
fn decode_message(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
fn writer_message(writer : Writer) -> String {
  decode_message(writer_error_ffi(writer))
}

///|
pub fn open_root(path : String) -> Result[Root, NativeFilesystemIssue] {
  let encoded = @utf8.encode(path)
  let root = open_root_ffi(encoded, encoded.length())
  if root_ready_ffi(root) {
    Ok(root)
  } else {
    Err(RootOpen(decode_message(root_error_ffi(root))))
  }
}

///|
pub fn Root::create_writer(
  self : Root,
  staging_name : String,
  max_bytes : Int64,
) -> Result[Writer, NativeFilesystemIssue] {
  if !valid_object_name(staging_name) {
    return Err(InvalidName)
  }
  if max_bytes < 0L {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(staging_name)
  let writer = create_writer_ffi(self, encoded, encoded.length(), max_bytes)
  if writer_ready_ffi(writer) {
    Ok(writer)
  } else {
    Err(WriterCreate(writer_message(writer)))
  }
}

///|
pub fn Writer::append(
  self : Writer,
  chunk : Bytes,
) -> Result[Unit, NativeFilesystemIssue] {
  match writer_append_ffi(self, chunk, chunk.length()) {
    0 => Ok(())
    1 => Err(CapacityExceeded)
    2 => Err(WriterClosed)
    _ => Err(Write(writer_message(self)))
  }
}

///|
pub fn Writer::seal(
  self : Writer,
  final_name : String,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  if !valid_object_name(final_name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(final_name)
  match writer_seal_ffi(self, encoded, encoded.length()) {
    0 =>
      Ok({
        device: writer_device_ffi(self),
        inode: writer_inode_ffi(self),
        size: writer_written_ffi(self),
      })
    1 => Err(Conflict)
    2 => Err(GenerationMismatch)
    3 => Err(WriterClosed)
    _ => Err(Seal(writer_message(self)))
  }
}

///|
pub fn Writer::cancel(self : Writer) -> Result[Unit, NativeFilesystemIssue] {
  match writer_cancel_ffi(self) {
    0 => Ok(())
    2 => Err(GenerationMismatch)
    _ => Err(Cleanup(writer_message(self)))
  }
}

///|
pub fn Writer::written(self : Writer) -> Int64 {
  writer_written_ffi(self)
}

///|
pub fn Writer::is_sealed(self : Writer) -> Bool {
  writer_sealed_ffi(self)
}

///|
pub fn Writer::cleanup_pending(self : Writer) -> Bool {
  writer_pending_cleanup_ffi(self)
}

///|
pub fn Root::verify_generation(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Bool {
  if !valid_object_name(name) {
    return false
  }
  let encoded = @utf8.encode(name)
  verify_generation_ffi(
    self,
    encoded,
    encoded.length(),
    generation.device,
    generation.inode,
    generation.size,
  )
}
