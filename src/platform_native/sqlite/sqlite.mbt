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
/// The existing bounded claim transaction distinguishes a newly committed
/// claim from its retained original. Neither variant proves Provider sending
/// or the presence of a separately saved use/outcome record.
pub(all) enum NativeOrdinalClaim {
  Fresh(Int64)
  Retained(Int64)
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
