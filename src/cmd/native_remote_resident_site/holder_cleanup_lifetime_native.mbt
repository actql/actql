///|
/// The existing holder channel is shared by executed output and unstarted
/// cleanup. It supplies a wake, never materials, execution or cleanup evidence.
fn read_holder_lifetime_input() -> @slot.NativeHolderInput {
  @slot.native_read_holder_input(2097152)
}

///|
extern "C" fn wait_holder_cleanup_signal_ffi() -> Int = "actql_executor_slot_wait_cleanup_signal"

///|
extern "C" fn park_holder_cleanup_unconfirmed_ffi() -> Int = "actql_executor_slot_park_cleanup_unconfirmed"

///|
fn wait_holder_cleanup_lifetime_signal() -> Unit {
  wait_holder_cleanup_lifetime_signal_with_report()
}

///|
fn wait_holder_cleanup_lifetime_signal_with_report(
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> Unit {
  if wait_holder_cleanup_signal_ffi() != 0 {
    // A failed mask/wait does not discard custody or start an immediate retry
    // loop. This fallback waits for a later signal and remains unconfirmed.
    report_progress("cleanup-pending", [("step", "holder-signal-wait")])
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
}

///|
priv struct HolderCleanupCustody {
  mut resources : HolderOutputResources?
  environment : SiteEnvironment
  slot : @slot.NativeExecutorSlot
  original_failure : String
  step : Ref[Int]
  mut slot_close_unknown : Bool
}

///|
priv enum HolderOutputResourceClose {
  HolderOutputResourcesClosed
  HolderOutputResourcesPending
}

///|
/// Checked replacement for the old Unit close. It preserves the original
/// HostSetupPending resources and never closes ordinary objects ahead of it.
fn close_holder_output_resources(
  original : HolderCleanupCustody,
) -> HolderOutputResourceClose {
  guard original.resources is Some(resources) else {
    return HolderOutputResourcesClosed
  }
  guard advance_holder_cleanup_pass(resources, original.step, 7, (same, step) => {
    match step {
      0 =>
        match close_holder_effect_host_setup(same) {
          HostSetupClosed => true
          HostSetupPending(pending) => {
            // Keep the Owner's returned carrier across the next cleanup pass.
            original.resources = Some(pending)
            false
          }
        }
      1 => same.transfer_journal.close()
      2 => same.store.close() is Ok(_)
      3 => same.transfer.close_checked() is Ok(_)
      4 => same.control.close_checked() is Ok(_)
      5 => same.transfer_library.close_checked() is Ok(_)
      _ => same.control_library.close_checked() is Ok(_)
    }
  }) else {
    return HolderOutputResourcesPending
  }
  HolderOutputResourcesClosed
}

///|
/// Ordered caller progress, not a replacement cleanup Owner. Each step invokes
/// the same original Owner. Successful close ACKs are never invoked twice.
fn retry_holder_cleanup_custody(original : HolderCleanupCustody) -> Bool {
  // The caller retains this same original custody across the call and retry.
  // Pending is progress only; no duplicate outer owner is transferred here.
  match close_holder_output_resources(original) {
    HolderOutputResourcesClosed => ()
    HolderOutputResourcesPending => return false
  }
  advance_holder_cleanup_pass(original, original.step, 11, (custody, step) => {
    match step {
      7 => custody.environment.journal.close()
      8 =>
        holder_runtime_process_hold_released(
          custody.environment.bundles.release(
            custody.environment.process_hold_id,
          ),
        )
      9 => custody.environment.bundles.close() is Ok(_)
      10 =>
        if custody.slot_close_unknown {
          false
        } else {
          let closed = custody.slot.close()
          if !closed {
            // Do not retry a potentially consumed/reused raw descriptor.
            custody.slot_close_unknown = true
          }
          closed
        }
      _ => false
    }
  })
}

///|
/// Capacity/current-binding projection for the original private channel only.
/// It grants no Account read/publication/Effect permission. Before detachment
/// the same reservation is in the original scope; afterwards it is forwarded.
fn holder_cleanup_caller_read_current(
  resources : HolderOutputResources,
) -> Bool {
  match
    (
      resources.effect_host_caller_operation,
      resources.effect_host_caller_current,
    ) {
    (Some(operation), Some(current)) =>
      @site.site_operation_available(operation) && current()
    (None, Some(current)) if resources.effect_host_caller_ordinary => current()
    (None, None) =>
      match resources.effect_host_setup.val {
        Some(scope) => scope.current_binding is Some(current) && current()
        None => false
      }
    _ => false
  }
}

///|
/// Real receiver for an existing pending holder, with no synthetic executed
/// value. The same process keeps resources, environment and inherited slot;
/// no CommandStop/process-hold/slot release is reached while close is pending.
fn retain_pending_holder_cleanup(
  resources : HolderOutputResources?,
  environment : SiteEnvironment,
  slot : @slot.NativeExecutorSlot,
  original_failure : String,
) -> String {
  let original : HolderCleanupCustody = {
    resources,
    environment,
    slot,
    original_failure,
    step: Ref(holder_cleanup_initial_position(resources)),
    slot_close_unknown: false,
  }
  // Register the existing termination handler only for this closing holder;
  // a termination request remains distinct from physical stop/close ACKs.
  while !@slot.install_native_termination_request() {
    report("cleanup-pending", [("step", "holder-signal-install")])
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
  let retired = retain_holder_cleanup_lifetime(
    original,
    retry_holder_cleanup_custody,
    () => {
      // A missing profile/reservation is not a free read grant. Keep custody
      // through signal observation instead of allocating another input frame.
      guard original.resources is Some(opened) &&
        holder_cleanup_caller_read_current(opened) else {
        return CleanupInputEnded
      }
      match read_holder_lifetime_input() {
        InputLine(line) =>
          if !holder_cleanup_caller_read_current(opened) {
            CleanupInputEnded
          } else if holder_cleanup_progress_frame(line) {
            CleanupProgress
          } else {
            // Cancel/recovery frames cannot restart Source or mint an ACK here.
            CleanupOther
          }
        InputEnded | InputInvalid => CleanupInputEnded
      }
    },
    wait_holder_cleanup_lifetime_signal,
    (custody, control_ended) => {
      report("cleanup-pending", [
        ("step", "holder-lifetime"),
        ("close_step", custody.step.val.to_string()),
        ("control_ended", control_ended.to_string()),
      ])
    },
  )
  // Consume the original diagnosis only after this receiver has acknowledged
  // its ordered cleanup. It remains the same failure, not a new close result.
  retired.original_failure
}

///|
/// This helper returns the original reservation and diagnosis. Its receiver has
/// ended: the new carrier/Ref and its callbacks/report frames cannot escape.
/// The original run_holder frame must also end before the reservation returns.
fn finish_holder_cleanup_lifetime(
  resources : HolderOutputResources,
  environment : SiteEnvironment,
  slot : @slot.NativeExecutorSlot,
  original_failure : String,
) -> (@site.SiteOperation?, String) {
  let failure = retain_pending_holder_cleanup(
    Some(resources),
    environment,
    slot,
    original_failure,
  )
  resources.effect_host_caller_current = None
  resources.effect_host_caller_ordinary = false
  let operation = resources.effect_host_caller_operation
  resources.effect_host_caller_operation = None
  (operation, failure)
}

///|
/// Preparation refused before ordinary resources existed. Preserve the same
/// environment/process holding/slot until their own close ACKs; do not invent
/// an executed value or a Host setup reservation to enter the cleanup receiver.
fn finish_unopened_holder_cleanup(
  environment : SiteEnvironment,
  slot : @slot.NativeExecutorSlot,
  original_failure : String,
) -> HolderCommandClose {
  let failure = retain_pending_holder_cleanup(
    None,
    environment,
    slot,
    original_failure,
  )
  // No Host operation has been selected here. Bootstrap funding remains a
  // separate missing supplier; None is not a zero-cost capacity admission.
  HolderCommandFailed(None, failure)
}

///|
/// Private command-flow handoff only, not Run status, custody issuance or ACK.
priv enum HolderCommandClose {
  HolderCommandClosed(@site.SiteOperation?)
  HolderCommandFailed(@site.SiteOperation?, String)
}

///|
fn settle_holder_caller_reservation(operation : @site.SiteOperation?) -> Unit {
  if operation is Some(original) {
    // No Reader reopen, recurring timer or replacement reservation. A failure
    // retains this exact nominal operation and only waits for another event.
    while !@site.settle_site_operation(original) {
      wait_holder_cleanup_lifetime_signal()
    }
  }
}

///|
/// Called only after run_holder returned, so its installed/scope/output aliases
/// and the entire receiver frame have ended. Matching consumes the private
/// handoff. Normal completion waits for settlement; a failed diagnostic keeps
/// that responsibility through the existing terminal consumer instead.
/// This is a lifetime boundary, never a promise of GC or RSS reclamation.
#owned(closed)
fn finish_holder_command(
  closed : HolderCommandClose,
) -> HolderTerminalFailure? raise CommandStop {
  match closed {
    HolderCommandClosed(operation) =>
      settle_holder_caller_reservation(operation)
    HolderCommandFailed(operation, failure) =>
      match operation {
        Some(original) => return Some({ operation: original, failure, })
        None => stop(failure)
      }
  }
  None
}

///|
/// The same nominal operation and diagnostic cross only the private command
/// caller boundary. This is not a persisted Run outcome or a cleanup Owner.
priv struct HolderTerminalFailure {
  operation : @site.SiteOperation
  failure : String
}

///|
/// The existing terminal abort does not return. Preserve the original funded
/// operation through its diagnostic consumption; no settlement ACK is inferred
/// from returning the private command handoff or from process termination.
fn consume_holder_terminal_failure(
  operation : @site.SiteOperation,
  failure : String,
) -> Unit {
  retain_holder_terminal_reservation(
    operation,
    () => abort("actql-native-remote-resident-site: " + failure),
    original => settle_holder_caller_reservation(Some(original)),
  )
}
