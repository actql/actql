///|
pub(all) enum NativeClientModelRawIssue {
  ForeignOriginal
  Original(NativeLocalAdoptionIssue)
  Capture(@model.ModelRawCaptureSaveIssue)
  Store(@publication_store.NativePublicationStoreIssue)
}

///|
priv enum NativeModelRawCapturePhase {
  Prepared
  Checking
  StoreAttempted
  StoreConfirmed
  ReceiptReady
} derive(Eq)

///|
// A single Call's captured Store child. A failure leaves this same object in
// the Native Model caller's possession. Recovery must keep its original
// encrypted holding even if current authority is lost after the write.
struct NativeClientModelRawCapture {
  capture : NativeLocalJournalCapture
  request : @host.ClientRequestIdentity
  definition : @publication.PublicationContract
  binding : String
  view : @model.ModelRawCaptureSave
  child : @publication_store.ModelEvidenceCustody
  mut phase : NativeModelRawCapturePhase
}

///|
fn native_model_raw_run_current(
  host : NativeLocalHostConnection,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  binding : String,
  reads : NativeClientJournalReadAccess,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match host.journal.retained(request, reads=Some(reads)) {
    Ok(Some(run)) if run.dispatch_reserved &&
      run.physical_start_claimed &&
      !run.cancellation_requested &&
      run.publication_binding == Some(binding) &&
      @publication.publication_contract_identity(run.definition) ==
      @publication.publication_contract_identity(definition) => Ok(())
    Ok(_) => Err(Journal(ForeignRun))
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Prepare the original Store child on the consuming Read. The checked Call,
/// durable Run and physical Store all have to agree. Key material comes from
/// the existing adopted epoch and Store binding. The caller must retain this
/// result before attempting persistence.
pub fn NativeLocalJournalCapture::prepare_model_raw_capture_in_original_read(
  self : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  namespace_id : String,
  store : @publication_store.Store,
  view : @model.ModelRawCaptureSave,
  bytes : Bytes,
) -> Result[NativeClientModelRawCapture, NativeClientModelRawIssue] {
  guard @model.model_raw_capture_save_matches_run(view, compiled, definition) else {
    return Err(ForeignOriginal)
  }
  match self.check_original_read_lifetime() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  match @model.model_raw_capture_save_current(view) {
    Ok(_) => ()
    Err(issue) => return Err(Capture(issue))
  }
  let (key_bytes, key_nodes, key_depth) = native_mock_model_evidence_key_codec_limits
  match
    self.prepare_model_entry_construction(
      Some(key_bytes),
      nodes=key_nodes,
      depth=key_depth,
      additional=Some((32, 1, 1)),
      additional_controls=Some({
        record_headers: 2L,
        reference_slots: 8L,
        scalar_words: 1L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  let (authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  let original = @model.model_raw_capture_save_binding(view)
  if !@publication.model_raw_response_matches_store(original, authority) {
    return Err(ForeignOriginal)
  }
  let binding = match
    installed_publication_binding(namespace_id, authority, device, inode) {
    Ok(value) => value
    Err(issue) => return Err(Original(Journal(issue)))
  }
  let key = match
    self.with_current_adoption_material_in_original_read((host, _, operations) => {
      match
        native_model_raw_run_current(
          host,
          request,
          definition,
          binding,
          operations.reads,
        ) {
        Ok(_) => native_mock_model_evidence_key(host, binding, operations.reads)
        Err(issue) => Err(issue)
      }
    }) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  match
    self.prepare_private_store_layouts_construction(1, _ => {
      store.model_raw_evidence_custody_construction(original)
    }) {
    Ok(_) => ()
    Err(NativeClientMockModelIssue::Original(issue)) =>
      return Err(Original(issue))
    Err(_) => return Err(Original(ConfigurationLimit))
  }
  match @model.model_raw_capture_save_current(view) {
    Ok(_) => ()
    Err(issue) => return Err(Capture(issue))
  }
  store
  .prepare_model_raw_evidence_custody(original, bytes, self.crypto, key)
  .map(child => {
    capture: self,
    request,
    definition,
    binding,
    view,
    child,
    phase: Prepared,
  })
  .map_err(issue => Store(issue))
}

///|
fn NativeClientModelRawCapture::require_current_in_original_read(
  self : NativeClientModelRawCapture,
) -> Result[Unit, NativeClientModelRawIssue] {
  match
    self.capture.with_current_adoption_material_in_original_read((
      host,
      _,
      operations,
    ) => {
      native_model_raw_run_current(
        host,
        self.request,
        self.definition,
        self.binding,
        operations.reads,
      )
    }) {
    Ok(_) =>
      @model.model_raw_capture_save_current(self.view).map_err(issue => {
        Capture(issue)
      })
    Err(issue) => Err(Original(issue))
  }
}

///|
/// Only one normal save attempt is admitted. Record authenticated readback
/// before rechecking current authority, so a late refusal cannot erase the
/// known durable holding or create permission to send again.
pub fn NativeClientModelRawCapture::persist_in_original_read(
  self : NativeClientModelRawCapture,
) -> Result[Unit, NativeClientModelRawIssue] {
  if self.phase != Prepared {
    return Err(ForeignOriginal)
  }
  // Current checks may invoke trusted installed callbacks. Refuse reentry
  // before the first such callback, while distinguishing a pre-Store refusal.
  self.phase = Checking
  match self.require_current_in_original_read() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.phase = StoreAttempted
  match self.child.persist() {
    Ok(_) => ()
    Err(issue) => return Err(Store(issue))
  }
  let confirmed = match self.child.confirm() {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  guard physical_equal(
    confirmed,
    @publication.model_raw_response_value(
      @model.model_raw_capture_save_binding(self.view),
    ),
  ) else {
    return Err(ForeignOriginal)
  }
  self.phase = StoreConfirmed
  self.require_current_in_original_read().map(_ => self.phase = ReceiptReady)
}

///|
/// Call in the original Model frame after Store confirmation. The Core
/// issuer still rechecks its exact live Call and capture authority.
pub fn NativeClientModelRawCapture::acknowledge_saved(
  self : NativeClientModelRawCapture,
) -> Result[@model.ModelSavedRawReceipt, NativeClientModelRawIssue] {
  if self.phase != ReceiptReady {
    return Err(ForeignOriginal)
  }
  @model.acknowledge_saved_model_raw_capture(self.view).map_err(issue => {
    Capture(issue)
  })
}
