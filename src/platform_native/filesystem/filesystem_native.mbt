///|
/// Open directory descriptor used as the authority for relative operations.
type Root

///|
/// Exclusive process ownership for one stable name below a Store root.
type Lock

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
/// Descriptor-pinned reader for one exact physical generation.
type Reader

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
extern "C" fn acquire_lock_ffi(root : Root, name : Bytes, length : Int) -> Lock = "actql_native_filesystem_acquire_lock"

///|
#borrow(lock)
extern "C" fn lock_ready_ffi(lock : Lock) -> Bool = "actql_native_filesystem_lock_ready"

///|
#borrow(lock)
extern "C" fn lock_error_ffi(lock : Lock) -> Bytes = "actql_native_filesystem_lock_error"

///|
#borrow(lock)
extern "C" fn lock_close_ffi(lock : Lock) -> Bool = "actql_native_filesystem_lock_close"

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
extern "C" fn writer_conflict_ffi(writer : Writer) -> Bool = "actql_native_filesystem_writer_conflict"

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
#borrow(root, name)
extern "C" fn inspect_generation_ffi(
  root : Root,
  name : Bytes,
  length : Int,
) -> Int = "actql_native_filesystem_inspect_generation"

///|
#borrow(root)
extern "C" fn root_result_device_ffi(root : Root) -> UInt64 = "actql_native_filesystem_root_result_device"

///|
#borrow(root)
extern "C" fn root_result_inode_ffi(root : Root) -> UInt64 = "actql_native_filesystem_root_result_inode"

///|
#borrow(root)
extern "C" fn root_result_size_ffi(root : Root) -> Int64 = "actql_native_filesystem_root_result_size"

///|
#borrow(root)
extern "C" fn sync_root_ffi(root : Root) -> Int = "actql_native_filesystem_sync_root"

///|
#borrow(root, name)
extern "C" fn reclaim_generation_ffi(
  root : Root,
  name : Bytes,
  length : Int,
  device : UInt64,
  inode : UInt64,
  size : Int64,
) -> Int = "actql_native_filesystem_reclaim_generation"

///|
#borrow(root, name)
extern "C" fn open_reader_ffi(
  root : Root,
  name : Bytes,
  length : Int,
  device : UInt64,
  inode : UInt64,
  size : Int64,
) -> Reader = "actql_native_filesystem_open_reader"

///|
#borrow(reader)
extern "C" fn reader_ready_ffi(reader : Reader) -> Bool = "actql_native_filesystem_reader_ready"

///|
#borrow(reader)
extern "C" fn reader_error_ffi(reader : Reader) -> Bytes = "actql_native_filesystem_reader_error"

///|
#borrow(reader)
extern "C" fn reader_next_ffi(reader : Reader, max_bytes : Int) -> Int = "actql_native_filesystem_reader_next"

///|
#borrow(reader)
extern "C" fn reader_chunk_ffi(reader : Reader) -> Bytes = "actql_native_filesystem_reader_chunk"

///|
#borrow(reader)
extern "C" fn reader_eof_ffi(reader : Reader) -> Bool = "actql_native_filesystem_reader_eof"

///|
#borrow(reader)
extern "C" fn reader_finish_ffi(reader : Reader) -> Int = "actql_native_filesystem_reader_finish"

///|
#borrow(reader)
extern "C" fn reader_close_ffi(reader : Reader) -> Int = "actql_native_filesystem_reader_close"

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
pub fn Root::acquire_lock(
  self : Root,
  name : String,
) -> Result[Lock, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  let lock = acquire_lock_ffi(self, encoded, encoded.length())
  if lock_ready_ffi(lock) {
    Ok(lock)
  } else {
    Err(Lock(decode_message(lock_error_ffi(lock))))
  }
}

