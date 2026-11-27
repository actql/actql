///|
const SAVED_EFFECT_RESOLUTION_PROOF_KIND : Int = 16

///|
const SAVED_EFFECT_RESOLUTION_PROOF_MAX : Int = 16384

///|
priv struct SavedEffectResolutionInput {
  at : String
  resolution : String
  evidence : String?
}

///|
priv struct StoredEffectResolutionProof {
  capacity : @resources.CapacityReservation
  challenge : @host.ClientEffectResolutionProofChallenge
  selection : @host.ClientLocalEffectApprovalSelection
  mut use_attempted : Bool
}

///|
fn saved_effect_resolution_proof_input(
  input : Bytes,
) -> (Bytes, SavedEffectResolutionInput?)? {
  guard input.length() >= 112 else { return None }
  let review = mock_effect_descriptor_field(input, 0)
  let resolution = mock_effect_descriptor_field(input, 4)
  let evidence = mock_effect_descriptor_field(input, 8)
  guard review >= 76 &&
    resolution > 0 &&
    resolution <= 65536 &&
    evidence >= 0 &&
    evidence <= 65536 &&
    review == input.length() - 36 - resolution - evidence &&
    input[36 + 71].to_int() == 2 else {
    return None
  }
  let unsigned = 36 + review
  let at = @utf8.decode(input[12:36]) catch { _ => return None }
  let answer = @utf8.decode(input[unsigned:unsigned + resolution]) catch {
    _ => return None
  }
  let approval = if evidence == 0 {
    None
  } else {
    Some(@utf8.decode(input[unsigned + resolution:]) catch { _ => return None })
  }
  Some(
    (
      input[36:unsigned].to_owned(),
      Some({ at, resolution: answer, evidence: approval, }),
    ),
  )
}

///|
fn prepare_saved_effect_resolution_proof(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  current : StoredHostCurrent,
  capacity : @resources.CapacityReservation,
  input : SavedEffectResolutionInput,
  review : @host.ClientEffectSavedReviewConfirmation,
  check : () -> Result[Unit, Int],
  fund : (Int, Int, Int) -> Result[Unit, Int],
) -> Result[Bytes, Int] {
  let control = configuration.tuple
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }
  // Public installation roles are fetched only inside the original Resolve
  // Read. The passed-in answer cannot choose their locator or permission.
  match
    fund(
      input.resolution.length() * 3 +
      input.evidence.map_or(0, body => body.length() * 3) +
      24576,
      1024,
      64,
    ) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let operator = match
    sdk_selected_original(value, current, "host.json", 8192) {
    Ok(bytes) => @utf8.decode(bytes) catch { _ => return Err(-31) }
    Err(code) => return Err(code)
  }
  guard @host.admit_client_host_signer_configuration(operator, {
      max_wire_bytes: 8192,
      max_nodes: 64,
      max_depth: 8,
      max_signers: 1,
    })
    is Ok(operator) &&
    !operator.has_explicit_signers() else {
    return Err(-32)
  }
  let reviewer = match
    sdk_selected_original(value, current, "effect-reviewer.json", 8192) {
    Ok(bytes) => @utf8.decode(bytes) catch { _ => return Err(-31) }
    Err(code) => return Err(code)
  }
  let host = match
    sdk_selected_original(value, current, "effect-host-attestation.json", 8192) {
    Ok(bytes) => @utf8.decode(bytes) catch { _ => return Err(-31) }
    Err(code) => return Err(code)
  }
  guard @host.admit_client_local_effect_approval_selection(
      reviewer,
      host,
      control.principal,
      control.connection,
    )
    is Some(selection) &&
    selection.signed_resource == "key/initial-host-attestation" else {
    return Err(-32)
  }
  let authentication : @host.ClientEffectResolutionReviewer = {
    registration: selection.registration,
    policy_cid: @host.client_local_default_signing_bootstrap_policy().cid(),
  }
  let challenge = match
    @host.prepare_client_effect_resolution_proof_challenge(
      review,
      input.resolution,
      input.evidence,
      authentication,
      input.at,
      () => check() is Ok(_),
      limits,
    ) {
    Ok(proof) => proof
    Err(@host.ReviewerRefused) => return Err(-47)
    Err(@host.Resolution(_)) => return Err(-31)
    Err(_) => return Err(-32)
  }
  let wire = match saved_effect_resolution_proof_wire(selection, challenge) {
    Ok(wire) => wire
    Err(code) => return Err(code)
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  record.append_plan = EffectProof({
    capacity,
    challenge,
    selection,
    use_attempted: false,
  })
  Ok(wire)
}

///|
fn saved_effect_resolution_proof_wire(
  selection : @host.ClientLocalEffectApprovalSelection,
  challenge : @host.ClientEffectResolutionProofChallenge,
) -> Result[Bytes, Int] {
  let (actor, resolution, approval) = challenge.proofs()
  try {
    let writer = @encode.writer(SAVED_EFFECT_RESOLUTION_PROOF_MAX, 40, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "actor")
    @encode.string_value(writer, actor)
    @encode.key(writer, "publicKey")
    @encode.string_value(writer, selection.reviewer_public_key)
    @encode.key(writer, "reviewerKey")
    @encode.string_value(writer, selection.registration.key_id)
    @encode.key(writer, "hostKey")
    @encode.string_value(writer, selection.host_key_id)
    @encode.key(writer, "hostPublicKey")
    @encode.string_value(writer, selection.host_public_key)
    @encode.key(writer, "proofs")
    @encode.begin_array(writer)
    let proofs = [resolution]
    if approval is Some(proof) {
      proofs.push(proof)
    }
    for (key, cid, signature) in proofs {
      @encode.begin_array(writer)
      @encode.string_value(writer, key)
      @encode.string_value(writer, cid)
      @encode.string_value(writer, signature)
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(-34)
  }
}

///|
fn produce_saved_effect_resolution_proof(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.invoked || record.output_closed {
    return -33
  }
  record.invoked = true
  let bytes = match
    select_saved_effect_checkpoint_review(value, record, configuration) {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, bytes),
  )
  if code == 0 {
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_resolution_proof(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.append_plan is EffectProof(proof) &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return -32
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let result = proof.challenge.require_waiting(
    (table, key, extent) => {
      physical_journal_row(
        current.physical,
        check,
        1,
        table,
        key,
        expected_body_length=Some(extent),
      )
    },
    -32,
  )
  match result.bind(_ => check()) {
    Ok(_) => 0
    Err(code) => code
  }
}
