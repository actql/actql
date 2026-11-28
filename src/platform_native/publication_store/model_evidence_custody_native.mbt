///|
// Per-call evidence uses the existing encrypted Store transaction, capacity,
// readback and tombstone owner. It does not issue a Model call, settlement ACK,
// ObservationSet, Result or current execution permission.
struct ModelEvidenceCustody {
  private_custody : PrivateEffectEvidenceCustody
  original : @publication.RunEvidenceValue
}

///|
let model_raw_descriptor_aad_role : String = "model_raw_response_descriptor"

///|
let model_raw_descriptor_max_wire : Int = 8192

///|
/// Quote this original private wire before UTF8, AEAD or Store construction.
/// The same private custody constructor/readback serves Model and Effect.
/// Its disk reservation cannot fund any of this live representation.
pub fn Store::private_evidence_custody_construction(
  self : Store,
  wire : String,
) -> PrivateEvidenceCustodyConstruction? {
  if self.closed || self.retiring {
    return None
  }
  guard private_evidence_custody_wire_construction(wire) is Some(layout) &&
    layout.envelope_bytes <= self.max_record_bytes else {
    return None
  }
  Some(layout)
}

///|
// The descriptor's canonical JSON has no literal line break. The encrypted
// plaintext is that exact descriptor, a separator and the exact raw bytes in
// Base64. In particular a non-UTF8 provider refusal is still stored verbatim.
fn model_raw_evidence_plaintext(
  descriptor : String,
  content_cid : String,
  byte_count : Int,
  bytes : Bytes,
) -> Result[String, NativePublicationStoreIssue] {
  if bytes.length() != byte_count || "sha256:" + @sha.hex(bytes) != content_cid {
    return Err(DigestMismatch)
  }
  Ok(descriptor + "\n" + @base64.encode(bytes))
}

///|
/// Measure before hashing, Base64, packing, AEAD or readback. The descriptor
/// and HTTP byte array remain borrowed from the original Call. The caller
/// admits these quantities on its existing Native Read before preparation.
pub fn Store::model_raw_evidence_custody_construction(
  self : Store,
  original : @publication.BoundModelRawResponse,
) -> PrivateEvidenceCustodyConstruction? {
  if self.closed ||
    self.retiring ||
    !@publication.model_raw_response_matches_store(original, self.authority_cid) {
    return None
  }
  let (_, _, descriptor, _, count) = @publication.model_raw_response_store_binding(
    original,
  )
  guard @scalar.admit_utf8_length(descriptor, 1048576) is Ok(descriptor_bytes) else {
    return None
  }
  let encoded = raw_base64_bytes(count.to_int64())
  let plaintext = descriptor_bytes.to_int64() + 1L + encoded
  guard count >= 0 &&
    plaintext <= 1048576L &&
    private_evidence_custody_construction(plaintext.to_int()) is Some(layout) &&
    layout.envelope_bytes <= self.max_record_bytes else {
    return None
  }
  // Besides the existing private custody, this path owns its joined plaintext
  // and temporary Base64/concat backing. Hashing includes its bounded state,
  // word schedule, digest and encoded CID.
  let retained = layout.retained
  let workspace = layout.workspace
  Some({
    envelope_bytes: layout.envelope_bytes,
    retained: {
      ..retained,
      owned_utf16_units: retained.owned_utf16_units + plaintext,
    },
    workspace: {
      record_headers: workspace.record_headers + 20L,
      reference_slots: workspace.reference_slots + 24L,
      scalar_words: workspace.scalar_words + 24L,
      owned_utf16_units: workspace.owned_utf16_units + 2L * plaintext + 128L,
      owned_wire_bytes: workspace.owned_wire_bytes + 512L,
    },
  })
}

///|
/// Prepare encrypted custody for this exact bound descriptor and byte array.
/// The original Model caller owns authority/currentness and retains the child
/// through persist and authenticated readback. Preparation is not a Raw ACK.
pub fn Store::prepare_model_raw_evidence_custody(
  self : Store,
  original : @publication.BoundModelRawResponse,
  bytes : Bytes,
  crypto : @signature.Library,
  key : Bytes,
  retain? : (ModelEvidenceCustody) -> Unit = _ => (),
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    match require_store_open(self) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    guard @publication.model_raw_response_matches_store(
      original,
      self.authority_cid,
    ) else {
      return Err(StateCollision)
    }
    guard self.model_raw_evidence_custody_construction(original) is Some(_) else {
      return Err(InvalidConfiguration)
    }
    self
    .prepare_model_raw_payload_in_scope(
      @publication.model_raw_response_store_binding(original),
      bytes,
      crypto,
      key,
    )
    .map(private_custody => {
      let child = {
        private_custody,
        original: @publication.model_raw_response_value(original),
      }
      // Custody must be reachable even if leaving the Store scope fails.
      retain(child)
      child
    })
  })
}

