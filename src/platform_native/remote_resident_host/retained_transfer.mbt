///|
pub(all) enum ResidentRetainedTransferIssue {
  Input(@host.ClientRetainedTaskInputIssue)
  Output(@runtime.NativeRemoteRuntimeIssue)
  Destination(@transfer_client.NativeRemoteTransferClientIssue)
  Journal(@transfer_journal.NativeRemoteTransferJournalIssue)
  ForeignProducer
  UnsupportedRoute
  CapacityUnavailable
  CleanupPending
}

///|
/// A physical handoff caller around the existing Runtime and Direct Transfer
/// owners. Durable progress and receiver custody remain in the Transfer journal.
/// A failed step keeps the reader, pending exact chunk and Site reservation.
pub struct ResidentRetainedTransfer {
  runtime : @runtime.NativeRemoteRuntime
  dispatch : @remote.DispatchRequest
  producer : @host.ClientRetainedInputProducer
  request : @transfer.RemoteTransferRequest
  current : @host.ClientRetainedInputCurrent
  site : @site.ExecutionSite
  mut journal : @transfer_journal.Journal
  root : @filesystem.Root
  max_chunk_bytes : Int
  max_destination_bytes : Int64
  max_destination_objects : Int64
  mut holding : @site.SiteHolding?
  mut reader : @runtime.NativeRemoteOutputManifestReader?
  mut pending : @runtime.NativeRemoteOutputManifestChunk?
  mut source_finished : Bool
  mut receipt_cid : String?
  mut cleanup_material : @transfer_client.NativeRemoteDestinationMaterialUse?
  mut cleanup_started : Bool
  mut reclaimed : Bool
}

