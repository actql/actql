///|
/// Actual partial construction, not a new resource/Run Owner. Each optional
/// field is the original object returned by the existing physical constructor.
priv struct HolderPartialOutputResources {
  mut retained_root : @filesystem.Root?
  mut failed_root : @filesystem.NativeRootOpenFailure?
  mut control : @http.Client?
  mut control_library : @http.Library?
  mut transfer : @http.Client?
  mut transfer_library : @http.Library?
  mut failed_http_library : @http.NativeHttpLibraryLoadFailure?
  mut failed_http_client : @http.NativeHttpClientCreateFailure?
  mut store : @publication_store.Store?
  mut failed_store : @publication_store.NativePublicationStoreOpenFailure?
  mut transfer_journal : @transfer_journal.Journal?
  mut failed_transfer_journal : @transfer_journal.NativeRemoteTransferJournalOpenFailure?
}

///|
priv enum HolderOutputSetupFailure {
  HolderOutputSetupRefused(String)
  HolderOutputSetupPending(HolderPartialOutputResources, String)
}

///|
fn new_holder_partial_output_resources() -> HolderPartialOutputResources {
  {
    retained_root: None,
    failed_root: None,
    control: None,
    control_library: None,
    transfer: None,
    transfer_library: None,
    failed_http_library: None,
    failed_http_client: None,
    store: None,
    failed_store: None,
    transfer_journal: None,
    failed_transfer_journal: None,
  }
}

///|
priv struct HolderHttpSettings {
  library_path : String
  ca_path : String
  authentication : @http.NativeHttpAuthentication
  response_bytes : Int64
  connect_ms : Int
  total_ms : Int
}

///|
/// Pure option extraction precedes any acquisition. No credential file is
/// read, no permission inferred and no physical configuration admitted here.
fn holder_http_settings(
  matches : @argparse.Matches,
  prefix : String,
) -> HolderHttpSettings raise CommandStop {
  let authentication : @http.NativeHttpAuthentication = match
    (
      optional(matches, prefix + "-cert"),
      optional(matches, prefix + "-key"),
      optional(matches, prefix + "-bearer-file"),
    ) {
    (Some(cert), Some(key), Some(bearer)) =>
      MutualTlsAndBearer(cert, key, bearer)
    (Some(cert), Some(key), None) => MutualTls(cert, key)
    (None, None, Some(bearer)) => Bearer(bearer)
    _ =>
      stop(
        prefix + " authentication needs a bearer file or a certificate and key",
      )
  }
  {
    library_path: required(matches, "http-library"),
    ca_path: required(matches, "ca"),
    authentication,
    response_bytes: required_int64(matches, "max-response-bytes"),
    connect_ms: required_int(matches, "connect-timeout-ms"),
    total_ms: required_int(matches, "total-timeout-ms"),
  }
}

///|
fn open_holder_partial_http_client(
  original : HolderPartialOutputResources,
  settings : HolderHttpSettings,
  control_role : Bool,
) -> Result[@http.Client, HolderOutputSetupFailure] {
  let library = match @http.load_library_with_custody(settings.library_path) {
    Ok(value) => value
    Err(RefusedBeforeAcquisition(_)) =>
      return Err(
        holder_output_setup_failure(
          original, "HTTP library configuration refused",
        ),
      )
    Err(CleanupRequired(failure)) => {
      original.failed_http_library = Some(failure)
      return Err(
        HolderOutputSetupPending(original, "HTTP library acquisition failed"),
      )
    }
  }
  if control_role {
    original.control_library = Some(library)
  } else {
    original.transfer_library = Some(library)
  }
  match
    library.create_authenticated_client_with_custody(
      settings.ca_path,
      settings.authentication,
      settings.response_bytes,
      settings.connect_ms,
      settings.total_ms,
    ) {
    Ok(value) => {
      if control_role {
        original.control = Some(value)
      } else {
        original.transfer = Some(value)
      }
      Ok(value)
    }
    Err(RefusedBeforeAcquisition(_)) =>
      Err(
        HolderOutputSetupPending(
          original, "HTTP Client configuration refused after Library acquisition",
        ),
      )
    Err(CleanupRequired(failure)) => {
      original.failed_http_client = Some(failure)
      Err(HolderOutputSetupPending(original, "HTTP Client acquisition failed"))
    }
  }
}

