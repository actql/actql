///|
// Acquisition and cleanup address the same exact retained consumer component.
fn consumer_process_hold_identity(request : @remote.DispatchRequest) -> String {
  "consumer:" + @remote.dispatch_request_identity(request)
}

///|
/// Keep only the existing recovery's exact constructor originals. A failed
/// constructor may retire its own partial handles, but remains failed; this
/// entrance never replaces it with a new acquisition or another configured path.
fn stopped_holder_cleanup_resources(
  owner : StoppedReleaseRecovery,
  transfer_path : String,
  root_path : String?,
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> (@transfer_journal.Journal, @filesystem.Root?)? {
  match owner.input_cleanup_paths {
    Some((original_transfer, original_root)) =>
      if transfer_path != original_transfer || root_path != original_root {
        return None
      }
    None => owner.input_cleanup_paths = Some((transfer_path, root_path))
  }
  let resources = owner.input_cleanup_resources
  if resources.failed_transfer_journal is Some(original) {
    let closed = original.retry_cleanup() is Ok(_)
    report_progress("release-recovery-pending", [
      ("step", "transfer-journal-constructor"),
      (
        "code",
        if closed {
          "original-constructor-failed"
        } else {
          "cleanup-unconfirmed"
        },
      ),
    ])
    return None
  }
  if resources.failed_root is Some(original) {
    let closed = original.retry_cleanup() is Ok(_)
    report_progress("release-recovery-pending", [
      ("step", "retained-root-constructor"),
      (
        "code",
        if closed {
          "original-constructor-failed"
        } else {
          "cleanup-unconfirmed"
        },
      ),
    ])
    return None
  }
  let transfers = match owner.transfer_journal {
    Some(original) => original
    None =>
      match
        @transfer_journal.open_journal_with_custody(
          owner.environment.sqlite_library,
          transfer_path,
          owner.environment.max_record_bytes,
          65536,
          1048576,
          owner.environment.max_bytes,
        ) {
        Ok(original) => {
          owner.transfer_journal = Some(original)
          original
        }
        Err(RefusedBeforeAcquisition(_)) => return None
        Err(CleanupRequired(original)) => {
          resources.failed_transfer_journal = Some(original)
          return None
        }
      }
  }
  let root = match root_path {
    None => None
    Some(path) =>
      match resources.retained_root {
        Some(original) => Some(original)
        None =>
          match @filesystem.open_root_with_custody(path) {
            Ok(original) => {
              resources.retained_root = Some(original)
              Some(original)
            }
            Err(original) => {
              resources.failed_root = Some(original)
              return None
            }
          }
      }
  }
  Some((transfers, root))
}

///|
/// Record the original admitted callback's ACK once, independently of later
/// handle retirement. No callback means no physical cleanup confirmation.
fn retry_stopped_holder_cleanup_callback(
  owner : StoppedReleaseRecovery,
) -> Bool {
  if owner.physical_cleanup_done {
    return true
  }
  guard owner.physical_cleanup is Some(original) else { return false }
  advance_holder_cleanup_pass(owner, owner.input_cleanup_step, 1, (_, _) => {
    original()
  })
}

///|
/// Parent descriptors may close only after the existing admitted callback.
/// A pending close keeps both the same original and its observed child ACK;
/// closing handles alone cannot set the recovery's physical cleanup state.
fn retry_stopped_holder_cleanup_handles(owner : StoppedReleaseRecovery) -> Bool {
  guard retry_stopped_holder_cleanup_callback(owner) else { return false }
  guard advance_holder_cleanup_pass(owner, owner.input_cleanup_step, 3, (
    same,
    step,
  ) => {
    if step == 1 {
      if same.transfer_journal is Some(original) {
        guard original.close_checked() is Ok(_) else { return false }
        same.transfer_journal = None
      }
      true
    } else {
      retry_partial_holder_output_resources(same.input_cleanup_resources)
    }
  }) else {
    return false
  }
  owner.physical_cleanup_done = true
  // The checked callback captures this same recovery Owner. Every original
  // callback and child-handle ACK above has completed; retire only that
  // managed back-reference, preserving the durable/parent cleanup below.
  owner.physical_cleanup = None
  true
}

///|
/// End this failed construction attempt after checked handle retirement, while
/// leaving the original Run unsettled. The controller may later select its
/// existing recovery entrance; it cannot reuse this failed constructor.
fn retire_failed_stopped_holder_input_constructor(
  owner : StoppedReleaseRecovery,
  retained : Ref[StoppedReleaseRecovery?],
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> Unit {
  guard retained.val is Some(same) && physical_equal(same, owner) else {
    return
  }
  guard owner.input_cleanup_resources.failed_root is Some(_) ||
    owner.input_cleanup_resources.failed_transfer_journal is Some(_) else {
    return
  }
  retain_partial_output_recovery_setup(
    new_holder_partial_output_resources(),
    owner,
    owner.slot,
    "stopped input constructor failed",
    report_progress~,
  )
  // This reference is physical caller custody only. The enclosing recovery
  // still returns false and commits no release or execution transition.
  retained.val = None
}

///|
/// The exclusive holder slot proves that no former process can keep using
/// these exact files or readers. Historical binding admission selects the
/// existing cleanup Owners; no payload use or fresh borrow is authorized here.
fn settle_stopped_holder_custody(
  matches : @argparse.Matches,
  owner : StoppedReleaseRecovery,
  request : @remote.DispatchRequest,
  report_progress? : (String, Array[(String, String)]) -> Unit = report,
) -> Bool raise CommandStop {
  if owner.physical_cleanup_done {
    return true
  }
  let environment = owner.environment
  let scope = @remote.dispatch_request_execution_scope(request)
  let cleanup_current = () => {
    owner.slot.verify_current_hold() == Ok(()) &&
    environment.site_key == scope[0] &&
    environment.site_generation.to_string() == scope[1] &&
    environment.runtime_bundle_cid == scope[2]
  }
  if !cleanup_current() {
    return false
  }
  if owner.physical_cleanup is None {
    let root_path = optional(matches, "retained-input-root")
    guard stopped_holder_cleanup_resources(
        owner,
        required(matches, "transfer-journal"),
        root_path,
        report_progress~,
      )
      is Some((transfers, root)) else {
      return false
    }
    if owner.recorded_source is Some(original) {
      guard root_path is Some(path) &&
        root is Some(retained_root) &&
        owner.recorded_consumer is Some((consumer_attempt, expected_consumer)) else {
        return false
      }
      let envelope = match owner.journal.dispatch_envelope(consumer_attempt) {
        Ok(Some(value)) => value
        _ => return false
      }
      guard @remote.admit_remote_poll_dispatch_json(envelope) is Ok(consumer) &&
        @remote.dispatch_request_identity(
          @remote.remote_poll_dispatch_request(consumer),
        ) ==
        expected_consumer else {
        return false
      }
      let delegated = delegation(matches, budget(matches))
      if !saved_output_bundle_current(
          owner.bundles,
          delegated,
          required(matches, "target-triple"),
        ) {
        return false
      }
      guard @site.create_site(
          environment.site_key,
          environment.site_generation,
          environment.runtime_bundle_cid,
          environment.max_operations,
          environment.max_transfers,
          environment.max_bytes,
          environment.max_bytes,
        )
        is Some(site) else {
        return false
      }
      let producer_attempt = match
        @remote.dispatch_request_attempt_identity(request) {
        Ok(value) => value
        Err(_) => return false
      }
      // Source, receiver and borrow responsibility must be discharged before
      // the existing formal-release owner can return the producer capability.
      let confirmed = match
        @resident_host.reclaim_stopped_resident_source_output(
          owner.journal,
          run_admission(matches),
          site,
          delegated,
          producer_attempt,
          consumer_attempt,
          transfers,
          retained_root,
          path,
          {
            max_binding_bytes: 1048576,
            max_chunks: 65536,
            max_manifest_bytes: 1048576,
            max_referenced_bytes: environment.max_bytes,
          },
          cleanup_current,
          recorded=Some(original),
        ) {
        Ok(value) => value
        Err(_) => return false
      }
      let (_, checked_consumer) = @host.client_retained_source_cleanup_requests(
        confirmed,
      )
      // Older recovery used the holder claimant for this component. Use the
      // same identity as acquisition, from the Owner-confirmed relationship.
      match
        owner.bundles.release(consumer_process_hold_identity(checked_consumer)) {
        Ok(_) => ()
        Err(_) => return false
      }
    }
    // This is an explicitly selected completed-custody maintenance path,
    // never fallback from failed executable-material admission. The existing
    // cleanup Owner requires both original durable completion observations,
    // their accepted binding and current Site/delegation before reclaiming.
    let completed_input = if owner.completed_input_producer
      is Some((producer_attempt, expected_producer)) {
      let envelope = match owner.journal.dispatch_envelope(producer_attempt) {
        Ok(Some(value)) => value
        _ => return false
      }
      guard @remote.admit_remote_poll_dispatch_json(envelope) is Ok(producer) &&
        @remote.dispatch_request_identity(
          @remote.remote_poll_dispatch_request(producer),
        ) ==
        expected_producer &&
        @remote.dispatch_request_attempt_identity(request)
        is Ok(consumer_attempt) &&
        root is Some(receiver_root) else {
        return false
      }
      guard @site.create_site(
          environment.site_key,
          environment.site_generation,
          environment.runtime_bundle_cid,
          environment.max_operations,
          environment.max_transfers,
          environment.max_bytes,
          environment.max_bytes,
        )
        is Some(site) else {
        return false
      }
      match
        @resident_host.reclaim_stopped_resident_retained_input(
          owner.journal,
          site,
          delegation(matches, budget(matches)),
          producer_attempt,
          consumer_attempt,
          transfers,
          receiver_root,
          {
            max_binding_bytes: 1048576,
            max_chunks: 65536,
            max_manifest_bytes: 1048576,
            max_referenced_bytes: environment.max_bytes,
          },
          cleanup_current,
        ) {
        Ok(_) => true
        Err(_) => {
          report_progress("release-recovery-pending", [
            ("request_cid", @remote.dispatch_request_identity(request)),
            ("step", "completed-input-cleanup"),
            ("code", "cleanup-unconfirmed"),
          ])
          return false
        }
      }
    } else {
      false
    }
    let input = if completed_input {
      Some(() => true)
    } else {
      match
        @resident_host.prepare_resident_saved_input_cleanup(
          owner.journal,
          transfers,
          root,
          run_admission(matches),
          request,
          environment.max_bytes,
          cleanup_current,
          recorded_source=owner.recorded_source,
        ) {
        Ok(value) => value
        Err(issue) => {
          // Report only fixed refusal codes. Historical cleanup must remain
          // pending; arbitrary messages and saved materials are never printed.
          let code = match issue {
            Refused(reason) => refusal_code(reason)
            _ => "input-custody-unconfirmed"
          }
          report_progress("release-recovery-pending", [
            ("request_cid", @remote.dispatch_request_identity(request)),
            ("step", "input-admission"),
            ("code", code),
          ])
          return false
        }
      }
    }
    let recovered = match owner.journal.observation(request) {
      Ok(value) => value
      Err(_) => return false
    }
    let release_input = input.unwrap_or(() => true)
    let cleanup = match
      @journal.recovered_site_dispatch_file_custody(recovered) {
      Some(_) => {
        guard root_path is Some(path) else { return false }
        match
          @output.prepare_native_remote_standard_saved_output_cleanup(
            recovered,
            path,
            required_int64(matches, "max-output-bytes"),
            release_input,
            cleanup_current,
          ) {
          Some(value) => value
          None => return false
        }
      }
      None => {
        // A completed retained task requires its original output custody.
        // Absence is not evidence that its file was physically reclaimed.
        let record = @journal.recovered_site_dispatch_record(recovered)
        if input is Some(_) &&
          @remote.dispatch_record_state_codes(record)[0] == 3 {
          return false
        }
        () => cleanup_current() && release_input()
      }
    }
    owner.retained_input = input is Some(_)
    owner.physical_cleanup = Some(cleanup)
  }
  if !retry_stopped_holder_cleanup_handles(owner) {
    report_progress("release-recovery-pending", [
      ("request_cid", @remote.dispatch_request_identity(request)),
      ("step", "physical-cleanup"),
      ("code", "cleanup-unconfirmed"),
    ])
    return false
  }
  true
}
