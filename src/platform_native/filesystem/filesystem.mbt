///|
pub(all) enum NativeFilesystemIssue {
  UnsupportedTarget
  InvalidName
  InvalidLimit
  RootOpen(String)
  WriterCreate(String)
  CapacityExceeded
  WriterClosed
  Write(String)
  Conflict
  GenerationMismatch
  Seal(String)
  Cleanup(String)
}

///|
pub(all) struct NativeFileGeneration {
  device : UInt64
  inode : UInt64
  size : Int64
}
