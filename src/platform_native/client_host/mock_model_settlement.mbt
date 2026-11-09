///|
// One private declaration supplies both the pre-call construction envelope
// and the actual key-preimage codec, using the existing record-codec limits.
let native_mock_model_evidence_key_codec_limits : (Int, Int, Int) = (
  8192, 64, 4,
)

///|
// One closed scalar in the existing settlement. Prelude is sticky (no retry)
// but has not entered a Store constructor; its captured Read owns any failure.
priv enum NativeMockModelStorePhase {
  ModelStoreUnstarted
  ModelStorePrelude
  ModelStoreEntered
} derive(Eq)

///|
// A retained child of the existing Native Model caller. Store children own
// their own physical persistence; this record never creates an ACK or a send.
priv struct NativeMockModelSettlement {
  original : @model.ModelCallSettlement
  slot : Int
  count : Int
  scope_cid : String
  slot_cid : String
  attempt_cid : String
  limits : @model.ModelCaptureExportLimits
  leaves : Array[@publication.RunEvidenceValue]
  call : @publication.RunEvidenceValue
  children : Array[@publication_store.ModelEvidenceCustody]
  mut store : @publication_store.Store?
  mut exporter : @model.ModelCaptureExport?
  mut wire : String
  mut complete : Bool
  mut store_phase : NativeMockModelStorePhase
  mut stored : Int
  mut store_complete : Bool
  mut journal_attempted : Bool
  mut journal_recorded : Bool
}

