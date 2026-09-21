///|
type Journal

///|
pub fn open_journal(
  _library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[Journal, NativeRemoteTransferJournalIssue] {
  ignore(path)
  ignore(max_record_bytes)
  ignore(max_chunks)
  ignore(max_manifest_bytes)
  ignore(max_referenced_bytes)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::accept(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[
  (NativeRemoteTransferAdmission, @transfer.RemoteTransferRecord),
  NativeRemoteTransferJournalIssue,
] {
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::require(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferJournalIssue] {
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::accept_store_use(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[
  (NativeRemoteTransferAdmission, @transfer.RemoteTransferStoreUseRecord),
  NativeRemoteTransferJournalIssue,
] {
  ignore(request)
  ignore(use_id)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::require_store_use(
  _self : Journal,
  store_use : @transfer.RemoteTransferStoreUse,
) -> Result[
  @transfer.RemoteTransferStoreUseRecord,
  NativeRemoteTransferJournalIssue,
] {
  ignore(store_use)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::bind_destination_use(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[Bool, NativeRemoteTransferJournalIssue] {
  ignore(request)
  ignore(use_id)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::reserve_destination_holding(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
  max_bytes : Int64,
  max_objects : Int64,
) -> Result[Bool, NativeRemoteTransferJournalIssue] {
  ignore(request)
  ignore(max_bytes)
  ignore(max_objects)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::release_destination_holding(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[Bool, NativeRemoteTransferJournalIssue] {
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::destination_capacity_usage(
  _self : Journal,
) -> Result[@sqlite.NativeCapacityUsage, NativeRemoteTransferJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::prepare_destination_allocation(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  index : Int,
  staging_name : String,
  final_name : String,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  ignore(request)
  ignore(use_id)
  ignore(index)
  ignore(staging_name)
  ignore(final_name)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::record_destination_allocation_owned(
  _self : Journal,
  current : NativeRemoteDestinationAllocation,
  ownership : @filesystem.NativeFileOwnership,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  ignore(current)
  ignore(ownership)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::record_destination_allocation_sealed(
  _self : Journal,
  current : NativeRemoteDestinationAllocation,
  generation : @filesystem.NativeFileGeneration,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  ignore(current)
  ignore(generation)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::record_destination_allocation_reused(
  _self : Journal,
  current : NativeRemoteDestinationAllocation,
  generation : @filesystem.NativeFileGeneration,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  ignore(current)
  ignore(generation)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::begin_destination_allocation_reclaim(
  _self : Journal,
  current : NativeRemoteDestinationAllocation,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  ignore(current)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::release_destination_allocation_intent(
  _self : Journal,
  current : NativeRemoteDestinationAllocation,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  ignore(current)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::finish_destination_allocation_reclaim(
  _self : Journal,
  current : NativeRemoteDestinationAllocation,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  ignore(current)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::commit_destination_receipt(
  _self : Journal,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  request : @transfer.RemoteTransferRequest,
) -> Result[
  @transfer.RemoteTransferDestinationReceipt,
  NativeRemoteTransferJournalIssue,
] {
  ignore(receipt)
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::inspect_destination_receipt(
  _self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[
  @transfer.RemoteTransferDestinationReceipt?,
  NativeRemoteTransferJournalIssue,
] {
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::commit_transition(
  _self : Journal,
  transition : @transfer.RemoteTransferTransition,
) -> Result[Unit, NativeRemoteTransferJournalIssue] {
  ignore(transition)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::commit_store_use_transition(
  _self : Journal,
  transition : @transfer.RemoteTransferStoreUseTransition,
) -> Result[Unit, NativeRemoteTransferJournalIssue] {
  ignore(transition)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::recover_after(
  _self : Journal,
  after_key : String,
) -> Result[RecoveredRemoteTransfer?, NativeRemoteTransferJournalIssue] {
  ignore(after_key)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::close(_self : Journal) -> Bool {
  false
}
