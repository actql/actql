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
extern "C" fn open_root_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> Root = "actql_native_filesystem_open_root_with_diagnostics"

///|
#borrow(path)
extern "C" fn open_private_root_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> Root = "actql_native_filesystem_open_private_root_with_diagnostics"

///|
#borrow(path)
extern "C" fn open_private_root_with_custody_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> Root = "actql_native_filesystem_open_private_root_with_custody_diagnostics"

///|
#borrow(root)
extern "C" fn private_root_identity_ffi(root : Root) -> Bool = "actql_native_filesystem_private_root_identity"

///|
#borrow(root)
extern "C" fn bootstrap_parent_identity_ffi(root : Root) -> Bool = "actql_native_filesystem_bootstrap_parent_identity"

///|
#borrow(root)
extern "C" fn root_ready_ffi(root : Root) -> Bool = "actql_native_filesystem_root_ready"

///|
#borrow(root)
extern "C" fn root_error_ffi(root : Root) -> Bytes = "actql_native_filesystem_root_error"

///|
#borrow(root)
extern "C" fn root_acquisition_error_ffi(root : Root) -> Bytes = "actql_native_filesystem_root_acquisition_error"

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
#borrow(lock)
extern "C" fn lock_close_checked_ffi(lock : Lock) -> Bool = "actql_native_filesystem_lock_close_checked"

///|
#borrow(lock)
extern "C" fn lock_cleanup_error_ffi(lock : Lock) -> Bytes = "actql_native_filesystem_lock_cleanup_error"

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
extern "C" fn reader_open_error_ffi(reader : Reader) -> Bytes = "actql_native_filesystem_reader_open_error"

///|
#borrow(reader)
extern "C" fn reader_open_kind_ffi(reader : Reader) -> Int = "actql_native_filesystem_reader_open_failure_kind"

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
extern "C" fn reader_finish_ffi(reader : Reader) -> Int = "actql_native_filesystem_reader_finish_dispatch"

///|
#borrow(reader)
extern "C" fn reader_close_ffi(reader : Reader) -> Int = "actql_native_filesystem_reader_close_dispatch"

///|
#borrow(root)
extern "C" fn root_close_ffi(root : Root) -> Int = "actql_native_filesystem_root_close_dispatch"

///|
/// Acknowledges this directory descriptor's close, not retirement of children.
/// Callers must retain their original Root on error; repeating the observation
/// never closes a potentially reused raw descriptor number.
pub fn Root::close(self : Root) -> Result[Unit, NativeFilesystemIssue] {
  if root_close_ffi(self) == 0 {
    Ok(())
  } else {
    Err(Cleanup(decode_diagnostic_message(root_error_ffi(self))))
  }
}

///|
fn decode_message(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
fn decode_diagnostic_message(bytes : Bytes) -> String {
  if bytes.length() == 0 {
    "filesystem diagnostic detail omitted"
  } else {
    @utf8.decode_lossy(bytes)
  }
}

///|
fn writer_message(writer : Writer) -> String {
  decode_message(writer_error_ffi(writer))
}

///|
/// An explicit positive diagnostic ceiling bounds original Root/Reader/Writer
/// detail. Omission preserves legacy behavior and does not establish funding.
pub fn open_root(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeFilesystemIssue] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(path)
  let root = open_root_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
  if root_ready_ffi(root) {
    Ok(root)
  } else {
    Err(RootOpen(decode_diagnostic_message(root_error_ffi(root))))
  }
}

///|
/// Additive original-custody entrance. A failed constructor is never admitted
/// as a usable Root, and cleanup neither reopens nor proves child retirement.
pub fn open_root_with_custody(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeRootOpenFailure] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err({ original_issue: InvalidLimit, root: None, })
  }
  let encoded = @utf8.encode(path)
  let root = open_root_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
  if root_ready_ffi(root) {
    Ok(root)
  } else {
    Err({
      original_issue: RootOpen(decode_diagnostic_message(root_error_ffi(root))),
      root: Some(root),
    })
  }
}

