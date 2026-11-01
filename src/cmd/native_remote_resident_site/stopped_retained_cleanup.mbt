///|
/// Reconcile only the original completed consumer's durable input borrow and
/// receiver holding. The exclusive executor slot fences both stopped holders.
/// This command grants no execution permission and commits no release state.
fn recover_retained_input_command(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
  child : @argparse.Matches,
  source_output? : Bool = false,
  cancelled_receiver? : Bool = false,
) -> Unit raise CommandStop {
  // Resolve configuration before acquiring any physical owner.
  let producer_attempt = required(child, "producer-attempt")
  let consumer_attempt = required(child, "consumer-attempt")
  let expected_producer = required(child, "expect-producer-dispatch")
  let expected_consumer = required(child, "expect-consumer-dispatch")
  // Explicit maintenance admission uses the original issued bytes. A missing
  // consumer envelope is never a fallback from the completed-borrow operation.
  let cancelled_materials = if cancelled_receiver {
    let recovery_root = required(child, "recovery-materials-root")
    let consumer = match
      @remote.admit_dispatch_request_json(
        load_text(recovery_root, "consumer-request.json", 1048576L),
        expected_consumer,
      ) {
      Ok(value) => value
      Err(_) => stop("cancelled receiver original consumer invalid")
    }
    let transfer = match
      @remote.admit_remote_poll_retained_input_transfer_json(
        load_text(recovery_root, "retained-transfer.json", 1048576L),
      ) {
      Ok(value) => value
      Err(_) => stop("cancelled receiver original plan invalid")
    }
    let producer = @remote.remote_retained_input_intent_request(
      @remote.remote_poll_retained_transfer_intent(transfer),
    )
    if @remote.dispatch_request_attempt_identity(consumer) !=
      Ok(consumer_attempt) ||
      @remote.dispatch_request_attempt_identity(producer) !=
      Ok(producer_attempt) ||
      @remote.dispatch_request_identity(producer) != expected_producer {
      stop("cancelled receiver original identity mismatch")
    }
    Some(
      (
        consumer,
        transfer,
        load_recorded_publication(required(child, "publication-custody-root")),
      ),
    )
  } else {
    None
  }
  let root_path = required(matches, "retained-input-root")
  let transfer_path = required(matches, "transfer-journal")
  let delegated = delegation(matches, budget(matches))
  let target = required(matches, "target-triple")
  let environment = open_control_environment(matches, entry)
  let site = match
    @site.create_site(
      environment.site_key,
      environment.site_generation,
      environment.runtime_bundle_cid,
      environment.max_operations,
      environment.max_transfers,
      environment.max_bytes,
      environment.max_bytes,
    ) {
    Some(value) => value
    None => stop("retained cleanup invalid current Site")
  }
  let slot = match
    @slot.open_native_executor_slot(required(matches, "executor-slot")) {
    Ok(value) => value
    Err(_) => stop("retained cleanup slot unavailable")
  }
  if slot.try_acquire() != Ok(true) {
    ignore(slot.close())
    stop("retained cleanup slot busy")
  }
  let owner = open_release_recovery(
    matches, environment, slot, expected_consumer,
  )
  let receiver : Ref[@transfer_journal.Journal?] = { val: None, }
  let failure = try {
    for
      (attempt, expected) in [
        (producer_attempt, expected_producer),
        (consumer_attempt, expected_consumer),
      ] {
      if cancelled_receiver && attempt == consumer_attempt {
        // The exact persisted cancellation record is checked by the Native
        // Owner below. No dispatch envelope is created for an undelivered task.
        continue
      }
      let envelope = match owner.journal.dispatch_envelope(attempt) {
        Ok(Some(value)) => value
        _ => stop("retained cleanup saved dispatch unavailable")
      }
      let saved = match @remote.admit_remote_poll_dispatch_json(envelope) {
        Ok(value) => value
        Err(_) => stop("retained cleanup saved dispatch invalid")
      }
      if @remote.dispatch_request_identity(
          @remote.remote_poll_dispatch_request(saved),
        ) !=
        expected {
        stop("retained cleanup dispatch mismatch")
      }
    }
    let current = () => {
      slot.verify_current_hold() == Ok(()) &&
      saved_output_bundle_current(owner.bundles, delegated, target)
    }
    if !current() {
      stop("retained cleanup current custody unconfirmed")
    }
    let root = match @filesystem.open_root(root_path) {
      Ok(value) => value
      Err(_) => stop("retained cleanup Root unavailable")
    }
    let journal = match
      @transfer_journal.open_journal(
        environment.sqlite_library,
        transfer_path,
        environment.max_record_bytes,
        65536,
        1048576,
        environment.max_bytes,
      ) {
      Ok(value) => value
      Err(_) => stop("retained cleanup Transfer journal unavailable")
    }
    receiver.val = Some(journal)
    let limits : @output.NativeRemoteStandardTransferBindingLimits = {
      max_binding_bytes: 1048576,
      max_chunks: 65536,
      max_manifest_bytes: 1048576,
      max_referenced_bytes: environment.max_bytes,
    }
    if cancelled_materials is Some((consumer, transfer, recorded)) {
      let cleanup = @resident_host.prepare_resident_saved_cancelled_receiver_cleanup(
        owner.journal,
        run_admission(matches),
        recorded,
        site,
        delegated,
        consumer,
        @remote.remote_poll_retained_transfer_intent(transfer),
        @remote.remote_poll_retained_transfer_plan(transfer),
        journal,
        root,
        limits,
        current,
      )
      match cleanup {
        Ok(retry) =>
          match retry() {
            Ok(_) => None
            Err(_) => Some("cancelled receiver cleanup retry pending")
          }
        Err(NotCurrent) =>
          Some("cancelled receiver current custody unconfirmed")
        Err(Host(_)) => Some("cancelled receiver original Run unconfirmed")
        Err(Binding(_)) => Some("cancelled receiver original binding refused")
        Err(Transfer(_)) => Some("cancelled receiver reclamation pending")
        Err(Journal(_)) => Some("cancelled receiver durable custody pending")
      }
    } else if source_output {
      match
        @resident_host.reclaim_stopped_resident_source_output(
          owner.journal,
          run_admission(matches),
          site,
          delegated,
          producer_attempt,
          consumer_attempt,
          journal,
          root,
          root_path,
          limits,
          current,
          recorded=match optional(child, "publication-custody-root") {
            Some(path) => Some(load_recorded_publication(path))
            None => None
          },
        ) {
        Ok(_) => None
        Err(NotCurrent) => Some("source cleanup current custody unconfirmed")
        Err(ConsumerReleasePending) =>
          Some("source cleanup consumer release pending")
        Err(Host(_)) => Some("source cleanup original Run unconfirmed")
        Err(Binding(_)) => Some("source cleanup sole consumer unconfirmed")
        Err(Receiver(_)) => Some("source cleanup receiver reclamation pending")
        Err(File(_)) => Some("source cleanup file reclamation pending")
        Err(CustodyPending) => Some("source cleanup file custody unconfirmed")
      }
    } else {
      match
        @resident_host.reclaim_stopped_resident_retained_input(
          owner.journal,
          site,
          delegated,
          producer_attempt,
          consumer_attempt,
          journal,
          root,
          limits,
          current,
        ) {
        Ok(_) => None
        Err(NotCurrent) => Some("retained cleanup current custody unconfirmed")
        Err(Host(_)) => Some("retained cleanup original completion unconfirmed")
        Err(Binding(_)) => Some("retained cleanup original binding refused")
        Err(Transfer(_)) =>
          Some("retained cleanup receiver reclamation pending")
        Err(Journal(_)) => Some("retained cleanup durable borrow pending")
      }
    }
  } catch {
    CommandStop(issue) => Some(issue)
  }
  // Attempt every close without replacing the primary failure. All pending
  // physical cleanup responsibilities remain in their existing journals.
  let mut closed = true
  if receiver.val is Some(journal) && !journal.close() {
    closed = false
  }
  if !owner.journal.close() {
    closed = false
  }
  if !(owner.bundles.close() is Ok(true)) {
    closed = false
  }
  if !slot.close() {
    closed = false
  }
  if !closed {
    report("retained-input-recovery-cleanup-pending", [("step", "owners")])
  }
  if failure is Some(issue) {
    stop(issue)
  }
  if !closed {
    stop("retained cleanup owner close unconfirmed")
  }
  report(
    if cancelled_receiver {
      "cancelled-receiver-recovery-reclaimed"
    } else if source_output {
      "source-output-recovery-reclaimed"
    } else {
      "retained-input-recovery-reclaimed"
    },
    [
      ("producer_request_cid", expected_producer),
      ("consumer_request_cid", expected_consumer),
    ],
  )
}
