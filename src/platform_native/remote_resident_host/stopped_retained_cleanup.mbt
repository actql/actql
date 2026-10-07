///|
pub(all) enum ResidentStoppedRetainedCleanupIssue {
  NotCurrent
  Host(ResidentHostIssue)
  Binding(@host.ClientRetainedTaskInputIssue)
  Transfer(@transfer_client.NativeRemoteTransferClientIssue)
  Journal(@transfer_journal.NativeRemoteTransferJournalIssue)
}

///|
/// The caller holds the real Site executor slot, covering both holder
/// descendants. Return only the exact completed consumer's durable borrow,
/// then reuse the existing receiver cleanup Owner. No Source, Compute,
/// payload reader, new borrow, reservation or terminal transition is created.
/// The same original responsibility remains retryable on every failure.
pub fn reclaim_stopped_resident_retained_input(
  journal : @journal.Journal,
  site : @site.ExecutionSite,
  delegation : @resident.ResidentSiteDelegation,
  producer_attempt : String,
  consumer_attempt : String,
  receiver_journal : @transfer_journal.Journal,
  receiver_root : @filesystem.Root,
  limits : @output.NativeRemoteStandardTransferBindingLimits,
  exclusive_current : () -> Bool,
) -> Result[Unit, ResidentStoppedRetainedCleanupIssue] {
  if !exclusive_current() {
    return Err(NotCurrent)
  }
  let dispatch = attempt => {
    let envelope = match journal.dispatch_envelope(attempt) {
      Ok(Some(value)) => value
      Ok(None) => return Err(EnvelopeMissing)
      Err(issue) => return Err(ResidentHostIssue::Journal(issue))
    }
    let value = match @remote.admit_remote_poll_dispatch_json(envelope) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    let request = @remote.remote_poll_dispatch_request(value)
    if @remote.dispatch_request_attempt_identity(request) != Ok(attempt) ||
      @resident.check_resident_dispatch_delegation(
        delegation,
        request,
        @site.site_generation(site),
      )
      is Err(_) {
      return Err(Protocol(@remote.DispatchIdentityMismatch))
    }
    let scope = @remote.dispatch_request_execution_scope(request)
    if scope[0] != @site.site_key(site) ||
      scope[1] != @site.site_generation(site).to_string() ||
      !@site.site_binding_current(site, @site.site_generation(site), scope[2]) {
      return Err(Refused(@resident.NotCurrent))
    }
    Ok(value)
  }
  let producer = match dispatch(producer_attempt) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let consumer = match dispatch(consumer_attempt) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let observed = request => {
    let value = match journal.observation(request) {
      Ok(value) => value
      Err(issue) => return Err(ResidentHostIssue::Journal(issue))
    }
    guard @journal.recovered_site_dispatch_evidence(value) is Some(evidence) &&
      @journal.recovered_site_dispatch_subject(value) is Some(subject) &&
      @journal.recovered_site_dispatch_measurement(value) is Some(measurement) else {
      return Err(Runtime(@runtime.CompletedRestorationPending))
    }
    Ok(
      (
        @journal.recovered_site_dispatch_record(value),
        evidence,
        subject,
        measurement,
      ),
    )
  }
  let p = match observed(@remote.remote_poll_dispatch_request(producer)) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let c = match observed(@remote.remote_poll_dispatch_request(consumer)) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let cleanup = match
    @host.prepare_client_retained_input_cleanup(
      @remote.remote_poll_dispatch_input_binding(consumer),
      p.0,
      p.1,
      p.2,
      p.3,
      c.0,
      c.1,
      c.2,
      c.3,
      limits.max_binding_bytes,
      limits.max_chunks,
      limits.max_manifest_bytes,
      limits.max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  let retry = match
    prepare_resident_retained_input_cleanup_retry(
      cleanup, receiver_journal, receiver_root, exclusive_current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  retry()
}

///|
/// Both stopped-command and retained restoration callers keep this exact
/// receiver responsibility. The historical address grants no new borrow.
fn prepare_resident_retained_input_cleanup_retry(
  cleanup : @host.ClientRetainedInputCleanup,
  receiver_journal : @transfer_journal.Journal,
  receiver_root : @filesystem.Root,
  exclusive_current : () -> Bool,
  allow_unborrowed? : Bool = false,
) -> Result[
  () -> Result[Unit, ResidentStoppedRetainedCleanupIssue],
  ResidentStoppedRetainedCleanupIssue,
] {
  let transfer = @host.client_retained_input_cleanup_transfer(cleanup)
  let receipt_cid = @host.client_retained_input_cleanup_receipt_cid(cleanup)
  // A missing consumer reader is admissible only after the original Transfer
  // and exact committed receipt are known. Missing Transfer custody is not
  // successful reclamation.
  match receiver_journal.require(transfer) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  let receipt = match receiver_journal.inspect_destination_receipt(transfer) {
    Ok(Some(value)) if @transfer.destination_receipt_cid(value) == receipt_cid =>
      value
    Ok(_) => return Err(Transfer(@transfer_client.ReconciliationRequired))
    Err(issue) => return Err(Journal(issue))
  }
  let returned = Ref(false)
  let reclaimed = Ref(false)
  let owner : Ref[@transfer_client.NativeRemoteDestinationMaterialUse?] = Ref(
    None,
  )
  Ok(() => {
    if !exclusive_current() {
      return Err(NotCurrent)
    }
    if reclaimed.val {
      return Ok(())
    }
    if !returned.val {
      match
        receiver_journal.release_destination_reader(
          transfer,
          receipt,
          @host.client_retained_input_cleanup_reader_id(cleanup),
        ) {
        Ok(_) => returned.val = true
        Err(@transfer_journal.Physical(@sqlite.NotFound)) if allow_unborrowed =>
          // Reader creation is atomic. Only this exact absent reader key
          // proves the accepted occurrence never acquired its borrow.
          returned.val = true
        Err(issue) => return Err(Journal(issue))
      }
    }
    if !exclusive_current() {
      return Err(NotCurrent)
    }
    if owner.val is None {
      match
        @transfer_client.recover_durable_direct_destination_cleanup(
          receiver_journal, receiver_root, transfer, receipt_cid,
        ) {
        Ok(value) => owner.val = Some(value)
        Err(issue) => return Err(Transfer(issue))
      }
    }
    if !exclusive_current() {
      return Err(NotCurrent)
    }
    match
      @transfer_client.reclaim_durable_destination_material(owner.val.unwrap()) {
      Ok(_) => {
        reclaimed.val = true
        Ok(())
      }
      Err(issue) => Err(Transfer(issue))
    }
  })
}
