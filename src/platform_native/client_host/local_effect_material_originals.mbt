///|
// Private metadata inside the existing versioned Run row. The material wire
// remains the exact existing Owner projection, not a new transport credential.
priv struct NativeClientEffectMaterialOriginalPacket {
  intent_cid : String
  materials_cid : String
  materials_wire : String
  request_scope_cid : String
  run_definition_cid : String
  submission_reference : String
}

///|
/// A current-authorized read of original private-journal bytes. This is not a
/// normalization proof, work claim, restored compilation or Provider permit.
/// Explicit restoration must still use the existing material Owner with this
/// independently retained request and Run, never identities from candidate wire.
struct NativeClientRetainedEffectMaterials {
  request : @host.ClientRequestIdentity
  definition : @publication.PublicationContract
  materials_wire : String
  materials_cid : String
}

///|
pub fn native_client_retained_effect_materials_wire(
  original : NativeClientRetainedEffectMaterials,
) -> String {
  original.materials_wire
}

///|
pub fn native_client_retained_effect_materials_cid(
  original : NativeClientRetainedEffectMaterials,
) -> String {
  original.materials_cid
}

///|
pub fn native_client_retained_effect_materials_request(
  original : NativeClientRetainedEffectMaterials,
) -> @host.ClientRequestIdentity {
  original.request
}

///|
pub fn native_client_retained_effect_materials_run(
  original : NativeClientRetainedEffectMaterials,
) -> @publication.PublicationContract {
  original.definition
}

///|
fn effect_material_original_packet_wire(
  packet : NativeClientEffectMaterialOriginalPacket,
) -> Result[String, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(131072, 16, 2)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("intent_cid", packet.intent_cid),
        ("materials_cid", packet.materials_cid),
        ("materials_wire", packet.materials_wire),
        ("request_scope_cid", packet.request_scope_cid),
        ("run_definition_cid", packet.run_definition_cid),
        ("submission_reference", packet.submission_reference),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn read_effect_material_original_packet(
  wire : String,
) -> Result[
  NativeClientEffectMaterialOriginalPacket,
  NativeClientRunJournalIssue,
] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 131072,
      max_nodes: 16,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: 131072,
      max_total_string_bytes: 131072,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @decode.closed_object(cursor, [
      "intent_cid", "materials_cid", "materials_wire", "request_scope_cid", "run_definition_cid",
      "submission_reference",
    ])
    is Ok(fields) &&
    epoch_text(fields, "intent_cid") is Some(intent_cid) &&
    epoch_text(fields, "materials_cid") is Some(materials_cid) &&
    epoch_text(fields, "materials_wire") is Some(materials_wire) &&
    !materials_wire.is_empty() &&
    epoch_text(fields, "request_scope_cid") is Some(request_scope_cid) &&
    epoch_text(fields, "run_definition_cid") is Some(run_definition_cid) &&
    epoch_text(fields, "submission_reference") is Some(submission_reference) else {
    return Err(CustodyLost)
  }
  let packet : NativeClientEffectMaterialOriginalPacket = {
    intent_cid,
    materials_cid,
    materials_wire,
    request_scope_cid,
    run_definition_cid,
    submission_reference,
  }
  guard effect_material_original_packet_wire(packet) is Ok(canonical) &&
    canonical == wire else {
    return Err(CustodyLost)
  }
  Ok(packet)
}

///|
/// Accept the original Run and already-issued packet in the same transaction.
/// Material binding and current submit authorization are existing Owners.
/// An existing equal packet is reused; missing accepted custody is not backfilled
/// even before physical start. The existing record capacity is unchanged.
/// A source_free_run_file selects an authenticated installation original only
/// for first acceptance. Repeated accepted operations keep the saved policy;
/// the filename is never a read grant or a replacement policy on restoration.
pub fn NativeLocalHostConnection::accept_submitted_effect_material_original(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  now : Double,
  source_free_run_file? : String? = None,
) -> Result[
  NativeClientSubmittedIntentRecord,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  self.accept_submitted_effect_material_with_policy(
    crypto,
    principal,
    connection,
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    now,
    source_free_run_file,
    None,
  )
}