///|
/// Only actual constructor references distinguish pre-acquisition refusal
/// from a cleanup responsibility. This is not an execution/outcome classifier.
fn holder_output_setup_failure(
  original : HolderPartialOutputResources,
  issue : String,
) -> HolderOutputSetupFailure {
  if original.retained_root is Some(_) ||
    original.failed_root is Some(_) ||
    original.control is Some(_) ||
    original.control_library is Some(_) ||
    original.transfer is Some(_) ||
    original.transfer_library is Some(_) ||
    original.failed_http_library is Some(_) ||
    original.failed_http_client is Some(_) ||
    original.store is Some(_) ||
    original.failed_store is Some(_) ||
    original.transfer_journal is Some(_) ||
    original.failed_transfer_journal is Some(_) {
    HolderOutputSetupPending(original, issue)
  } else {
    HolderOutputSetupRefused(issue)
  }
}

///|
/// One bounded pass on the exact original constructors in reverse order.
/// Each checked close concerns only the same original resource. A pending
/// request, failed Library retirement or lost observation retains that original
/// and the outer Root; neither logical cancel nor finalization supplies ACK.
fn retry_partial_holder_output_resources(
  original : HolderPartialOutputResources,
) -> Bool {
  if original.failed_transfer_journal is Some(owner) {
    guard owner.retry_cleanup() is Ok(_) else { return false }
    original.failed_transfer_journal = None
  }
  if original.transfer_journal is Some(owner) {
    guard owner.close_checked() is Ok(_) else { return false }
    original.transfer_journal = None
  }
  if original.failed_store is Some(owner) {
    guard owner.retry_cleanup() is Ok(_) else { return false }
    original.failed_store = None
  }
  if original.store is Some(owner) {
    guard owner.close() is Ok(_) else { return false }
    original.store = None
  }
  if original.failed_http_client is Some(owner) {
    let residual = match owner.retry_cleanup() {
      Ok(library) => library
      Err(_) => return false
    }
    guard (
        original.control_library is Some(library) &&
        physical_equal(residual, library)
      ) ||
      (
        original.transfer_library is Some(library) &&
        physical_equal(residual, library)
      ) else {
      return false
    }
    original.failed_http_client = None
  }
  if original.failed_http_library is Some(owner) {
    guard owner.retry_cleanup() is Ok(_) else { return false }
    original.failed_http_library = None
  }
  if original.transfer is Some(owner) {
    guard owner.close_checked() is Ok(_) else { return false }
    original.transfer = None
  }
  if original.control is Some(owner) {
    guard owner.close_checked() is Ok(_) else { return false }
    original.control = None
  }
  if original.transfer_library is Some(owner) {
    guard owner.close_checked() is Ok(_) else { return false }
    original.transfer_library = None
  }
  if original.control_library is Some(owner) {
    guard owner.close_checked() is Ok(_) else { return false }
    original.control_library = None
  }
  if original.failed_root is Some(owner) {
    guard owner.retry_cleanup() is Ok(_) else { return false }
    original.failed_root = None
  }
  if original.retained_root is Some(owner) {
    guard owner.close() is Ok(_) else { return false }
    original.retained_root = None
  }
  true
}

///|
/// Same original environment/process hold/slot, held by the existing lifetime
/// shell. There is no synthetic executed value or replacement cleanup queue.
priv struct HolderPartialSetupCleanup {
  resources : HolderPartialOutputResources
  environment : SiteEnvironment
  slot : @slot.NativeExecutorSlot
  failure : String
  step : Ref[Int]
  mut slot_close_unknown : Bool
}

///|
fn retain_partial_holder_output_setup(
  resources : HolderPartialOutputResources,
  environment : SiteEnvironment,
  slot : @slot.NativeExecutorSlot,
  failure : String,
) -> Unit {
  let original : HolderPartialSetupCleanup = {
    resources,
    environment,
    slot,
    failure,
    step: Ref(0),
    slot_close_unknown: false,
  }
  install_partial_holder_cleanup_signal()
  ignore(
    retain_holder_cleanup_lifetime(
      original,
      custody => {
        advance_holder_cleanup_pass(custody, custody.step, 5, (owner, step) => {
          match step {
            0 => retry_partial_holder_output_resources(owner.resources)
            1 => owner.environment.journal.close_checked() is Ok(_)
            2 =>
              owner.environment.bundles.release(
                owner.environment.process_hold_id,
              )
              is Ok(true)
            3 => owner.environment.bundles.close_checked() is Ok(_)
            _ =>
              if owner.slot_close_unknown {
                false
              } else {
                let closed = owner.slot.close()
                if !closed {
                  owner.slot_close_unknown = true
                }
                closed
              }
          }
        })
      },
      // Before installation, no caller operation covers a new input frame.
      // Preserve the same custody using the existing signal wait, never free I/O.
      () => CleanupInputEnded,
      wait_holder_cleanup_lifetime_signal,
      (owner, control_ended) => {
        report("setup-cleanup-pending", [
          ("reason", owner.failure),
          ("step", owner.step.val.to_string()),
          ("control_ended", control_ended.to_string()),
        ])
      },
    ),
  )
}

