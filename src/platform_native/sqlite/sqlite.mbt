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
  Physical(String)
}

///|
pub(all) struct NativeJournalValue {
  revision : Int64
  body : Bytes
}