///|
/// Finish only the existing Store scope return. True means that the actual
/// parent Store has already closed, so the failed caller may drop this alias.
/// No SQL, evidence retirement, tombstone or confirmation is attempted here.
pub fn ModelEvidenceCustody::reconcile_original_store_return(
  self : ModelEvidenceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  let store = self.private_custody.store
  store.reconcile_original_return().map(_ => store.closed)
}

///|
fn Store::prepare_model_raw_payload_in_scope(
  self : Store,
  selection : (String, String, String, String, Int),
  bytes : Bytes,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[PrivateEffectEvidenceCustody, NativePublicationStoreIssue] {
  let (cid, holding, descriptor, content, count) = selection
  let wire = match
    model_raw_evidence_plaintext(descriptor, content, count, bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let terminal = "{\"cleanup_complete\":true,\"evidence_cid\":\"" +
    cid +
    "\",\"version\":\"actql-native-model-evidence-custody/0.1\"}"
  prepare_private_effect_custody(
    self, holding, "model_raw_response", cid, wire, "model_evidence_custody", "model-evidence",
    terminal, crypto, key,
  )
}

///|
/// One generation-zero entered Raw point. Its plaintext stays inside Store.
struct ModelEnteredRawReadExtent {
  store : Store
  cid : String
  holding : String
  descriptor : String
  content : String
  count : Int
  header : @sqlite.NativeJournalHeader
}

///|
/// Select the entered payload from the same bound Raw descriptor. The caller
/// must fund the actual point's transient construction on its current Read.
pub fn Store::model_entered_raw_read_construction(
  self : Store,
  raw : @publication.BoundModelRawResponse,
) -> Result[
  (ModelEnteredRawReadExtent, PrivateEvidenceCustodyConstruction),
  NativePublicationStoreIssue,
] {
  let (status, eof, _) = @publication.model_raw_response_transport_facts(raw)
  guard eof &&
    status >= 200 &&
    status < 300 &&
    @publication.model_raw_response_matches_store(raw, self.authority_cid) else {
    return Err(StateCollision)
  }
  self.observe_entered_model_raw_extent(
    @publication.model_raw_response_store_binding(raw),
  )
}

///|
fn Store::observe_entered_model_raw_extent(
  self : Store,
  selection : (String, String, String, String, Int),
) -> Result[
  (ModelEnteredRawReadExtent, PrivateEvidenceCustodyConstruction),
  NativePublicationStoreIssue,
] {
  self.with_original_read(false, false, fn() {
    match require_store_open(self) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let (cid, holding, descriptor, content, count) = selection
    guard count >= 0 &&
      @scalar.admit_utf8_length(descriptor, model_raw_descriptor_max_wire)
      is Ok(descriptor_bytes) else {
      return Err(InvalidConfiguration)
    }
    let encoded = raw_base64_bytes(count.to_int64())
    let plaintext = descriptor_bytes.to_int64() + 1L + encoded
    guard plaintext <= 1048576L else { return Err(InvalidConfiguration) }
    let header = match
      self.database.observe_body_extent("model_evidence_custody", holding) {
      Ok(value) => value
      Err(issue) => return Err(Database(issue))
    }
    guard header.revision == 0L &&
      header.body_bytes == raw_cipher_envelope_bytes(plaintext) &&
      header.body_bytes <= self.max_record_bytes.to_int64() &&
      private_evidence_custody_construction(plaintext.to_int()) is Some(layout) else {
      return Err(RecoveryRequired)
    }
    let workspace = layout.workspace
    Ok(
      (
        { store: self, cid, holding, descriptor, content, count, header, },
        {
          ..layout,
          workspace: {
            record_headers: workspace.record_headers + 20L,
            reference_slots: workspace.reference_slots + 24L,
            scalar_words: workspace.scalar_words + 24L,
            owned_utf16_units: workspace.owned_utf16_units +
            plaintext +
            encoded +
            128L,
            owned_wire_bytes: workspace.owned_wire_bytes +
            count.to_int64() +
            512L,
          },
        },
      ),
    )
  })
}

///|
/// Authenticate and hash the original entered response. No provider decoding
/// or plaintext leaves this operation, and it cannot enter or settle a Call.
pub fn ModelEnteredRawReadExtent::verify_original(
  self : ModelEnteredRawReadExtent,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.store.inspect_private_evidence_wire_at_extent(
    "model_evidence_custody",
    self.holding,
    self.header,
    "model_raw_response",
    self.cid,
    crypto,
    key,
    wire => {
      let at = self.descriptor.length()
      guard wire.length().to_int64() ==
        at.to_int64() + 1L + raw_base64_bytes(self.count.to_int64()) &&
        wire.has_prefix(self.descriptor) &&
        wire[at] == '\n' else {
        return Err(StateCollision)
      }
      let payload = wire[at + 1:]
      let bytes = @base64.decode(payload) catch {
        _ => return Err(StateCollision)
      }
      guard bytes.length() == self.count &&
        @base64.encode(bytes)[:] == payload &&
        "sha256:" + @sha.hex(bytes) == self.content else {
        return Err(DigestMismatch)
      }
      Ok(())
    },
  )
}

///|
/// The trusted Model caller supplies its original admitted evidence and the
/// same Run/Scope/Slot/attempt. Fund this constructor, encryption, readback and
/// failed-child overlap BEFORE calling; Store disk quota is independent.
pub fn Store::prepare_model_evidence_custody(
  self : Store,
  definition : @publication.PublicationContract,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  original : @publication.RunEvidenceValue,
  crypto : @signature.Library,
  key : Bytes,
  raw_descriptor? : @publication.BoundModelRawResponse? = None,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_model_evidence_custody_in_scope(
      definition,
      scope_cid,
      slot_cid,
      attempt_cid,
      original,
      crypto,
      key,
      raw_descriptor~,
    )
  })
}

