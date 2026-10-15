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
  // Selected Library custody outlives every Store/Journal Database alias.
  // Its installer keeps the same original read domain alive until this ACK.
  mut selected_sqlite_library : @sqlite.Library?
  mut failed_sqlite_library : @sqlite.NativeSqliteLibraryLoadFailure?
}

///|
fn site_environment_open_custody(
  original_failure : String,
  process_hold_id : String,
  bundles? : @bundle.NativeRuntimeBundleStore? = None,
  failed_bundle? : @bundle.NativeRuntimeBundleStoreOpenFailure? = None,
  failed_journal? : @journal.NativeRemoteJournalOpenFailure? = None,
  release_required? : Bool = false,
  selected_sqlite_library? : @sqlite.Library? = None,
  failed_sqlite_library? : @sqlite.NativeSqliteLibraryLoadFailure? = None,
) -> SiteEnvironmentOpenCustody {
  {
    original_failure,
    process_hold_id,
    bundles,
    failed_bundle,
    failed_journal,
    release_required,
    selected_sqlite_library,
    failed_sqlite_library,
  }
}

///|
/// Journal physical cleanup precedes process-hold release; Bundle close
/// follows its release ACK. Missing/unknown release is not returned custody.
/// This frame ends before the Library close: its temporary Store/Database
/// aliases must not keep that original Library alive across the next phase.
fn retry_site_environment_open_objects(
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
/// Only the existing Library Owner can acknowledge retirement. Missing or
/// foreign context, legacy Library and unknown close remain pending. No reload
/// or context replacement occurs here. A failed leave/domain/Host still belongs
/// to the same outer installer after this Library's own ACK.
fn retry_site_environment_open_libraries(
  original : SiteEnvironmentOpenCustody,
) -> Bool {
  if original.selected_sqlite_library is Some(same) {
    guard same.close_checked() is Ok(_) else { return false }
    original.selected_sqlite_library = None
  }
  if original.failed_sqlite_library is Some(same) {
    guard same.retry_cleanup() is Ok(_) else { return false }
    original.failed_sqlite_library = None
  }
  true
}

///|
/// Do not fold these two helpers into a single frame: even a closed Database
/// external object retains its Library child until that managed alias retires.
/// This is an ordering boundary, not a GC/RSS or domain-retirement guarantee.
fn retry_site_environment_open_custody(
  original : SiteEnvironmentOpenCustody,
) -> Bool {
  retry_site_environment_open_objects(original) &&
  retry_site_environment_open_libraries(original)
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
