///|
// One private declaration supplies both the pre-call construction envelope
// and the actual key-preimage codec, using the existing record-codec limits.
let native_mock_model_evidence_key_codec_limits : (Int, Int, Int) = (
  8192, 64, 4,
)

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
  mut store_attempted : Bool
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
      store_attempted: false,
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
      !saved.store_attempted else {
      return Err(ForeignOriginal)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    saved.store_attempted = true
    saved.store = Some(store)
    // The existing original-record codec has an 8192-byte output envelope.
    // Admit that constructor and the independent 32-byte HMAC output on this
    // SAME consuming Read before codec, epoch read or Crypto. This funds no
    // Store/AEAD/output frame; those remain the installing caller's overlap.
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
// Private encryption material from this SAME adopted Host and actual Store
// binding. The existing epoch secret never leaves its original custody reader;
// the domain-separated output supplies no signing, Model or execution grant.
// The original read caller funds the existing codec and Crypto output first.
fn native_mock_model_evidence_key(
  host : NativeLocalHostConnection,
  binding : String,
  reads : NativeClientJournalReadAccess,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let preimage = try {
    let (bytes, nodes, depth) = native_mock_model_evidence_key_codec_limits
    let writer = @encode.writer(bytes, nodes, depth)
    @encode.begin_object(writer)
    @encode.key(writer, "adoption_cid")
    @encode.string_value(writer, host.adoption_cid)
    @encode.key(writer, "domain")
    @encode.string_value(writer, "actql-native-local-model-evidence-key/0.1")
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
