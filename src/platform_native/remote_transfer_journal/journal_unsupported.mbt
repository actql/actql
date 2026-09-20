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
