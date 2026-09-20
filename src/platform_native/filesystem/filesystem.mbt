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