///|
// All entry points retain the same existing acceptance transaction.
// The optional finite original can only enter with its current selected Host
// binding; Common metadata by itself never supplies that physical authority.
fn NativeLocalHostConnection::accept_submitted_effect_material_with_policy(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  now : Double,
  source_free_run_file : String?,
  local_policy : (
    NativeLocalRunPolicyBinding,
    @host.ClientLocalRunPolicyOriginal,
  )?,
  capture? : NativeLocalJournalCapture? = None,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[
  NativeClientSubmittedIntentRecord,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      SubmitOriginals,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match
    self.journal.authorize_submitted_run(
      self.epoch,
      reference,
      request,
      authority.scope,
      authority.current_for(self.journal, request),
      now,
      operations~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  guard preparation.preparation is EffectComputation(prepared) &&
    physical_equal(
      prepared,
      @host.client_effect_compilation_owner(allowed.compilation),
    ) else {
    return Err(ForeignPreparation)
  }
  let materials = match
    @host.bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Materials(issue))
  }
  guard @host.client_effect_normalization_materials_cid(materials)
    is Some(materials_cid) else {
    return Err(Materials(Normalization(UnverifiedOriginalMaterials)))
  }
  let observation = match
    @host.capture_client_effect_run_observation_originals(
      prepared, allowed, definition,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(ForeignRun))
  }
  let packet : NativeClientEffectMaterialOriginalPacket = {
    intent_cid: preparation.intent_cid,
    materials_cid,
    materials_wire: @host.client_effect_issued_normalization_materials_wire(
      issued,
    ),
    request_scope_cid: @host.client_request_scope_cid(request),
    run_definition_cid: @publication.publication_contract_identity(definition),
    submission_reference: reference.wire,
  }
  let wire = match effect_material_original_packet_wire(packet) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let (policy_wire, policy_selection) = match source_free_run_file {
    None =>
      if @host.prepared_client_effect_publication_data_policy_cid(prepared)
        is Some(_) {
        // The checked Source/Result closure is immutable compiler DATA. Keep
        // its existing original bodies with first acceptance, not a current
        // installation policy or a replacement inferred during Saved read.
        match @host.issue_client_effect_run_policy_originals(prepared) {
          Ok(wire) => (Some(wire), None)
          Err(issue) => return Err(Journal(policy_originals_issue(issue)))
        }
      } else {
        (None, None)
      }
    Some(file) => {
      let graph = @strategy.checked_effect_computation_graph(
        @host.prepared_client_effect_computation_graph(prepared),
      )
      // The existing Work retains Values-family admission and actual funding.
      // This finite metadata connection does not claim that those are present.
      if !@strategy.graph_source_free_inputs_complete(graph) ||
        @strategy.graph_captured_prefix(graph) != 0 ||
        @strategy.graph_task_count(graph) != 1 ||
        @strategy.graph_task_input_count(graph, 0) != Some(0) ||
        @host.prepared_client_effect_infer_occurrence(prepared) is Some(_) {
        return Err(ForeignPreparation)
      }
      match
        self.select_effect_values_policy_originals(
          reference, request, definition, file,
        ) {
        Ok((wire, selection)) => (Some(wire), selection)
        Err(issue) => return Err(Journal(issue))
      }
    }
  }
  let local_run_policy_original = match local_policy {
    None => None
    Some((binding, original)) => {
      if !physical_equal(binding.host, self) ||
        binding.principal != principal ||
        binding.connection != connection ||
        binding.scope != authority.scope {
        return Err(Journal(AuthorizationDenied))
      }
      let ref_record = reference.original
      if @host.admit_client_local_run_policy_original(
          @host.client_local_run_policy_original_body(original),
          binding.profile,
          ref_record,
          request,
          definition,
          self.adoption_cid(),
          binding.read_selection_cid,
        )
        is Err(_) {
        return Err(Journal(CustodyLost))
      }
      Some(original)
    }
  }
  let current = () => {
    authority.current_for(self.journal, request) &&
    (match policy_selection {
      None => true
      Some(selection) => selection.current()
    }) &&
    (match local_policy {
      None => true
      Some((binding, _)) =>
        match capture {
          None => binding.current_for(self.journal, Some(request), true)
          Some(original) =>
            binding.current_in_original_read(original, Some(request), true)
        }
    })
  }
  self.journal
  .accept_original_submitted_run(
    self.epoch,
    reference,
    preparation.intent_cid,
    request,
    definition,
    authority.scope,
    authority.current_for(self.journal, request),
    effect_material_originals=Some(wire),
    publication_policy_originals=policy_wire,
    local_run_policy_original~,
    run_observation_originals=Some(observation),
    current_fence=Some(current),
    operations~,
  )
  .map_err(issue => Journal(issue))
}

