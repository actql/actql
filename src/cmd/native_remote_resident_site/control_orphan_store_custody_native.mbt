///|
/// Pure operator configuration, not permission or a Store/Slot original.
priv struct ControlOrphanStoreSettings {
  root : String
  authority_cid : String
  capacity_bytes : Int64
}

///|
/// Retain the existing failed constructor before another fallible operation.
/// A pending original prohibits a replacement, even with different settings.
fn open_control_orphan_store(
  environment : ControlEnvironment,
  settings : ControlOrphanStoreSettings,
  failed : Ref[@publication_store.NativePublicationStoreOpenFailure?],
) -> @publication_store.Store? {
  guard failed.val is None else { return None }
  match
    @publication_store.open_store_with_custody(
      environment.sqlite_library,
      settings.root,
      settings.authority_cid,
      settings.capacity_bytes,
      environment.max_transfers.to_int64(),
      environment.max_record_bytes,
    ) {
    Ok(original) => Some(original)
    Err(RefusedBeforeAcquisition(_)) => None
    Err(CleanupRequired(original)) => {
      failed.val = Some(original)
      None
    }
  }
}

///|
fn retry_control_orphan_store_cleanup(
  failed : Ref[@publication_store.NativePublicationStoreOpenFailure?],
  journal : Ref[ControlReplayJournalCustody?],
  slot : @slot.NativeExecutorSlot,
) -> Bool {
  guard failed.val is Some(original) else { return true }
  guard original.retry_cleanup() is Ok(_) else { return false }
  // Keep the original failure until its earlier Journal and Slot also retire.
  // Reentry repeats only the idempotent cleanup of that same constructor.
  guard retry_control_replay_journal_cleanup(journal) else { return false }
  retain_control_reclaim_slot_close(slot)
  failed.val = None
  true
}

///|
/// A Store refused before acquisition still leaves the earlier real Journal
/// and Slot with this caller. No synthetic failed Store is needed to retain
/// those originals, and no later opener may bypass their cleanup.
fn retain_control_orphan_reader_cleanup(
  journal : Ref[ControlReplayJournalCustody?],
  slot : @slot.NativeExecutorSlot,
) -> Unit {
  install_partial_holder_cleanup_signal()
  ignore(
    retain_holder_cleanup_lifetime(
      (journal, slot),
      same => {
        guard retry_control_replay_journal_cleanup(same.0) else { return false }
        retain_control_reclaim_slot_close(same.1)
        true
      },
      () => CleanupInputEnded,
      wait_holder_cleanup_lifetime_signal,
      (_, _) => report("orphan-reader-cleanup-pending", []),
    ),
  )
}