///|
/// Open an explicitly selected user-owned private directory. This establishes
/// physical containment, not adoption, freshness or execution authority.
pub fn open_private_root(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeFilesystemIssue] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(path)
  let root = open_private_root_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
  if root_ready_ffi(root) {
    Ok(root)
  } else {
    Err(RootOpen(decode_diagnostic_message(root_error_ffi(root))))
  }
}

///|
/// The same private constructor and privacy checks, retaining its rejected
/// original separately from cleanup. Retirement never admits that failed Root.
pub fn open_private_root_with_custody(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeRootOpenFailure] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err({ original_issue: InvalidLimit, root: None, })
  }
  let encoded = @utf8.encode(path)
  let root = open_private_root_with_custody_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
  if root_ready_ffi(root) {
    Ok(root)
  } else {
    Err({
      original_issue: RootOpen(
        decode_diagnostic_message(root_acquisition_error_ffi(root)),
      ),
      root: Some(root),
    })
  }
}

///|
/// Recheck the pinned descriptor's privacy and its original namespace binding.
/// A missing/replaced original name is not a new root or freshness evidence.
pub fn Root::private_ownership(
  self : Root,
) -> Result[NativeFileOwnership, NativeFilesystemIssue] {
  if private_root_identity_ffi(self) {
    Ok({
      device: root_result_device_ffi(self),
      inode: root_result_inode_ffi(self),
    })
  } else {
    Err(RootOpen(decode_diagnostic_message(root_error_ffi(self))))
  }
}

