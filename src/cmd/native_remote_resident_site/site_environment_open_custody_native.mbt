///|
/// Same partially acquired Site preparation, within existing Bundle/Journal
/// Owners. No substitute Site, Run, grant or cleanup queue is created.
priv struct SiteEnvironmentOpenCustody {
  original_failure : String
  process_hold_id : String
  mut bundles : @bundle.NativeRuntimeBundleStore?
  mut failed_bundle : @bundle.NativeRuntimeBundleStoreOpenFailure?
  mut failed_journal : @journal.NativeRemoteJournalOpenFailure?
  mut release_required : Bool
}

///|
fn site_environment_open_custody(
  original_failure : String,
  process_hold_id : String,
  bundles? : @bundle.NativeRuntimeBundleStore? = None,
  failed_bundle? : @bundle.NativeRuntimeBundleStoreOpenFailure? = None,
  failed_journal? : @journal.NativeRemoteJournalOpenFailure? = None,
  release_required? : Bool = false,
) -> SiteEnvironmentOpenCustody {
  {
    original_failure,
    process_hold_id,
    bundles,
    failed_bundle,
    failed_journal,
    release_required,
  }
}

///|
/// Journal physical cleanup precedes process-hold release; Bundle close
/// follows its release ACK. Missing/unknown release is not returned custody.
fn retry_site_environment_open_custody(
  original : SiteEnvironmentOpenCustody,
) -> Bool {
  if original.failed_journal is Some(same) {
    guard same.retry_cleanup() is Ok(_) else { return false }
    original.failed_journal = None
  }
  if original.bundles is Some(same) {
    if original.release_required {
      guard same.release(original.process_hold_id) is Ok(true) else {
        return false
      }
      original.release_required = false
    }
    guard same.close_checked() is Ok(_) else { return false }
    original.bundles = None
  }
  if original.failed_bundle is Some(same) {
    guard same.retry_cleanup() is Ok(_) else { return false }
    original.failed_bundle = None
  }
  !original.release_required
}

///|
priv struct HolderSiteEnvironmentOpenCleanup {
  original : SiteEnvironmentOpenCustody
  slot : @slot.NativeExecutorSlot
  mut slot_close_unknown : Bool
  mut slot_closed : Bool
}

///|
fn retry_holder_site_environment_open_cleanup(
  custody : HolderSiteEnvironmentOpenCleanup,
) -> Bool {
  guard retry_site_environment_open_custody(custody.original) &&
    !custody.slot_close_unknown else {
    return false
  }
  if custody.slot_closed {
    return true
  }
  let closed = custody.slot.close()
  if closed {
    custody.slot_closed = true
  } else {
    custody.slot_close_unknown = true
  }
  closed
}

///|
/// Before ordinary resources exist, the same failed preparation and inherited
/// Slot use the existing holder lifetime shell. No unfunded channel read,
/// constructor retry or poll/queue is introduced. Bootstrap funding is still
/// an unselected supplier, not a zero-cost admission.
fn finish_failed_site_environment_open(
  original : SiteEnvironmentOpenCustody,
  slot : @slot.NativeExecutorSlot,
) -> HolderCommandClose {
  let custody : HolderSiteEnvironmentOpenCleanup = {
    original,
    slot,
    slot_close_unknown: false,
    slot_closed: false,
  }
  while !@slot.install_native_termination_request() {
    report("cleanup-pending", [("step", "site-open-signal-install")])
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
  ignore(
    retain_holder_cleanup_lifetime(
      custody,
      retry_holder_site_environment_open_cleanup,
      () => CleanupInputEnded,
      wait_holder_cleanup_lifetime_signal,
      (_, control_ended) => {
        report("cleanup-pending", [
          ("step", "site-environment-open"),
          ("control_ended", control_ended.to_string()),
        ])
      },
    ),
  )
  HolderCommandFailed(None, original.original_failure)
}