///|
/// Accept the SAME issued material and Run while the original captured Read
/// owns the operation. Every epoch/read/write uses that capture's existing
/// Read/SQLite exchange. Neither a new Host nor a standalone SQL entrance is
/// selected. The caller admits the packet's construction before entering here.
/// The outer result preserves Read/current/return failure independently of
/// the inner material/acceptance result, including a committed-but-lost return.
pub fn NativeLocalJournalCapture::accept_submitted_effect_material_original_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  now : Double,
  local_policy? : (
    NativeLocalRunPolicyBinding,
    @host.ClientLocalRunPolicyOriginal,
  )? = None,
) -> Result[
  Result[
    NativeClientSubmittedIntentRecord,
    NativeClientSubmittedEffectMaterialsIssue,
  ],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    if @host.client_request_authority_scope_cid(request) != expected_scope {
      return Err(Epoch(ScopeMismatch))
    }
    Ok(
      host.accept_submitted_effect_material_with_policy(
        self.crypto,
        principal,
        connection,
        reference,
        preparation,
        request,
        allowed,
        definition,
        issued,
        now,
        None,
        local_policy,
        capture=Some(self),
        operations=Some(operations),
      ),
    )
  })
}

///|
/// Read the original packet through current Run read authority. No preparation,
/// compilation, normalization issuance, Source acquisition or send occurs.
/// Missing or inconsistent custody is a refusal, never a new material packet.
pub fn NativeLocalHostConnection::lookup_submitted_effect_material_original(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[
  NativeClientRetainedEffectMaterials,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let original = match
    self.journal.lookup_submitted_intent(
      self.epoch,
      reference,
      authority.scope,
      authority.current_for(self.journal, request),
      now,
    ) {
    Ok(Submitted(value)) => value
    Ok(UnresolvedSubmissionHistory) => return Err(UnresolvedHistory)
    Err(issue) => return Err(Journal(issue))
  }
  guard original.run_admission is Some(admission) else {
    return Err(MissingRunAdmission)
  }
  if @host.client_request_identity_relation(admission.request, request) !=
    @host.SameRequest {
    return Err(ChangedIntent)
  }
  self.journal
  .transaction(() => {
    if !authority.current_for(self.journal, request) {
      return Err(AuthorizationDenied)
    }
    let record = match self.journal.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if @publication.publication_contract_identity(record.definition) !=
      admission.run_definition_cid {
      return Err(ForeignRun)
    }
    guard record.effect_material_originals is Some(wire) else {
      return Err(MissingEffectMaterialOriginal)
    }
    let packet = match read_effect_material_original_packet(wire) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if packet.intent_cid != @host.client_submitted_intent_cid(original.intent) ||
      packet.submission_reference != reference.wire ||
      packet.request_scope_cid != @host.client_request_scope_cid(request) ||
      packet.run_definition_cid != admission.run_definition_cid {
      return Err(CustodyLost)
    }
    // Hash the exact retained wire. Configuration canonicalization must never
    // normalize Program/parameter values or replace an absent original packet.
    guard local_adoption_digest(crypto, @utf8.encode(packet.materials_wire))
      is Ok(digest) &&
      digest == packet.materials_cid else {
      return Err(CustodyLost)
    }
    if !authority.current_for(self.journal, request) {
      return Err(AuthorizationDenied)
    }
    Ok({
      request: record.request,
      definition: record.definition,
      materials_wire: packet.materials_wire,
      materials_cid: packet.materials_cid,
    })
  })
  .map_err(issue => Journal(issue))
}
