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
  if wait_holder_cleanup_signal_ffi() != 0 {
    // A failed mask/wait does not discard custody or start an immediate retry
    // loop. This fallback waits for a later signal and remains unconfirmed.
    report("cleanup-pending", [("step", "holder-signal-wait")])
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
}

///|
priv struct HolderCleanupCustody {
  resources : HolderOutputResources
  environment : SiteEnvironment
  slot : @slot.NativeExecutorSlot
  original_failure : String
  step : Ref[Int]
  mut slot_close_unknown : Bool
}

///|
priv enum HolderOutputResourceClose {
  HolderOutputResourcesClosed
  HolderOutputResourcesPending(HolderCleanupCustody)
}

///|
/// Checked replacement for the old Unit close. It preserves the original
/// HostSetupPending resources and never closes ordinary objects ahead of it.
fn close_holder_output_resources(
  original : HolderCleanupCustody,
) -> HolderOutputResourceClose {
  guard advance_holder_cleanup_pass(original, original.step, 5, (custody, step) => {
    match step {
      0 => close_holder_effect_host_setup(custody.resources) is HostSetupClosed
      1 => custody.resources.transfer_journal.close()
      2 => custody.resources.store.close() is Ok(_)
      3 => custody.resources.transfer.close()
      _ => custody.resources.control.close()
    }
  }) else {
    return HolderOutputResourcesPending(original)
  }
  HolderOutputResourcesClosed
}

///|
/// Ordered caller progress, not a replacement cleanup Owner. Each step invokes
/// the same original Owner. Successful close ACKs are never invoked twice.
fn retry_holder_cleanup_custody(original : HolderCleanupCustody) -> Bool {
  guard close_holder_output_resources(original) is HolderOutputResourcesClosed else {
    return false
  }
  advance_holder_cleanup_pass(original, original.step, 9, (custody, step) => {
    match step {
      5 => custody.environment.journal.close()
      6 =>
        // Missing is not a fabricated release ACK, including after an unknown
        // commit. Keep the exact original holding/Store for reconciliation.
        custody.environment.bundles.release(custody.environment.process_hold_id)
        is Ok(true)
      7 => custody.environment.bundles.close() is Ok(_)
      8 =>
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
/// Real receiver for an existing pending holder, with no synthetic executed
/// value. The same process keeps resources, environment and inherited slot;
/// no CommandStop/process-hold/slot release is reached while close is pending.
fn retain_pending_holder_cleanup(
  resources : HolderOutputResources,
  environment : SiteEnvironment,
  slot : @slot.NativeExecutorSlot,
  original_failure : String,
) -> HolderCleanupCustody {
  let original : HolderCleanupCustody = {
    resources,
    environment,
    slot,
    original_failure,
    step: Ref(0),
    slot_close_unknown: false,
  }
  // Register the existing termination handler only for this closing holder;
  // a termination request remains distinct from physical stop/close ACKs.
  while !@slot.install_native_termination_request() {
    report("cleanup-pending", [("step", "holder-signal-install")])
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
  retain_holder_cleanup_lifetime(
    original,
    retry_holder_cleanup_custody,
    () => {
      match read_holder_lifetime_input() {
        InputLine(line) =>
          if holder_cleanup_progress_frame(line) {
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
}