///|
fn install_partial_holder_cleanup_signal(
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> Unit {
  while !@slot.install_native_termination_request() {
    report_progress("setup-cleanup-pending", [("step", "signal-install")])
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
}

///|
priv struct PartialOutputRecoveryCleanup {
  resources : HolderPartialOutputResources
  recovery : StoppedReleaseRecovery
  slot : @slot.NativeExecutorSlot
  failure : String
  step : Ref[Int]
  mut slot_close_unknown : Bool
}

///|
/// Maintenance custody is not a fresh SiteEnvironment or process holding.
/// In particular this never invents/release a holding this tool did not own.
/// The same lifetime also accepts a completed setup's exact objects; no new
/// constructor runs, and pending child/Library cleanup keeps the outer slot.
fn retain_partial_output_recovery_setup(
  resources : HolderPartialOutputResources,
  recovery : StoppedReleaseRecovery,
  slot : @slot.NativeExecutorSlot,
  failure : String,
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> Unit {
  let original = partial_output_recovery_cleanup(
    resources, recovery, slot, failure,
  )
  install_partial_holder_cleanup_signal(report_progress~)
  ignore(
    retain_holder_cleanup_lifetime(
      original,
      retry_partial_output_recovery_cleanup,
      () => CleanupInputEnded,
      () => wait_holder_cleanup_lifetime_signal_with_report(report_progress~),
      (owner, control_ended) => {
        report_progress("output-recovery-setup-cleanup-pending", [
          ("reason", owner.failure),
          ("step", owner.step.val.to_string()),
          ("control_ended", control_ended.to_string()),
        ])
      },
    ),
  )
}

///|
fn partial_output_recovery_cleanup(
  resources : HolderPartialOutputResources,
  recovery : StoppedReleaseRecovery,
  slot : @slot.NativeExecutorSlot,
  failure : String,
) -> PartialOutputRecoveryCleanup {
  let original : PartialOutputRecoveryCleanup = {
    resources,
    recovery,
    slot,
    failure,
    step: Ref(0),
    slot_close_unknown: false,
  }
  original
}

///|
/// The already-admitted cleanup must finish before its borrowed parents close.
/// Progress records that observation locally; it never issues Run settlement
/// or sets physical_cleanup_done from handle closure or an empty resource set.
fn retry_partial_output_recovery_cleanup(
  original : PartialOutputRecoveryCleanup,
) -> Bool {
  advance_holder_cleanup_pass(original, original.step, 5, (owner, step) => {
    match step {
      0 =>
        match owner.recovery.physical_cleanup {
          Some(_) if !owner.recovery.physical_cleanup_done =>
            retry_stopped_holder_cleanup_callback(owner.recovery)
          _ => true
        }
      1 => {
        if owner.recovery.transfer_journal is Some(journal) {
          guard journal.close_checked() is Ok(_) else { return false }
          owner.recovery.transfer_journal = None
        }
        guard retry_partial_holder_output_resources(
          owner.recovery.input_cleanup_resources,
        ) else {
          return false
        }
        retry_partial_holder_output_resources(owner.resources)
      }
      2 =>
        if owner.recovery.terminal_close is RecoveryTerminalOpen {
          owner.recovery.journal.close_checked() is Ok(_)
        } else {
          retry_stopped_recovery_terminal_handles(owner.recovery)
        }
      3 => {
        if !owner.recovery.bundle_closed {
          guard owner.recovery.bundles.close_checked() is Ok(_) else {
            return false
          }
          owner.recovery.bundle_closed = true
        }
        true
      }
      _ =>
        if owner.recovery.terminal_close is RecoveryTerminalClosed {
          true
        } else if owner.slot_close_unknown {
          false
        } else {
          let closed = owner.slot.close()
          if !closed {
            owner.slot_close_unknown = true
          }
          closed
        }
    }
  })
}
