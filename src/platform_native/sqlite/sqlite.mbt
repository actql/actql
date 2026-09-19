///|
pub(all) enum NativeSqliteIssue {
  UnsupportedTarget
  InvalidName
  InvalidLimit
  LibraryLoad(String)
  DatabaseOpen(String)
  DatabaseClosed
  NotFound
  Collision
  Busy
  BodyTooLarge
  CapacityExceeded
  Physical(String)
}

///|
pub(all) struct NativeCapacityUsage {
  reserved_bytes : Int64
  reserved_objects : Int64
}

///|
pub(all) struct NativeJournalValue {
  revision : Int64
  body : Bytes
}

///|
pub(all) struct NativeJournalEntry {
  key : String
  revision : Int64
  body : Bytes
}
