///|
/// Facts returned from this one original preparation/action. A generic Store
/// error is not proof that its retain/release was never applied.
priv enum ControlBundleCustodyCompletion {
  BundleCustodyRejected(String)
  BundleCustodyPrepared(@bundle_protocol.RemoteBundleCustodyResponse)
  BundleCustodyUncertain(@agent.NativeBundleCustodyIssue)
}

///|
/// One existing delivery, Store/open-failure and Slot. No additional queue,
/// durable ledger, custody issuer or reconstruction from current data.
priv struct ControlBundleCustodyCleanup {
  delivery : @remote.RemotePollBundleCustody
  completion : ControlBundleCustodyCompletion
  mut store : @bundle.NativeRuntimeBundleStore?
  mut failed_store : @bundle.NativeRuntimeBundleStoreOpenFailure?
  slot : @slot.NativeExecutorSlot
  mut slot_retired : Bool
  mut slot_close_unknown : Bool
}

///|
fn control_bundle_custody_cleanup(
  delivery : @remote.RemotePollBundleCustody,
  slot : @slot.NativeExecutorSlot,
  completion : ControlBundleCustodyCompletion,
  store? : @bundle.NativeRuntimeBundleStore? = None,
  failed_store? : @bundle.NativeRuntimeBundleStoreOpenFailure? = None,
) -> ControlBundleCustodyCleanup {
  {
    delivery,
    completion,
    store,
    failed_store,
    slot,
    slot_retired: false,
    slot_close_unknown: false,
  }
}

///|
/// One checked pass against only original handles. Physical retirement is
/// independent of the saved response and Coordinator report ACK.
fn retry_control_bundle_custody_cleanup(
  original : ControlBundleCustodyCleanup,
) -> Bool {
  if original.failed_store is Some(same) {
    guard same.retry_cleanup() is Ok(_) else { return false }
    original.failed_store = None
  }
  if original.store is Some(same) {
    guard same.close_checked() is Ok(_) else { return false }
    original.store = None
  }
  if original.slot_close_unknown {
    return false
  }
  if !original.slot_retired {
    guard original.slot.close() else {
      original.slot_close_unknown = true
      return false
    }
    original.slot_retired = true
  }
  true
}

///|
/// A prepared response reaches only its existing report Owner after physical
/// ACKs. Unconfirmed action/response binding keeps this exact duty and never
/// returns to Waiting or calls the Store action again.
/// Private callers can observe the same synchronous progress without writing
/// into the test driver stream; the production default remains the CLI report.
fn advance_control_bundle_custody_cleanup(
  original : ControlBundleCustodyCleanup,
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> PendingBundleCustody? {
  guard retry_control_bundle_custody_cleanup(original) else {
    return Some(Retiring(original))
  }
  match original.completion {
    BundleCustodyRejected(reason) => {
      report_progress("bundle-custody-refused", [("reason", reason)])
      None
    }
    BundleCustodyPrepared(response) =>
      match
        @agent.prepare_native_bundle_custody_pending_report(
          original.delivery,
          response,
        ) {
        Ok(pending) => Some(Responding(pending))
        Err(_) =>
          Some(
            report_unconfirmed_bundle_custody(
              Unconfirmed(original),
              "response-identity",
              "response",
              report_progress~,
            ),
          )
      }
    BundleCustodyUncertain(issue) =>
      Some(
        report_unconfirmed_bundle_custody(
          Unconfirmed(original),
          "original-store-outcome",
          match issue {
            @agent.AuthorityRejected => "authority-rejected"
            @agent.AdmissionClosed => "admission-closed"
            @agent.RegistrationMismatch => "registration-mismatch"
            @agent.Store(_) => "store"
          },
          report_progress~,
        ),
      )
  }
}

///|
// Observe this exact transition once, not on subsequent paced reconciliation
// passes. Return the same pending duty; this is no Store retry or close ACK.
fn report_unconfirmed_bundle_custody(
  pending : PendingBundleCustody,
  reason : String,
  category : String,
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> PendingBundleCustody {
  match pending {
    Unconfirmed(original) =>
      report_progress("bundle-custody-unconfirmed", [
        ("reason", reason),
        ("category", category),
        (
          "slot-state",
          if original.slot_close_unknown {
            "unknown"
          } else if original.slot_retired {
            "retired"
          } else {
            "owned"
          },
        ),
      ])
    _ => ()
  }
  pending
}
