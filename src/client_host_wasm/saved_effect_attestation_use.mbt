///|
const SAVED_EFFECT_ATTESTATION_USE_KIND : Int = 17

///|
const SAVED_EFFECT_ATTESTATION_USE_MAX : Int = 32768

///|
priv struct StoredSavedEffectAttestationUse {
  parent : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectHostAttestationUse
  mut decision_attempted : Bool
}

///|
fn saved_effect_attestation_use_parent(
  instance : Instance,
  record : StoredSubmissionProjection,
) -> (Int, StoredSubmissionProjection, StoredEffectResolutionProof, Bytes)? {
  guard record.borrow is Ok(borrow) &&
    @buffers.filled_payload_input_bytes(instance.pool, borrow) is Some(packet) &&
    packet.length() > 4 + 106 &&
    packet.length() <= 4 + 234 + SAVED_EFFECT_RESOLUTION_PROOF_MAX else {
    return None
  }
  let id = mock_effect_descriptor_field(packet, 0)
  guard id > 0 && instance.submissions.get(id) is Some(parent) &&
    parent.kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND &&
    parent.configuration == record.configuration &&
    parent.produced &&
    !parent.output_closed &&
    parent.append_plan is EffectProof(proof) &&
    @buffers.buffer_wire(instance.pool, parent.slot) is Some(verified_wire) else {
    return None
  }
  let end = packet.length() - verified_wire.length()
  guard end > 4 + 106 && end <= 4 + 234 &&
    packet[end:] == verified_wire[:] else {
    return None
  }
  Some((id, parent, proof, packet[4:end].to_owned()))
}

///|
fn saved_effect_attestation_initialization(bytes : Bytes) -> String? {
  guard bytes.length() <= 8192 &&
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: 8192, max_nodes: 32, max_depth: 4,
    }) is Ok(source) &&
    @decode.admit(source, {
      max_nodes: 32, max_depth: 4, max_string_bytes: 512, max_total_string_bytes: 4096,
    }) is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "configuration_custody_cid", "device", "inode", "intent_cid", "version",
    ]) is Ok(fields) else {
    return None
  }
  required_text(fields, "intent_cid")
}

///|
fn produce_saved_effect_attestation_use(
  instance : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.invoked || record.output_closed { return -33 }
  record.invoked = true
  let check = () => submission_lookup_current(instance, record, configuration)
  match check() {
    Ok(_) => ()
    Err(code) => return code
  }
  guard configuration.host_current is Some(current_handle) &&
    instance.host_currents.get(current_handle) is Some(current) &&
    current.adoption_original is Some(adoption) &&
    configuration.sdk is Some(sdk) &&
    record.append_plan is Idle else {
    return -32
  }
  let capacity = match @resources.reserve_capacity(instance.root, 0L, 524288L) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  guard saved_effect_attestation_use_parent(instance, record)
    is Some((id, parent, proof, generation)) &&
    !proof.use_attempted &&
    proof.selection.private_key_file == "effect-host.key" &&
    saved_effect_attestation_initialization(adoption) is Some(intent) else {
    return -32
  }
  proof.use_attempted = true
  let current_proof = validate_saved_effect_resolution_proof(instance, parent, configuration)
  if current_proof != 0 { return current_proof }
  let role = match sdk_selected_original(instance, current, "effect-host-attestation.json", 8192) {
    Ok(bytes) => bytes
    Err(code) => return code
  }

  // This phase can enter only through the protected Host that has consumed
  // and physically verified both exact proofs in the preceding same Read.
  // Its transfer repeats that exact funded descriptor and cannot substitute
  // an alternate preimage, proof key, generation, or waiting Run.
  let (_, first, second) = proof.challenge.proofs()
  let attestation = match proof.challenge.verified(
    () => check() is Ok(_),
    (key, cid, signature) => first == (key, cid, signature) ||
      second == Some((key, cid, signature)),
  ) {
    Ok(value) => value
    Err(_) => return -47
  }
  guard attestation.observed_at_ms() is Some(at) else { return -31 }
  let selected : @host.ClientEffectSelectedHostSigningOriginal = {
    account: configuration.account,
    principal: configuration.tuple.principal,
    connection: configuration.tuple.connection,
    authority_scope_cid: configuration.authority_scope_cid,
    resource: proof.selection.signed_resource,
    adoption_cid: sdk.adoption_cid,
    initialization_intent_cid: intent,
    key_configuration_cid: "sha256:" + @sha.hex(role),
    key_generation_cid: "sha256:" + @sha.hex(generation),
    key_id: proof.selection.host_key_id,
    key_public: proof.selection.host_public_key,
  }
  let original = match attestation.prepare_use(selected, at, () => check() is Ok(_)) {
    Ok(value) => value
    Err(_) => return -32
  }
  guard original.originals() is Ok((grant_cid, grant, use_cid, use_entry, preimage)) else {
    return -31
  }
  guard original.window() is Some((sampled, expiry)) else { return -31 }
  let wire = try {
    let writer = @encode.writer(SAVED_EFFECT_ATTESTATION_USE_MAX, 32, 3)
    @encode.begin_object(writer)
    for (name, body) in [
      ("checkpointCid", original.checkpoint_cid()),
      ("grantCid", grant_cid), ("grant", grant), ("useCid", use_cid),
      ("use", use_entry), ("preimage", preimage),
      ("keyId", selected.key_id), ("publicKey", selected.key_public),
    ] {
      @encode.key(writer, name)
      @encode.string_value(writer, body)
    }
    @encode.key(writer, "sampledAtMs")
    @encode.string_value(writer, sampled.to_string())
    @encode.key(writer, "expiresAtMs")
    @encode.string_value(writer, expiry.to_string())
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return -34
  }
  let code = status(@buffers.supply_buffer_output(instance.pool, record.slot, wire))
  if code == 0 {
    record.append_plan = EffectAttestationUse({ parent: id, capacity, original, decision_attempted: false })
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_attestation_use(
  instance : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.append_plan is EffectAttestationUse(use_entry) &&
    use_entry.original.originals() is Ok(_) &&
    instance.submissions.get(use_entry.parent) is Some(parent) else {
    return -32
  }
  validate_saved_effect_resolution_proof(instance, parent, configuration)
}
