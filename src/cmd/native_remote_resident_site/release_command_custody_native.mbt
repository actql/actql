///|
/// Same command's Store or failed constructor, retained before any later
/// journal/reclamation work. No second open is selected on this carrier.
fn open_release_command_store(
  environment : ControlEnvironment,
  resources : HolderPartialOutputResources,
  settings : ControlOrphanStoreSettings,
) -> @publication_store.Store? {
  guard resources.store is None && resources.failed_store is None else {
    return None
  }
  match
    @publication_store.open_store_with_custody(
      environment.sqlite_library,
      settings.root,
      settings.authority_cid,
      settings.capacity_bytes,
      environment.max_transfers.to_int64(),
      environment.max_record_bytes,
    ) {
    Ok(original) => {
      resources.store = Some(original)
      Some(original)
    }
    Err(RefusedBeforeAcquisition(_)) => None
    Err(CleanupRequired(original)) => {
      resources.failed_store = Some(original)
      None
    }
  }
}

///|
/// Keep a ready observation reader through its checked close, before Library
/// or command Read retirement. A failed close cannot be dropped or converted
/// into a remote status/release acknowledgment.
fn retain_control_replay_journal_close(
  original : @journal.Journal,
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> Unit {
  let retained = Ref(Some(ReplayJournalHandle(original)))
  install_partial_holder_cleanup_signal(report_progress~)
  ignore(
    retain_holder_cleanup_lifetime(
      retained,
      retry_control_replay_journal_cleanup,
      () => CleanupInputEnded,
      () => wait_holder_cleanup_lifetime_signal_with_report(report_progress~),
      (_, _) => report_progress("journal-reader-cleanup-pending", []),
    ),
  )
}
