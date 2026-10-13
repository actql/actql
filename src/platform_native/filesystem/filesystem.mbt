///|
pub(all) enum NativeFilesystemIssue {
  UnsupportedTarget
  InvalidName
  InvalidLimit
  RootOpen(String)
  Lock(String)
  WriterCreate(String)
  CapacityExceeded
  WriterClosed
  Write(String)
  Conflict
  GenerationMismatch
  InvalidReadSize
  IncompleteRead
  ReaderClosed
  Read(String)
  Seal(String)
  Cleanup(String)
}

///|
pub(all) struct NativeFileGeneration {
  device : UInt64
  inode : UInt64
  size : Int64
} derive(Eq, Debug)

///|
/// Stable ownership acquired by one successful exclusive file creation. File
/// length is deliberately excluded because a staging allocation grows while
/// the same owner writes it.
pub(all) struct NativeFileOwnership {
  device : UInt64
  inode : UInt64
} derive(Eq, Debug)

///|
pub(all) struct NativeFileChunk {
  bytes : Bytes
  eof : Bool
}

///|
/// Refusal from the existing Reader constructor, with the same rejected Reader
/// retained when its close result was not acknowledged. It never admits reads.
struct NativeReaderOpenFailure {
  original_issue : NativeFilesystemIssue
  mut reader : Reader?
}

///|
pub fn NativeReaderOpenFailure::issue(
  self : NativeReaderOpenFailure,
) -> NativeFilesystemIssue {
  self.original_issue
}

///|
pub fn NativeReaderOpenFailure::retry_cleanup(
  self : NativeReaderOpenFailure,
) -> Result[Unit, NativeFilesystemIssue] {
  guard self.reader is Some(reader) else { return Ok(()) }
  match reader.close() {
    Ok(_) => {
      self.reader = None
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
fn reader_open_failure(
  issue : NativeFilesystemIssue,
) -> NativeReaderOpenFailure {
  { original_issue: issue, reader: None, }
}

///|
/// The same rejected directory object, distinct from read authority or an
/// admitted Root. Successful cleanup retires only its original descriptor.
struct NativeRootOpenFailure {
  original_issue : NativeFilesystemIssue
  mut root : Root?
}

///|
pub fn NativeRootOpenFailure::issue(
  self : NativeRootOpenFailure,
) -> NativeFilesystemIssue {
  self.original_issue
}

///|
pub fn NativeRootOpenFailure::retry_cleanup(
  self : NativeRootOpenFailure,
) -> Result[Unit, NativeFilesystemIssue] {
  guard self.root is Some(original) else { return Ok(()) }
  match original.close() {
    Ok(_) => {
      self.root = None
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// A rejected Lock retains the actual constructor object and primary refusal.
/// Unknown close stays with this same object; it never retries a raw FD.
struct NativeLockOpenFailure {
  original_issue : NativeFilesystemIssue
  mut lock : Lock?
}

///|
pub fn NativeLockOpenFailure::issue(
  self : NativeLockOpenFailure,
) -> NativeFilesystemIssue {
  self.original_issue
}

///|
pub fn NativeLockOpenFailure::retry_cleanup(
  self : NativeLockOpenFailure,
) -> Result[Unit, NativeFilesystemIssue] {
  guard self.lock is Some(original) else { return Ok(()) }
  match original.close_checked() {
    Ok(_) => {
      self.lock = None
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}