///|
/// Recheck a user-owned bootstrap parent and its original no-follow namespace.
/// This is physical metadata, not private-state ownership or an operation permit.
/// Exclusive children still require their original witness and private_ownership.
pub fn Root::bootstrap_parent_ownership(
  self : Root,
) -> Result[NativeFileOwnership, NativeFilesystemIssue] {
  if bootstrap_parent_identity_ffi(self) {
    Ok({
      device: root_result_device_ffi(self),
      inode: root_result_inode_ffi(self),
    })
  } else {
    Err(RootOpen(decode_diagnostic_message(root_error_ffi(self))))
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
pub fn Root::acquire_lock_with_custody(
  self : Root,
  name : String,
) -> Result[Lock, NativeLockOpenFailure] {
  if !valid_object_name(name) {
    return Err({ original_issue: InvalidName, lock: None, })
  }
  let encoded = @utf8.encode(name)
  let lock = acquire_lock_ffi(self, encoded, encoded.length())
  if lock_ready_ffi(lock) {
    Ok(lock)
  } else {
    Err({
      original_issue: Lock(decode_diagnostic_message(lock_error_ffi(lock))),
      lock: Some(lock),
    })
  }
}

///|
/// Idempotent acknowledgement of this original Lock only. An unconfirmed
/// consumed descriptor remains sticky and is never closed again by its number.
pub fn Lock::close_checked(self : Lock) -> Result[Unit, NativeFilesystemIssue] {
  if lock_close_checked_ffi(self) {
    Ok(())
  } else {
    Err(Cleanup(decode_diagnostic_message(lock_cleanup_error_ffi(self))))
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
  self.seal_named_file(final_name)
}

///|
fn Writer::seal_named_file(
  self : Writer,
  final_name : String,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
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
#borrow(writer, target, name)
extern "C" fn writer_adopt_name_ffi(
  writer : Writer,
  target : Root,
  name : Bytes,
  length : Int,
) -> Int = "actql_native_filesystem_writer_adopt_name"

///|
/// Give the open staging file its public name under `target` and drop its
/// private one. The public name is linked exclusively: an existing file
/// there is a conflict and is never replaced or removed. The generation is
/// verified before the private name goes; from then on the writer's names
/// live under `target`.
pub fn Writer::adopt_name(
  self : Writer,
  target : Root,
  name : String,
) -> Result[Unit, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  match writer_adopt_name_ffi(self, target, encoded, encoded.length()) {
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
  self.verify_named_file_generation(name, generation)
}

///|
fn Root::verify_named_file_generation(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Bool {
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
  self.inspect_named_file_generation(name)
}

///|
fn Root::inspect_named_file_generation(
  self : Root,
  name : String,
) -> Result[NativeFileGeneration?, NativeFilesystemIssue] {
  if !root_read_available_ffi(self) {
    return Err(Read("Current read scope was refused"))
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
    _ => Err(Read(decode_diagnostic_message(root_error_ffi(self))))
  }
}

///|
/// Confirms durability of prior namespace changes in this Store root. This is
/// separate from observing that a name is absent.
pub fn Root::sync_directory(self : Root) -> Result[Unit, NativeFilesystemIssue] {
  if sync_root_ffi(self) == 0 {
    Ok(())
  } else {
    Err(Cleanup(decode_diagnostic_message(root_error_ffi(self))))
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
    _ => Err(Cleanup(decode_diagnostic_message(root_error_ffi(self))))
  }
}

///|
pub fn Root::open_reader(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Reader, NativeFilesystemIssue] {
  match self.open_reader_with_custody(name, generation) {
    Ok(reader) => Ok(reader)
    Err(failure) => Err(failure.issue())
  }
}

///|
/// Uses the same constructor and exact generation checks. A rejected Reader
/// remains unready; the failure only retains its original cleanup custody.
pub fn Root::open_reader_with_custody(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Reader, NativeReaderOpenFailure] {
  if !valid_object_name(name) {
    return Err(reader_open_failure(InvalidName))
  }
  self.open_named_file_reader_with_custody(name, generation)
}

///|
fn Root::open_named_file_reader_with_custody(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Reader, NativeReaderOpenFailure] {
  if generation.size < 0L {
    return Err(reader_open_failure(GenerationMismatch))
  }
  if !root_read_available_ffi(self) {
    return Err(reader_open_failure(Read("Current read scope was refused")))
  }
  let encoded = @utf8.encode(name)
  if root_is_scoped_ffi(self) {
    return open_scoped_reader_with_custody(self, encoded, generation)
  }
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
    let message = decode_diagnostic_message(reader_open_error_ffi(reader))
    let issue = reader_open_issue(
      reader_open_kind(reader_open_kind_ffi(reader)),
      message,
    )
    let retained = match reader.close() {
      Ok(_) => None
      Err(_) => Some(reader)
    }
    Err({ original_issue: issue, reader: retained, })
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
  if !reader_read_available_ffi(self) {
    return Err(Read("Current read scope was refused"))
  }
  match reader_next_ffi(self, max_bytes) {
    0 => Ok({ bytes: reader_chunk_ffi(self), eof: reader_eof_ffi(self), })
    1 => Err(GenerationMismatch)
    2 => Err(ReaderClosed)
    _ => Err(Read(decode_diagnostic_message(reader_error_ffi(self))))
  }
}

///|
pub fn Reader::finish(self : Reader) -> Result[Unit, NativeFilesystemIssue] {
  match reader_finish_ffi(self) {
    0 => Ok(())
    1 => Err(GenerationMismatch)
    2 => Err(IncompleteRead)
    3 => Err(ReaderClosed)
    _ => Err(Read(decode_diagnostic_message(reader_error_ffi(self))))
  }
}

///|
pub fn Reader::close(self : Reader) -> Result[Unit, NativeFilesystemIssue] {
  if reader_close_ffi(self) == 0 {
    Ok(())
  } else {
    Err(Read(decode_diagnostic_message(reader_error_ffi(self))))
  }
}

///|
#borrow(root, name)
extern "C" fn create_directory_ffi(
  root : Root,
  name : Bytes,
  length : Int,
) -> Int = "actql_native_filesystem_create_directory"

///|
#borrow(root, name)
extern "C" fn inspect_directory_ffi(
  root : Root,
  name : Bytes,
  length : Int,
) -> Int = "actql_native_filesystem_inspect_directory"

///|
#borrow(root, name)
extern "C" fn remove_directory_ffi(
  root : Root,
  name : Bytes,
  length : Int,
  device : UInt64,
  inode : UInt64,
) -> Int = "actql_native_filesystem_remove_directory"

///|
#borrow(root, name)
extern "C" fn open_child_root_ffi(
  root : Root,
  name : Bytes,
  length : Int,
) -> Root = "actql_native_filesystem_open_child_root"

///|
/// Create one directory below this root exclusively and return its identity.
/// An existing name is a conflict; nothing there is touched.
pub fn Root::create_directory(
  self : Root,
  name : String,
) -> Result[NativeFileOwnership, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  match create_directory_ffi(self, encoded, encoded.length()) {
    0 =>
      Ok({
        device: root_result_device_ffi(self),
        inode: root_result_inode_ffi(self),
      })
    1 => Err(Conflict)
    _ => Err(WriterCreate(decode_diagnostic_message(root_error_ffi(self))))
  }
}

///|
/// The identity of a directory below this root, if one is there.
pub fn Root::inspect_directory(
  self : Root,
  name : String,
) -> Result[NativeFileOwnership?, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  match inspect_directory_ffi(self, encoded, encoded.length()) {
    0 =>
      Ok(
        Some({
          device: root_result_device_ffi(self),
          inode: root_result_inode_ffi(self),
        }),
      )
    1 => Ok(None)
    2 => Err(GenerationMismatch)
    _ => Err(Read(decode_diagnostic_message(root_error_ffi(self))))
  }
}

///|
/// Durably remove one exact empty directory. A missing name is idempotent
/// success; a directory that is not empty is left, with `Ok(false)`; another
/// directory or a file at the name is never removed.
pub fn Root::remove_directory(
  self : Root,
  name : String,
  identity : NativeFileOwnership,
) -> Result[Bool, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let encoded = @utf8.encode(name)
  match
    remove_directory_ffi(
      self,
      encoded,
      encoded.length(),
      identity.device,
      identity.inode,
    ) {
    0 => Ok(true)
    1 => Err(GenerationMismatch)
    3 => Ok(false)
    _ => Err(Cleanup(decode_diagnostic_message(root_error_ffi(self))))
  }
}

///|
/// Open one directory below this root as a root of its own.
pub fn Root::open_child(
  self : Root,
  name : String,
) -> Result[Root, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  // The issue-only entrance cannot retain a failed scoped child. Its caller
  // must use the original custody carrier instead of falling through to legacy.
  if root_is_scoped_ffi(self) {
    return Err(RootOpen("Scoped child acquisition requires original custody"))
  }
  let encoded = @utf8.encode(name)
  let child = open_child_root_ffi(self, encoded, encoded.length())
  if root_ready_ffi(child) {
    Ok(child)
  } else {
    Err(RootOpen(decode_diagnostic_message(root_error_ffi(child))))
  }
}

///|
/// Private mapping of the original C open disposition. Diagnostic bytes are
/// not an authority for this kind and cannot turn omission into success.
priv enum NativeReaderOpenIssueKind {
  GenerationFailure
  ReadFailure
}

///|
fn reader_open_kind(code : Int) -> NativeReaderOpenIssueKind {
  if code == 2 {
    GenerationFailure
  } else {
    ReadFailure
  }
}

///|
fn reader_open_issue(
  kind : NativeReaderOpenIssueKind,
  detail : String,
) -> NativeFilesystemIssue {
  match kind {
    GenerationFailure => GenerationMismatch
    ReadFailure => Read(detail)
  }
}