///|
/// Retain this original settlement before opening its canonical exporter.
/// The caller supplies the already selected finite export limits and funds
/// all evidence/export/Store/failed-child overlap on the SAME parent before
/// entering. This is not a normal numerical profile or another Model owner.
pub fn NativeClientMockModelWork::prepare_settlement_export(
  self : NativeClientMockModelWork,
  limits : @model.ModelCaptureExportLimits,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    guard !self.closing &&
      !self.closed &&
      !self.advancing &&
      self.settlement is None &&
      self.active is Some(active) &&
      self.prepared is Some(prepared) &&
      self.scope is Some(scope) &&
      self.entry_recorded &&
      @infer.call_settlement(active) is Some(original) &&
      @model.model_call_settlement_slot(original) is Some(slot) &&
      @model.prepared_model_call_count(prepared) is Some(count) &&
      @publication.model_invocation_scope_slot(scope, slot)
      is Some((slot_cid, _, _)) &&
      @model.prepared_model_call_at(prepared, slot) is Some(call) &&
      @publication.run_evidence_value_identity(call) == slot_cid else {
      return Err(ForeignOriginal)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    let proof = mock_model_require(
      @infer.attempt_evidence(active, slot).map_err(issue => {
        NativeClientMockModelIssue::Capture(issue)
      }),
    )
    let attempt = @model.model_attempt_identity(proof)
    let accounting = @model.model_attempt_accounting(proof)
    let outcome = @model.model_attempt_outcome(proof)
    let authority = @model.model_attempt_authority(proof)
    mock_model_require(
      @publication.check_model_invocation_attempt(
        scope, slot, attempt, authority, 1L,
      ).map_err(issue => NativeClientMockModelIssue::Evidence(issue)),
    )
    let capture = mock_model_require(
      @infer.issued_slot_capture(active, slot).map_err(issue => {
        NativeClientMockModelIssue::Capture(issue)
      }),
    )
    let binding = mock_model_require(
      @publication.bind_model_slot_capture(call, capture).map_err(issue => {
        NativeClientMockModelIssue::Evidence(issue)
      }),
    )
    let _ = mock_model_require(
      @publication.bind_model_slot_attempt_evidence(
        binding,
        attempt,
        accounting,
        outcome,
        authority,
        self.compiled.admission,
        self.definition,
      ).map_err(issue => NativeClientMockModelIssue::Evidence(issue)),
    )
    let leaves = [attempt, accounting, outcome, authority, capture]
    guard @publication.bound_model_slot_capture_outcome(binding) is Some(result) else {
      return Err(ForeignOriginal)
    }
    if result == "ok" {
      guard @infer.invocation_evidence(active, slot) is Some(observation) else {
        return Err(ForeignOriginal)
      }
      mock_model_require(
        @publication.verify_model_slot_success_observation(binding, observation).map_err(issue => {
            NativeClientMockModelIssue::Evidence(issue)
          },
        ),
      )
      leaves.push(observation)
    } else {
      mock_model_require(
        @publication.verify_model_slot_no_response_failure(binding, result).map_err(issue => {
            NativeClientMockModelIssue::Evidence(issue)
          },
        ),
      )
    }
    let attachment = mock_model_require(
      @infer.issued_attachment_admission(active, slot).map_err(issue => {
        NativeClientMockModelIssue::Capture(issue)
      }),
    )
    if attachment is Some(value) {
      leaves.push(value)
    }
    let saved : NativeMockModelSettlement = {
      original,
      slot,
      count,
      scope_cid: @publication.model_invocation_scope_cid(scope),
      slot_cid,
      attempt_cid: @publication.run_evidence_value_identity(attempt),
      limits,
      leaves,
      call,
      children: [],
      store: None,
      exporter: None,
      wire: "",
      complete: false,
      store_phase: ModelStoreUnstarted,
      stored: 0,
      store_complete: false,
      journal_attempted: false,
      journal_recorded: false,
    }
    self.settlement = Some(saved)
    let exporter = mock_model_require(
      @model.start_model_call_settlement_export(original, limits).map_err(issue => {
        NativeClientMockModelIssue::Capture(issue)
      }),
    )
    saved.exporter = Some(exporter)
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
/// One bounded batch in the same Model execution frame. Provisional chunks
/// cannot enter Store custody until the original exporter accepts its CID.
pub fn NativeClientMockModelWork::advance_settlement_export(
  self : NativeClientMockModelWork,
) -> Result[Bool, NativeClientMockModelIssue] {
  try {
    guard !self.closing &&
      !self.closed &&
      !self.advancing &&
      self.settlement is Some(saved) &&
      @model.model_call_settlement_slot(saved.original) == Some(saved.slot) &&
      saved.exporter is Some(exporter) else {
      return Err(ForeignOriginal)
    }
    if saved.complete {
      return Ok(true)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    let (complete, chunk, _) = mock_model_require(
      @model.advance_model_capture_export(exporter, 31).map_err(issue => {
        NativeClientMockModelIssue::Capture(issue)
      }),
    )
    if chunk.length() > saved.limits.max_bytes - saved.wire.length() {
      return Err(Encoding)
    }
    saved.wire += chunk
    if complete {
      guard @model.model_capture_export_identity(exporter) is Some(cid) else {
        return Err(ForeignOriginal)
      }
      let bundle = mock_model_require(
        @publication.admit_run_evidence_value(
          "model_capture_bundle",
          saved.wire,
          saved.limits.max_bytes,
          saved.limits.max_nodes,
          saved.limits.max_depth,
        ).map_err(issue => NativeClientMockModelIssue::Evidence(issue)),
      )
      if @publication.run_evidence_value_identity(bundle) != cid ||
        @publication.run_evidence_value_json(bundle) != saved.wire {
        return Err(ForeignOriginal)
      }
      saved.leaves.push(bundle)
      saved.complete = true
    }
    Ok(complete)
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
/// Outer Read boundary only, after the original Model batch returned. Retain
/// EACH original Store child before its first fallible persistence. A failure
/// is sticky on this same record; it cannot resend, replace the child, infer
/// absence or issue Core's settlement acknowledgement.
pub fn NativeClientMockModelWork::persist_settlement_evidence_in_original_read(
  self : NativeClientMockModelWork,
  store : @publication_store.Store,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    guard !self.closing &&
      !self.closed &&
      !self.advancing &&
      self.settlement is Some(saved) &&
      saved.complete &&
      saved.store_phase == ModelStoreUnstarted else {
      return Err(ForeignOriginal)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    saved.store_phase = ModelStorePrelude
    // The existing original-record codec has an 8192-byte output envelope.
    // Admit that constructor and the independent 32-byte HMAC output on this
    // SAME consuming Read before codec, epoch read or Crypto. This funds no
    // Store/AEAD/output frame; that separate aggregate is funded below.
    let (key_bytes, key_nodes, key_depth) = native_mock_model_evidence_key_codec_limits
    mock_model_require(
      self.capture
      .prepare_model_entry_construction(
        Some(key_bytes),
        nodes=key_nodes,
        depth=key_depth,
        additional=Some((32, 1, 1)),
      )
      .map_err(issue => NativeClientMockModelIssue::Original(issue)),
    )
    let key = mock_model_require(
      self.capture
      .with_current_adoption_material_in_original_read((
        host,
        _material,
        operations,
      ) => {
        let record = match
          host.journal.retained(self.request, reads=Some(operations.reads)) {
          Ok(Some(value)) => value
          Ok(None) => return Err(Journal(CustodyLost))
          Err(issue) => return Err(Journal(issue))
        }
        let (authority, device, inode) = match store.custody_location() {
          Ok(value) => value
          Err(issue) => return Err(Journal(PublicationObservation(issue)))
        }
        let binding = match
          installed_publication_binding(
            self.namespace_id,
            authority,
            device,
            inode,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Journal(issue))
        }
        if !record.dispatch_reserved ||
          !record.physical_start_claimed ||
          record.effect_material_originals is None ||
          record.publication_binding != Some(binding) ||
          @publication.publication_contract_identity(record.definition) !=
          @publication.publication_contract_identity(self.definition) {
          return Err(Journal(ForeignRun))
        }
        native_mock_model_evidence_key(host, binding, operations.reads)
      })
      .map_err(issue => NativeClientMockModelIssue::Original(issue)),
    )
    // Only the already retained original Library encrypts. No caller key,
    // key generation, library path or replacement installation is accepted.
    let crypto = self.capture.crypto
    mock_model_require(self.prepare_settlement_store_construction(store, saved))
    // A failed pure quote/key prelude has not entered this Store. Its captured
    // Read still owns any original read/return failure. Latch Store custody
    // only immediately before its first real constructor, never infer ACK.
    saved.store_phase = ModelStoreEntered
    saved.store = Some(store)
    for original in saved.leaves {
      let child = mock_model_require(
        store
        .prepare_model_evidence_custody(
          self.definition,
          saved.scope_cid,
          saved.slot_cid,
          saved.attempt_cid,
          original,
          crypto,
          key,
        )
        .map_err(issue => NativeClientMockModelIssue::Store(issue)),
      )
      saved.children.push(child)
      mock_model_require(
        child
        .persist()
        .map_err(issue => NativeClientMockModelIssue::Store(issue)),
      )
      let confirmed = mock_model_require(
        child
        .confirm()
        .map_err(issue => NativeClientMockModelIssue::Store(issue)),
      )
      if @publication.run_evidence_value_identity(confirmed) !=
        @publication.run_evidence_value_identity(original) {
        return Err(ForeignOriginal)
      }
      // Retain the known durable observation before returning to Read or any
      // next callback. This counter is not a physical or Model settlement ACK.
      saved.stored += 1
      // The last original confirmation remains known even if the following
      // current fence refuses. Journal COMMIT and Model ACK stay independent.
      saved.store_complete = saved.stored == saved.leaves.length()
      mock_model_require(
        self.capture
        .check_current_in_original_read()
        .map_err(issue => NativeClientMockModelIssue::Original(issue)),
      )
    }
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
// All children retained by this SAME settlement coexist with the next seal,
// persist/readback and failed return. Quote them before the first Store call;
// sequential scratch takes a maximum, retained ciphertext/keys accumulate.
fn NativeClientMockModelWork::prepare_settlement_store_construction(
  self : NativeClientMockModelWork,
  store : @publication_store.Store,
  saved : NativeMockModelSettlement,
) -> Result[Unit, NativeClientMockModelIssue] {
  if !saved.children.is_empty() {
    return Err(ForeignOriginal)
  }
  self.capture.prepare_private_store_children_construction(
    store,
    saved.leaves.length(),
    index => @publication.run_evidence_value_json(saved.leaves[index]),
  )
}

///|
fn NativeLocalJournalCapture::prepare_private_store_children_construction(
  self : NativeLocalJournalCapture,
  store : @publication_store.Store,
  count : Int,
  wire_at : (Int) -> String,
  additional_retained? : Int64 = 0L,
) -> Result[Unit, NativeClientMockModelIssue] {
  self.prepare_private_store_layouts_construction(
    count,
    index => store.private_evidence_custody_construction(wire_at(index)),
    additional_retained~,
  )
}

///|
// The same Native constructor fold also consumes scalar observed ciphertext
// geometry. No plaintext placeholder or synthetic wire is allocated to quote a
// cold read. Existing Store limits remain admission, not physical backing.
fn NativeLocalJournalCapture::prepare_private_store_layouts_construction(
  self : NativeLocalJournalCapture,
  count : Int,
  layout_at : (Int) -> @publication_store.PrivateEvidenceCustodyConstruction?,
  additional_retained? : Int64 = 0L,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard self.original_resources is Some(original) &&
    !original.interrupted &&
    original.active_phase is Some(@arena.HostRead) &&
    count >= 0 &&
    additional_retained >= 0L else {
    return Err(ForeignOriginal)
  }
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit || pointer <= 0L {
    return Err(Encoding)
  }
  let n = count.to_int64()
  let vector = @execution.preparation_array_representation(1L, n, true).unwrap()
  // The original derived key remains beside all per-child key copies.
  let mut retained = @execution.preparation_representation_cost(vector).unwrap() +
    header +
    33L +
    additional_retained
  let mut workspace = 0L
  let mut contiguous = array_header + (12L + 3L * n) * pointer
  for index in 0..<count {
    guard layout_at(index) is Some(layout) &&
      @execution.preparation_representation_cost(layout.retained) is Some(r) &&
      @execution.preparation_representation_cost(layout.workspace) is Some(e) &&
      @execution.checked_preparation_add_product(retained, r, 1L) is Some(next) else {
      return Err(Encoding)
    }
    retained = next
    workspace = Int64::max(workspace, e)
    // Pinned Native StringBuilder doubling and Map/Array bucket growth are
    // independent contiguous constructors, not the logical R/E sum. The
    // largest malformed envelope collection has at most one entry per byte.
    let bytes = layout.envelope_bytes.to_int64()
    let mut capacity = 8L
    while capacity < bytes * 2L {
      capacity *= 2L
    }
    contiguous = Int64::max(
      contiguous,
      Int64::max(
        header + (capacity + 1L) * unit,
        array_header + (capacity + 1L) * pointer,
      ),
    )
  }
  guard @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) else {
    return Err(Encoding)
  }
  original.host
  .prepare_domain_original_read_construction(
    original.read,
    retained,
    execution,
    contiguous,
  )
  .map_err(issue => Original(OriginalResources(@arena.Read(issue))))
}

///|
// Private encryption material from this SAME adopted Host and actual Store
// binding. The existing epoch secret never leaves its original custody reader;
// the domain-separated output supplies no signing, Model or execution grant.
// The original read caller funds the existing codec and Crypto output first.
fn native_mock_model_evidence_key(
  host : NativeLocalHostConnection,
  binding : String,
  reads : NativeClientJournalReadAccess,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  native_local_private_evidence_key(
    host, binding, reads, "actql-native-local-model-evidence-key/0.1",
  )
}

///|
fn native_local_private_evidence_key(
  host : NativeLocalHostConnection,
  binding : String,
  reads : NativeClientJournalReadAccess,
  domain : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let preimage = try {
    let (bytes, nodes, depth) = native_mock_model_evidence_key_codec_limits
    let writer = @encode.writer(bytes, nodes, depth)
    @encode.begin_object(writer)
    @encode.key(writer, "adoption_cid")
    @encode.string_value(writer, host.adoption_cid)
    @encode.key(writer, "domain")
    @encode.string_value(writer, domain)
    @encode.key(writer, "store_binding")
    @encode.string_value(writer, binding)
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return Err(Encoding)
  }
  let (original, _, _) = match
    read_epoch_custody(host.database, reads=Some(reads)) {
    Err(issue) => return Err(Epoch(issue))
    Ok(value) => value
  }
  host.epoch.crypto
  .hmac_sha256(original, preimage)
  .map_err(issue => Crypto(issue))
}