///|
fn Store::prepare_model_evidence_custody_in_scope(
  self : Store,
  definition : @publication.PublicationContract,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  original : @publication.RunEvidenceValue,
  crypto : @signature.Library,
  key : Bytes,
  raw_descriptor? : @publication.BoundModelRawResponse? = None,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let role = @publication.run_evidence_value_name(original)
  let kind = if role == "model_raw_response" {
    guard raw_descriptor is Some(raw) &&
      @publication.model_raw_response_matches_store(raw, self.authority_cid) else {
      return Err(StateCollision)
    }
    let (cid, entered_holding, wire, _, _) = @publication.model_raw_response_store_binding(
      raw,
    )
    let (_, eof, _) = @publication.model_raw_response_transport_facts(raw)
    guard eof &&
      cid == @publication.run_evidence_value_identity(original) &&
      wire == @publication.run_evidence_value_json(original) &&
      @scalar.admit_utf8_length(wire, model_raw_descriptor_max_wire) is Ok(_) &&
      @publication.model_scoped_private_holding_cid(
        definition,
        self.authority_cid,
        scope_cid,
        slot_cid,
        attempt_cid,
        1,
        "entered",
        role,
      ) ==
      Some(entered_holding) else {
      return Err(StateCollision)
    }
    model_raw_descriptor_aad_role
  } else if raw_descriptor is None &&
    [
      "model_call_attempt", "model_attempt_accounting", "model_attempt_outcome",
      "model_dispatch_authority", "model_slot_capture", "model_invocation_evidence",
      "model_capture_bundle", "model_attachment_admission",
    ].contains(role) {
    role
  } else {
    return Err(InvalidConfiguration)
  }
  let holding = match
    @publication.model_scoped_private_holding_cid(
      definition,
      self.authority_cid,
      scope_cid,
      slot_cid,
      attempt_cid,
      1,
      "settled",
      role,
    ) {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  let cid = @publication.run_evidence_value_identity(original)
  let terminal = "{\"cleanup_complete\":true,\"evidence_cid\":\"" +
    cid +
    "\",\"version\":\"actql-native-model-evidence-custody/0.1\"}"
  prepare_private_effect_custody(
    self,
    holding,
    kind,
    cid,
    @publication.run_evidence_value_json(original),
    "model_evidence_custody",
    "model-evidence",
    terminal,
    crypto,
    key,
  ).map(private_custody => { private_custody, original, })
}

///|
/// One selected settlement leaf retains its original observed extent.
/// The caller owns the exact Journal locator and must fund the returned layout.
struct ModelSettlementReadExtent {
  store : Store
  holding : String
  evidence_cid : String
  aad_role : String
  max_wire : Int
  header : @sqlite.NativeJournalHeader
}

///|
/// Inspect a settled leaf selected by the original Attempt and Store.
/// This reads SQLite geometry before ciphertext or provider body allocation.
pub fn Store::model_settlement_restore_construction(
  self : Store,
  definition : @publication.PublicationContract,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  role : ModelSettlementReadRole,
  evidence_cid : String,
) -> Result[
  (ModelSettlementReadExtent, PrivateEvidenceCustodyConstruction),
  NativePublicationStoreIssue,
] {
  self.with_original_read(false, false, fn() {
    match require_store_open(self) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let semantic_role = match role {
      Accounting => "model_attempt_accounting"
      Outcome => "model_attempt_outcome"
      Capture => "model_slot_capture"
      RawDescriptor => "model_raw_response"
      Invocation => "model_invocation_evidence"
      CaptureBundle(_) => "model_capture_bundle"
    }
    let (aad_role, max_wire) = match role {
      RawDescriptor =>
        (model_raw_descriptor_aad_role, model_raw_descriptor_max_wire)
      CaptureBundle(maximum) => (semantic_role, Int::min(maximum, 1048576))
      _ => (semantic_role, 16384)
    }
    if max_wire <= 0 {
      return Err(InvalidConfiguration)
    }
    guard @publication.model_scoped_private_holding_cid(
        definition,
        self.authority_cid,
        scope_cid,
        slot_cid,
        attempt_cid,
        1,
        "settled",
        semantic_role,
      )
      is Some(holding) else {
      return Err(InvalidConfiguration)
    }
    let header = match
      self.database.observe_body_extent("model_evidence_custody", holding) {
      Ok(value) => value
      Err(issue) => return Err(Database(issue))
    }
    guard header.revision == 0L &&
      header.body_bytes <= raw_cipher_envelope_bytes(max_wire.to_int64()) &&
      header.body_bytes <= self.max_record_bytes.to_int64() &&
      private_evidence_envelope_construction(header.body_bytes) is Some(layout) else {
      return Err(RecoveryRequired)
    }
    let retained = {
      ..layout.retained,
      owned_utf16_units: layout.retained.owned_utf16_units + header.body_bytes,
    }
    Ok(
      (
        { store: self, holding, evidence_cid, aad_role, max_wire, header, },
        { ..layout, retained, },
      ),
    )
  })
}

///|
/// Open the same bounded extent using the original role and CID. The caller
/// admits this wire against the retained Run, Scope, Slot and Attempt.
pub fn ModelSettlementReadExtent::read_original_wire(
  self : ModelSettlementReadExtent,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[String, NativePublicationStoreIssue] {
  self.store
  .read_private_evidence_wire_at_extent(
    "model_evidence_custody",
    self.holding,
    self.header,
    self.aad_role,
    self.evidence_cid,
    crypto,
    key,
  )
  .bind(wire => {
    if @scalar.admit_utf8_length(wire, self.max_wire) is Ok(_) {
      Ok(wire)
    } else {
      Err(StateCollision)
    }
  })
}

///|
/// Restore only this exact existing cell. Missing evidence is never inserted,
/// treated as unsent, or replaced by a newly encrypted response.
pub fn Store::restore_model_evidence_custody(
  self : Store,
  definition : @publication.PublicationContract,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  original : @publication.RunEvidenceValue,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    let custody = match
      self.prepare_model_evidence_custody_in_scope(
        definition, scope_cid, slot_cid, attempt_cid, original, crypto, key,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    custody.private_custody.read().map(_ => custody)
  })
}

///|
pub fn ModelEvidenceCustody::persist(
  self : ModelEvidenceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.private_custody.persist()
  })
}

///|
/// Exact authenticated readback only. The original Model/Journal caller still
/// owes its own durable settlement and same-entry acknowledgement.
pub fn ModelEvidenceCustody::confirm(
  self : ModelEvidenceCustody,
) -> Result[@publication.RunEvidenceValue, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    match self.private_custody.read() {
      Ok((_, false)) => Ok(self.original)
      Ok((_, true)) => Err(RecoveryRequired)
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Called only by the owning Run after its original evidence retention ends.
/// Cancellation or a public terminal status alone cannot select retirement.
pub fn ModelEvidenceCustody::retry_cleanup(
  self : ModelEvidenceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(true, false, fn() {
    self.private_custody.retry_cleanup()
  })
}

///|
pub fn ModelEvidenceCustody::reserved_bytes(
  self : ModelEvidenceCustody,
) -> Int64 {
  self.private_custody.reserved_bytes()
}