///|
pub fn Lock::close(self : Lock) -> Bool {
  lock_close_ffi(self)
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
  } else if writer_conflict_ffi(writer) {
    Err(Conflict)
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
#borrow(writer, name)
extern "C" fn writer_adopt_name_ffi(
  writer : Writer,
  name : Bytes,
  length : Int,
) -> Int = "actql_native_filesystem_writer_adopt_name"

///|
/// Give the open staging file its public name and drop its private one. The
/// public name is linked exclusively: an existing file there is a conflict
/// and is never replaced or removed. The generation is verified before the
/// private name goes.
pub fn Writer::adopt_name(
  self : Writer,
  name : String,
) -> Result[Unit, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  match writer_adopt_name_ffi(self, encoded, encoded.length()) {
    0 => Ok(())
    1 => Err(Conflict)
    2 => Err(GenerationMismatch)
    3 => Err(WriterClosed)
    _ => Err(Write(writer_message(self)))
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
/// Returns the identity acquired by this successful exclusive creation. It is
/// stable while the staging file grows and grants authority over no other
/// file.
pub fn Writer::ownership(self : Writer) -> NativeFileOwnership {
  { device: writer_device_ffi(self), inode: writer_inode_ffi(self), }
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

///|
/// Observes one regular file generation without following symbolic links.
/// A missing name is represented as None and is distinct from a mismatch.
pub fn Root::inspect_generation(
  self : Root,
  name : String,
) -> Result[NativeFileGeneration?, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  match inspect_generation_ffi(self, encoded, encoded.length()) {
    0 =>
      Ok(
        Some({
          device: root_result_device_ffi(self),
          inode: root_result_inode_ffi(self),
          size: root_result_size_ffi(self),
        }),
      )
    1 => Ok(None)
    2 => Err(GenerationMismatch)
    _ => Err(Read(decode_message(root_error_ffi(self))))
  }
}

///|
/// Confirms durability of prior namespace changes in this Store root. This is
/// separate from observing that a name is absent.
pub fn Root::sync_directory(self : Root) -> Result[Unit, NativeFilesystemIssue] {
  if sync_root_ffi(self) == 0 {
    Ok(())
  } else {
    Err(Cleanup(decode_message(root_error_ffi(self))))
  }
}

///|
/// Durably removes one exact committed generation. A missing name is
/// idempotent success, while a replacement generation is never removed.
pub fn Root::reclaim_generation(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Unit, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  if generation.size < 0L {
    return Err(GenerationMismatch)
  }
  let encoded = @utf8.encode(name)
  match
    reclaim_generation_ffi(
      self,
      encoded,
      encoded.length(),
      generation.device,
      generation.inode,
      generation.size,
    ) {
    0 => Ok(())
    1 => Err(GenerationMismatch)
    _ => Err(Cleanup(decode_message(root_error_ffi(self))))
  }
}

///|
pub fn Root::open_reader(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Reader, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  if generation.size < 0L {
    return Err(GenerationMismatch)
  }
  let encoded = @utf8.encode(name)
  let reader = open_reader_ffi(
    self,
    encoded,
    encoded.length(),
    generation.device,
    generation.inode,
    generation.size,
  )
  if reader_ready_ffi(reader) {
    Ok(reader)
  } else {
    let message = decode_message(reader_error_ffi(reader))
    if message == "generation mismatch" {
      Err(GenerationMismatch)
    } else {
      Err(Read(message))
    }
  }
}

///|
pub fn Reader::next(
  self : Reader,
  max_bytes : Int,
) -> Result[NativeFileChunk, NativeFilesystemIssue] {
  if max_bytes <= 0 || max_bytes > 1048576 {
    return Err(InvalidReadSize)
  }
  match reader_next_ffi(self, max_bytes) {
    0 => Ok({ bytes: reader_chunk_ffi(self), eof: reader_eof_ffi(self), })
    1 => Err(GenerationMismatch)
    2 => Err(ReaderClosed)
    _ => Err(Read(decode_message(reader_error_ffi(self))))
  }
}

///|
pub fn Reader::finish(self : Reader) -> Result[Unit, NativeFilesystemIssue] {
  match reader_finish_ffi(self) {
    0 => Ok(())
    1 => Err(GenerationMismatch)
    2 => Err(IncompleteRead)
    3 => Err(ReaderClosed)
    _ => Err(Read(decode_message(reader_error_ffi(self))))
  }
}

///|
pub fn Reader::close(self : Reader) -> Result[Unit, NativeFilesystemIssue] {
  if reader_close_ffi(self) == 0 {
    Ok(())
  } else {
    Err(Read(decode_message(reader_error_ffi(self))))
  }
}