///|
/// Construction performs no payload read, payload write or reservation. The caller
/// retains this exact owner on failure and serializes its methods; it cannot
/// create a second active owner for the same receiver responsibility.
pub fn prepare_resident_retained_transfer(
  runtime : @runtime.NativeRemoteRuntime,
  dispatch : @remote.DispatchRequest,
  producer : @host.ClientRetainedInputProducer,
  request : @transfer.RemoteTransferRequest,
  current : @host.ClientRetainedInputCurrent,
  site : @site.ExecutionSite,
  journal : @transfer_journal.Journal,
  root : @filesystem.Root,
  max_chunk_bytes : Int,
  max_destination_bytes : Int64,
  max_destination_objects : Int64,
) -> Result[ResidentRetainedTransfer, ResidentRetainedTransferIssue] {
  if @transfer.request_route(request) != @transfer.DirectStream ||
    max_chunk_bytes <= 0 ||
    max_destination_bytes < 0L ||
    max_destination_objects < 1L {
    return Err(UnsupportedRoute)
  }
  if @remote.dispatch_request_identity(dispatch) !=
    @remote.dispatch_request_identity(
      @host.client_retained_input_producer_dispatch(producer),
    ) {
    return Err(ForeignProducer)
  }
  let completion = match runtime.observed_completion(dispatch) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  if completion.evidence_cid !=
    @remote.remote_execution_evidence_cid(
      @host.client_retained_input_producer_evidence(producer),
    ) {
    return Err(ForeignProducer)
  }
  match
    @host.validate_client_retained_input_transfer_current(
      producer, request, current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  let scope = @remote.dispatch_request_execution_scope(dispatch)
  if scope[0] != @site.site_key(site) ||
    scope[1] != @site.site_generation(site).to_string() ||
    !@site.site_binding_current(site, @site.site_generation(site), scope[2]) {
    return Err(ForeignProducer)
  }
  Ok({
    runtime,
    dispatch,
    producer,
    request,
    current,
    site,
    journal,
    root,
    max_chunk_bytes,
    max_destination_bytes,
    max_destination_objects,
    holding: None,
    reader: None,
    pending: None,
    source_finished: false,
    receipt_cid: None,
    cleanup_material: None,
    cleanup_started: false,
    reclaimed: false,
  })
}

///|
/// Advance at most one exact physical chunk. False means more handoff work,
/// true means the existing receiver Owner has durably committed its receipt.
/// Neither result starts a consumer or releases the producer holding.
pub fn ResidentRetainedTransfer::advance(
  self : ResidentRetainedTransfer,
) -> Result[Bool, ResidentRetainedTransferIssue] {
  if self.reclaimed || self.cleanup_started {
    return Err(CleanupPending)
  }
  match
    @host.validate_client_retained_input_transfer_current(
      self.producer,
      self.request,
      self.current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  if self.holding is None {
    self.holding = @site.retain_site_holding(
      self.site,
      @transfer.request_manifest(self.request).referenced_bytes,
    )
    if self.holding is None {
      return Err(CapacityUnavailable)
    }
  }
  let record = match
    @transfer_client.admit_durable_direct_destination(
      self.journal,
      self.request,
      self.max_destination_bytes,
      self.max_destination_objects,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Destination(issue))
  }
  // Current authorization and expiry can change while journal I/O runs.
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if @transfer.record_is_destination_committed(record) {
    // Reconstructed committed custody needs no source read or new Transfer.
    match self.remember_receipt() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    self.source_finished = true
    return self.require_current().map(_ => true)
  }
  if self.reader is None {
    self.reader = Some(
      match
        self.runtime.open_output_manifest_reader(
          self.dispatch,
          @transfer.request_projection(self.request)[6],
          self.max_chunk_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Output(issue))
      },
    )
  }
  let reader = self.reader.unwrap()
  let physical = match reader.physical_manifest() {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  if physical.manifest_cid !=
    @transfer.request_manifest(self.request).manifest_cid {
    return Err(ForeignProducer)
  }
  if !self.source_finished {
    if self.pending is None {
      match self.require_current() {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      self.pending = match reader.next() {
        Ok(value) => value
        Err(issue) => return Err(Output(issue))
      }
    }
    if self.pending is Some(chunk) {
      match self.require_current() {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      match
        @transfer_client.write_durable_direct_destination_chunk(
          self.journal,
          self.root,
          self.request,
          chunk.index,
          chunk.bytes,
        ) {
        Ok(_) => self.pending = None
        Err(issue) => return Err(Destination(issue))
      }
      match
        @host.validate_client_retained_input_transfer_current(
          self.producer,
          self.request,
          self.current,
        ) {
        Ok(_) => return Ok(false)
        Err(issue) => return Err(Input(issue))
      }
    }
    match reader.finish() {
      Ok(_) => self.source_finished = true
      Err(issue) => return Err(Output(issue))
    }
  }
  match
    @host.validate_client_retained_input_transfer_current(
      self.producer,
      self.request,
      self.current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  match
    @transfer_client.commit_durable_direct_destination(
      self.journal,
      self.root,
      self.request,
    ) {
    Ok(record) => {
      if !@transfer.record_is_destination_committed(record) {
        return Ok(false)
      }
      match self.remember_receipt() {
        Ok(_) => self.require_current().map(_ => true)
        Err(issue) => Err(issue)
      }
    }
    Err(issue) => Err(Destination(issue))
  }
}

///|
fn ResidentRetainedTransfer::require_current(
  self : ResidentRetainedTransfer,
) -> Result[Unit, ResidentRetainedTransferIssue] {
  @host.validate_client_retained_input_transfer_current(
    self.producer,
    self.request,
    self.current,
  ).map_err(issue => Input(issue))
}

///|
fn ResidentRetainedTransfer::remember_receipt(
  self : ResidentRetainedTransfer,
) -> Result[Unit, ResidentRetainedTransferIssue] {
  let receipt = match self.journal.inspect_destination_receipt(self.request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CleanupPending)
    Err(issue) => return Err(Journal(issue))
  }
  let cid = @transfer.destination_receipt_cid(receipt)
  if self.receipt_cid is Some(saved) && saved != cid {
    return Err(ForeignProducer)
  }
  self.receipt_cid = Some(cid)
  Ok(())
}

///|
/// Reopen the committed receiver journal while this holder still owns the
/// original producer and Site reservation. The exact saved receipt must match;
/// no second reservation, reader, Source acquisition or Transfer is created.
pub fn ResidentRetainedTransfer::reopen_completed_destination(
  self : ResidentRetainedTransfer,
  journal : @transfer_journal.Journal,
) -> Result[Unit, ResidentRetainedTransferIssue] {
  guard !self.reclaimed &&
    self.source_finished &&
    self.receipt_cid is Some(saved) else {
    return Err(CleanupPending)
  }
  let record = match journal.require(self.request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let receipt = match journal.inspect_destination_receipt(self.request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CleanupPending)
    Err(issue) => return Err(Journal(issue))
  }
  if !@transfer.record_is_destination_committed(record) ||
    @transfer.destination_receipt_cid(receipt) != saved {
    return Err(ForeignProducer)
  }
  if !self.cleanup_started {
    match
      @host.validate_client_retained_input_transfer_current(
        self.producer,
        self.request,
        self.current,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Input(issue))
    }
  }
  self.journal = journal
  Ok(())
}

///|
/// Stop this handoff and reclaim only its receiver. No current execution
/// authorization is needed to discharge an already acquired cleanup duty.
/// Borrow return alone does not confirm receiver cleanup or refund capacity.
pub fn ResidentRetainedTransfer::reclaim(
  self : ResidentRetainedTransfer,
) -> Result[Bool, ResidentRetainedTransferIssue] {
  if self.reclaimed {
    return Ok(false)
  }
  self.cleanup_started = true
  if self.reader is Some(reader) {
    match reader.close() {
      Ok(_) => self.reader = None
      Err(issue) => return Err(Output(issue))
    }
  }
  self.pending = None
  if self.holding is Some(holding) {
    let receipt = match self.journal.inspect_destination_receipt(self.request) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    if receipt is Some(receipt) {
      if self.cleanup_material is None {
        self.cleanup_material = Some(
          match
            @transfer_client.recover_durable_direct_destination_cleanup(
              self.journal,
              self.root,
              self.request,
              @transfer.destination_receipt_cid(receipt),
            ) {
            Ok(value) => value
            Err(issue) => return Err(Destination(issue))
          },
        )
      }
      match
        @transfer_client.reclaim_durable_destination_material(
          self.cleanup_material.unwrap(),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Destination(issue))
      }
    } else {
      match
        @transfer_client.cancel_durable_direct_destination(
          self.journal,
          self.root,
          self.request,
        ) {
        Ok(record) if @transfer.direct_transfer_cleanup_confirmed(record) => ()
        Ok(_) => return Err(CleanupPending)
        Err(
          @transfer_client.Durable(@transfer_journal.Physical(@sqlite.NotFound))
        ) =>
          // The synchronous serialized admission has returned. Its exact
          // record is durably absent; no receiver allocation can predate it.
          ()
        Err(issue) => return Err(Destination(issue))
      }
    }
    ignore(@site.release_site_holding(holding))
    self.holding = None
  }
  self.reclaimed = true
  Ok(true)
}
