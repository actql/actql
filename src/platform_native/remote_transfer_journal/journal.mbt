///|
pub(all) enum NativeRemoteTransferJournalIssue {
  UnsupportedTarget
  Closed
  Physical(@sqlite.NativeSqliteIssue)
  Protocol(@transfer.RemoteTransferIssue)
  StateCollision
  RecoveryRequired
}

///|
pub(all) enum NativeRemoteDestinationAllocationPhase {
  DestinationAllocationIntent
  DestinationAllocationStagingOwned(@filesystem.NativeFileOwnership)
  DestinationAllocationSealed(@filesystem.NativeFileGeneration)
  DestinationAllocationReused(@filesystem.NativeFileGeneration)
  DestinationAllocationReclaimingOwned(@filesystem.NativeFileOwnership)
  DestinationAllocationReclaimingSealed(@filesystem.NativeFileGeneration)
  DestinationAllocationReleased
} derive(Eq, Debug)

///|
#warnings("-struct_never_constructed")
pub struct NativeRemoteDestinationAllocation {
  key : String
  staging_name : String
  final_name : String
  revision : Int64
  phase : NativeRemoteDestinationAllocationPhase
}

///|
pub fn destination_allocation_staging_name(
  value : NativeRemoteDestinationAllocation,
) -> String {
  value.staging_name
}

///|
pub fn destination_allocation_final_name(
  value : NativeRemoteDestinationAllocation,
) -> String {
  value.final_name
}

///|
pub fn destination_allocation_phase(
  value : NativeRemoteDestinationAllocation,
) -> NativeRemoteDestinationAllocationPhase {
  value.phase
}

///|
#warnings("-unused_value")
fn destination_allocation_u64(value : String) -> UInt64? {
  let parsed : UInt64 = @string.from_str(value) catch { _ => return None }
  Some(parsed)
}

///|
#warnings("-unused_value")
fn destination_allocation_i64(value : String) -> Int64? {
  let parsed : Int64 = @string.from_str(value) catch { _ => return None }
  Some(parsed)
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
