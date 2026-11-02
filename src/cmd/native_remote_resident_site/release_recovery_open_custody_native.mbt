///|
/// Partial initialization of the existing stopped-release Owner. No execution
/// claim, process holding or synthetic prepared recovery is represented here.
priv struct ReleaseRecoveryOpenCustody {
  request_identity : String
  slot : @slot.NativeExecutorSlot
  journal : Ref[ControlReplayJournalCustody?]
  mut bundles : @bundle.NativeRuntimeBundleStore?
  mut failed_bundle : @bundle.NativeRuntimeBundleStoreOpenFailure?
  mut failure : String
  mut slot_closed : Bool
  mut slot_close_unknown : Bool
}

///|
fn release_recovery_open_custody(
  slot : @slot.NativeExecutorSlot,
  identity : String,
) -> ReleaseRecoveryOpenCustody {
  {
    request_identity: identity,
    slot,
    journal: Ref(None),
    bundles: None,
    failed_bundle: None,
    failure: "release recovery preparation incomplete",
    slot_closed: false,
    slot_close_unknown: false,
  }
}

///|
/// A fresh descriptor is not yet an exclusive current recovery hold. Keep
/// the original on either acquisition or named-current failure, before any
/// Journal/Bundle preparation. Cleanup does not confirm a Run release.
fn acquire_release_recovery_slot_with_custody(
  slot : @slot.NativeExecutorSlot,
  identity : String,
) -> Result[@slot.NativeExecutorSlot, ReleaseRecoveryOpenCustody] {
  let original = release_recovery_open_custody(slot, identity)
  let failure = match slot.try_acquire() {
    Ok(true) =>
      match slot.verify_current_hold() {
        Ok(_) => return Ok(slot)
        Err(_) => "release recovery Slot current hold unconfirmed"
      }
    Ok(false) => "release recovery Slot busy"
    Err(_) => "release recovery Slot acquisition failed"
  }
  original.failure = failure
  Err(original)
}

///|
/// All failures after the inherited Slot return that same custody. Argument
/// extraction precedes Journal/Bundle acquisition. The environment carries the
/// original command SQLite Library and lazy SAME-carrier Crypto loader; this
/// constructor never opens a replacement Library or invents a cleanup ACK.
fn open_release_recovery_with_custody(
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  slot : @slot.NativeExecutorSlot,
  identity : String,
) -> Result[StoppedReleaseRecovery, ReleaseRecoveryOpenCustody] {
  let original = release_recovery_open_custody(slot, identity)
  try {
    let crypto_path = required(matches, "crypto-library")
    let key_root = required(matches, "bundle-public-key-root")
    let key_file = required(matches, "bundle-public-key-file")
    let max_file_bytes = required_int64(matches, "max-file-bytes")
    let runtime_root = required(matches, "runtime-root")
    let issuer = required(matches, "bundle-issuer")
    let key_id = required(matches, "bundle-key-id")
    let target = required(matches, "target-triple")
    let release_failures = required_int(matches, "holder-release-failures")
    let journal = match
      open_control_replay_journal(environment, original.journal) {
      Some(value) => value
      None => stop("release recovery journal unavailable")
    }
    let signature_library = match (environment.crypto_library)(crypto_path) {
      Ok(value) => value
      Err(_) => stop("signature library load failed")
    }
    let public_key = load_text(key_root, key_file, max_file_bytes)
    let bundles = match
      @bundle.open_runtime_bundle_store_with_custody(
        environment.sqlite_library,
        signature_library,
        runtime_root,
        [{ issuer_authority: issuer, key_id, public_key_pem: public_key, }],
        target,
        environment.max_bytes,
        64,
        1024,
        environment.max_record_bytes,
      ) {
      Ok(value) => {
        original.bundles = Some(value)
        value
      }
      Err(RefusedBeforeAcquisition(_)) =>
        stop("release recovery Bundle configuration refused")
      Err(CleanupRequired(failure)) => {
        original.failed_bundle = Some(failure)
        stop("release recovery Bundle acquisition failed")
      }
    }
    match bundles.inspect(environment.runtime_bundle_cid) {
      Ok(Some(_)) => ()
      _ => stop("release recovery saved Bundle unavailable")
    }
    let owner : StoppedReleaseRecovery = {
      slot,
      environment,
      bundles,
      journal,
      request_identity: identity,
      bundle_closed: false,
      transfer_journal: None,
      input_cleanup_resources: new_holder_partial_output_resources(),
      input_cleanup_paths: None,
      input_cleanup_step: Ref(0),
      physical_cleanup: None,
      physical_cleanup_done: false,
      release_failure_hook: { remaining: release_failures, attempts: 0, },
      retained_input: false,
      recorded_source: None,
      recorded_consumer: None,
      completed_input_producer: None,
      terminal_close: RecoveryTerminalOpen,
    }
    // The successfully prepared Owner receives the exact original references.
    original.journal.val = None
    original.bundles = None
    Ok(owner)
  } catch {
    CommandStop(reason) => {
      original.failure = reason
      Err(original)
    }
  }
}

///|
/// Reverse constructor order: same Bundle, same Journal, inherited Slot.
/// No catalog/read/reopen, execution retry, release transition or report ACK.
fn retry_release_recovery_open_cleanup(
  original : ReleaseRecoveryOpenCustody,
) -> Bool {
  if original.failed_bundle is Some(same) {
    guard same.retry_cleanup() is Ok(_) else { return false }
    original.failed_bundle = None
  }
  if original.bundles is Some(same) {
    guard same.close_checked() is Ok(_) else { return false }
    original.bundles = None
  }
  guard retry_control_replay_journal_cleanup(original.journal) else {
    return false
  }
  if original.slot_close_unknown {
    return false
  }
  if original.slot_closed {
    return true
  }
  let closed = original.slot.close()
  if closed {
    original.slot_closed = true
  } else {
    original.slot_close_unknown = true
  }
  closed
}

///|
/// The unstarted failure remains in the existing same-process lifetime shell.
/// Only real close ACKs allow its terminal diagnostic to be consumed; signal,
/// EOF and termination do not turn cleanup Unknown into success.
fn finish_failed_release_recovery_open(
  original : ReleaseRecoveryOpenCustody,
) -> Unit {
  install_partial_holder_cleanup_signal()
  ignore(
    retain_holder_cleanup_lifetime(
      original,
      retry_release_recovery_open_cleanup,
      () => CleanupInputEnded,
      wait_holder_cleanup_lifetime_signal,
      (same, control_ended) => {
        report("release-recovery-open-cleanup-pending", [
          ("request_cid", same.request_identity),
          ("control_ended", control_ended.to_string()),
        ])
      },
    ),
  )
}
