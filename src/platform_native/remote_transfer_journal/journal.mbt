///|
pub(all) enum NativeRemoteTransferJournalIssue {
  UnsupportedTarget
  Closed
  Physical(@sqlite.NativeSqliteIssue)
  Protocol(@transfer.RemoteTransferIssue)
  StateCollision
}

///|
pub(all) enum NativeRemoteTransferAdmission {
  NewTransfer
  ExistingTransfer
} derive(Eq, Debug)

///|
#warnings("-struct_never_constructed")
struct RecoveredRemoteTransfer {
  key : String
  record : @transfer.RemoteTransferRecord
}

///|
pub fn recovered_remote_transfer_key(
  recovered : RecoveredRemoteTransfer,
) -> String {
  recovered.key
}

///|
pub fn recovered_remote_transfer_record(
  recovered : RecoveredRemoteTransfer,
) -> @transfer.RemoteTransferRecord {
  recovered.record
}

///|
#warnings("-unused_value")
fn journal_bytes(body : String) -> Bytes {
  @utf8.encode(body)
}
