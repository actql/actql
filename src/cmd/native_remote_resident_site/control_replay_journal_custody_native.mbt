///|
/// A retained reference in the existing controller lifetime. It is neither a
/// report ledger nor an authority to retry an execution or Provider request.
priv enum ControlReplayJournalCustody {
  ReplayJournalHandle(@journal.Journal)
  ReplayJournalOpenFailure(@journal.NativeRemoteJournalOpenFailure)
}

///|
fn retry_control_replay_journal_cleanup(
  retained : Ref[ControlReplayJournalCustody?],
) -> Bool {
  let outcome = match retained.val {
    Some(ReplayJournalHandle(original)) => original.close_checked()
    Some(ReplayJournalOpenFailure(original)) => original.retry_cleanup()
    None => return true
  }
  match outcome {
    Ok(_) => {
      retained.val = None
      true
    }
    Err(_) => false
  }
}

///|
/// No second opener may replace a retained original, even when the caller's
/// current environment changes. Cleanup is a separate control progress pass.
fn open_control_replay_journal(
  environment : ControlEnvironment,
  retained : Ref[ControlReplayJournalCustody?],
) -> @journal.Journal? {
  guard retained.val is None else { return None }
  let site = match @site.create_site(
    environment.site_key, environment.site_generation,
    environment.runtime_bundle_cid, environment.max_operations,
    environment.max_transfers, environment.max_bytes, environment.max_bytes,
  ) {
    Some(value) => value
    None => return None
  }
  let control = match @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1") {
    Ok(value) => value
    Err(_) => return None
  }
  match @journal.open_journal_with_custody(
    environment.sqlite_library, environment.journal_path,
    environment.max_record_bytes, control,
  ) {
    Ok(original) => {
      retained.val = Some(ReplayJournalHandle(original))
      Some(original)
    }
    Err(@journal.RefusedBeforeAcquisition(_)) => None
    Err(@journal.CleanupRequired(original)) => {
      retained.val = Some(ReplayJournalOpenFailure(original))
      None
    }
  }
}
