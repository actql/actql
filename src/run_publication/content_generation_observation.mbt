///|
/// Structural evidence bound to the real common generation and issued opaque
/// reference. The installing Host owns physical Store admission, durable
/// holding and current authority; this borrows them without a second owner.
struct BoundContentGeneration {
  template : RunEvidenceValue
  evidence : RunEvidenceValue
  derivation : RunEvidenceValue
  input_artifact : RunEvidenceValue
  reference : @admitted.ReferenceValue
  reference_envelope : @json.CanonicalValue
}

///|
/// Stored row readmission may borrow only this currently issued exact Ref.
/// This is the existing value reissuer, not fresh byte/Model authority.
pub fn bound_content_generation_reference_reissuer(
  value : BoundContentGeneration,
) -> @admitted.ReferenceIssuer? {
  if !@admitted.reference_available(value.reference) {
    return None
  }
  Some(
    @admitted.bind_reference_reissuer((contract, wire) => {
      if @admitted.reference_available(value.reference) &&
        @admitted.reference_wire(value.reference) == wire &&
        @admitted.reference_compatible(value.reference, contract) {
        Some(value.reference)
      } else {
        None
      }
    }),
  )
}

///|
/// Re-admit the immutable proof named by the authenticated original holding.
/// The trusted installing owner supplies expected_generation_cid from that
/// custody, not from the candidate proof. The original checked Run supplies
/// template/node/barrier. A current opaque Ref is required independently.
/// This does not claim fresh encoding, reacquire an input or renew its lifetime.
pub fn readmit_generated_content_observation(
  template : RunEvidenceValue,
  run_definition_cid : String,
  node_id : String,
  barrier_cid : String,
  expected_generation_cid : String,
  input_artifact : RunEvidenceValue,
  derivation : RunEvidenceValue,
  evidence : RunEvidenceValue,
  candidate : StoredGeneratedContentReference,
  content : @admitted.CheckedValue,
) -> Result[BoundContentGeneration, RunEvidenceValueIssue] {
  let issue = RunEvidenceReferenceMismatch("content_generation.recovery")
  if template.name != "bound_invocation_template" ||
    !content_template_requires_generation(template) ||
    input_artifact.name != "content_input_artifact" ||
    derivation.name != "content_evidence" ||
    evidence.name != "content_generation" ||
    !valid_contract_cid(expected_generation_cid) ||
    evidence.identity != expected_generation_cid ||
    contract_string_from_value(evidence.value, "node_id") != Some(node_id) ||
    contract_string_from_value(evidence.value, "barrier_cid") !=
    Some(barrier_cid) {
    return Err(issue)
  }
  guard content.value is @admitted.Reference(reference) &&
    @admitted.reference_available(reference) &&
    @admitted.reference_identity_cid(reference) == candidate.body.identity &&
    @admitted.reference_wire(reference) == candidate.body.wire &&
    @json.object_field(candidate.body.envelope, "metadata") is Some(metadata) &&
    @json.object_field(metadata, "issuer_evidence") is Some(issuer) &&
    content_generation_structure_matches(
      template.value,
      input_artifact.value,
      derivation.value,
      evidence.value,
      candidate.body.envelope,
      run_definition_cid,
    ) else {
    return Err(issue)
  }
  // These are fifteen fixed metadata links, not a row/payload scan. Admission
  // already verified each proof's closed protocol shape and original self CID.
  for index in 0..<15 {
    guard content_generation_link_pair(
        derivation.value,
        evidence.value,
        input_artifact.value,
        candidate.body.envelope,
        template.value,
        issuer,
        index,
      )
      is Some((left, right)) &&
      left == right else {
      return Err(issue)
    }
  }
  // Current access can be revoked while the original proofs are still valid.
  if !@admitted.reference_available(reference) {
    return Err(issue)
  }
  Ok({
    template,
    evidence,
    derivation,
    input_artifact,
    reference,
    reference_envelope: candidate.body.envelope,
  })
}

///|
fn content_template_requires_generation(template : RunEvidenceValue) -> Bool {
  guard @json.object_field(template.value, "required_profile_contracts")
    is Some(@json.Array(profiles)) else {
    return false
  }
  for index in 0..<@json.array_count(profiles) {
    guard @json.array_at(profiles, index) is Some(profile) else { return false }
    if contract_string_from_value(profile, "profile_id") ==
      Some("actql-content/0.1") {
      return true
    }
  }
  false
}

///|
pub fn bind_generated_content_observation(
  template : RunEvidenceValue,
  run_definition_cid : String,
  node_id : String,
  barrier_cid : String,
  input_artifact : RunEvidenceValue,
  candidate : GeneratedContentReference,
  content : @admitted.CheckedValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[BoundContentGeneration, RunEvidenceValueIssue] {
  if template.name != "bound_invocation_template" ||
    !content_template_requires_generation(template) {
    return Err(RunEvidenceReferenceMismatch("content_generation.template"))
  }
  guard generated_content_reference_completion_for(candidate, candidate.owner)
    is Some(completion) &&
    content.value is @admitted.Reference(reference) &&
    @admitted.reference_available(reference) &&
    @admitted.reference_identity_cid(reference) == candidate.identity &&
    @admitted.reference_wire(reference) == candidate.wire else {
    return Err(RunEvidenceReferenceMismatch("content_generation.reference"))
  }
  if input_artifact.name != "content_input_artifact" ||
    contract_string_from_value(
      input_artifact.value,
      "effective_data_policy_cid",
    ) !=
    Some(candidate.binding.effective_data_policy_cid) ||
    !(@json.object_field(input_artifact.value, "row_count")
    is Some(@json.Number(rows)) &&
    rows == completion.row_count.to_double()) {
    return Err(RunEvidenceReferenceMismatch("content_generation.input"))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  let derivation_body = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("version", "actql-content-derivation-evidence/0.1"),
        ("barrier_cid", barrier_cid),
        ("barrier_input_artifact_cid", input_artifact.identity),
        ("content_cid", completion.content_cid),
        ("content_ref_cid", candidate.identity),
        ("content_issuer_evidence_cid", candidate.issuer_evidence_cid),
        ("media_type", completion.media_type),
        ("name", completion.name),
        (
          "effective_data_policy_cid",
          candidate.binding.effective_data_policy_cid,
        ),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "row_count")
    @encode.number_value(writer, completion.row_count.to_double())
    @encode.key(writer, "byte_count")
    @encode.number_value(writer, completion.size_bytes.to_double())
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(RunEvidenceEncoding)
  }
  let derivation = match
    seal_run_evidence_value(
      "content_evidence", derivation_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  let body = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("version", "actql-content-generation/0.1"),
        ("bound_invocation_template_cid", template.identity),
        ("run_definition_cid", run_definition_cid),
        ("node_id", node_id),
        ("barrier_cid", barrier_cid),
        ("content_evidence_cid", derivation.identity),
        (
          "availability_evidence_cid",
          candidate.binding.availability_evidence_cid,
        ),
        ("content_store_cid", candidate.binding.content_store_cid),
        ("workspace_scope_cid", candidate.binding.workspace_scope_cid),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(RunEvidenceEncoding)
  }
  seal_run_evidence_value(
    "content_generation", body, max_wire_bytes, max_nodes, max_depth,
  ).map(evidence => {
    template,
    evidence,
    derivation,
    input_artifact,
    reference,
    reference_envelope: candidate.envelope,
  })
}

///|
/// Saved generation inventory borrows sealed identities, not source rows.
pub fn bound_content_generation_input_artifact(
  generation : BoundContentGeneration,
) -> RunEvidenceValue? {
  if bound_content_generation_value(generation) is None {
    return None
  }
  Some(generation.input_artifact)
}

///|
pub fn bound_content_generation_location(
  generation : BoundContentGeneration,
) -> (String, String)? {
  guard bound_content_generation_value(generation) is Some(value) &&
    contract_string_from_value(value.value, "content_store_cid") is Some(store) &&
    contract_string_from_value(value.value, "node_id") is Some(node) else {
    return None
  }
  Some((store, node))
}

///|
/// Immutable physical custody cell under the existing publication Store.
/// A role identifies exactly one body for this Run's checked output node.
pub fn content_generation_private_holding_cid(
  definition : PublicationContract,
  store_authority_cid : String,
  node_id : String,
  role : String,
) -> String? {
  if definition.name != "run_definition" ||
    !valid_contract_cid(store_authority_cid) ||
    node_id.is_empty() ||
    node_id.length() > 128 ||
    ![
      "content_input_artifact", "content_evidence", "content_generation", "content_bytes",
    ].contains(role) {
    return None
  }
  try {
    let writer = @encode.hashing_writer(2048, 64, 2)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("node_id", node_id),
        ("role", role),
        ("run_definition_cid", definition.identity),
        ("store_authority_cid", store_authority_cid),
        ("version", "actql-content-private-holding/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Some("sha256:" + @encode.finish_hash(writer))
  } catch {
    _ => None
  }
}

///|
/// Describe one saved occurrence's required physical custody. This is not
/// chain validation or reference issuance: the Store calls it only after the
/// existing computation/commit owner has validated the containing CapturedRun.
/// The index is an occurrence, never a content-CID deduplication key.
pub fn captured_content_generation_count(
  captured : PublicationContract,
) -> Int? {
  if captured.name != "captured_run" {
    return None
  }
  guard @json.object_field(captured.value, "effect_context") is Some(context) else {
    return None
  }
  match @json.object_field(context, "content_generations") {
    None => Some(0)
    Some(@json.Array(records)) => Some(@json.array_count(records))
    _ => None
  }
}

///|
pub fn captured_content_generation_storage(
  captured : PublicationContract,
  definition : PublicationContract,
  store_authority_cid : String,
  index : Int,
) -> (String, String, String, Int64, Array[(String, String, String, String)])? {
  if captured.name != "captured_run" || definition.name != "run_definition" {
    return None
  }
  guard @json.object_field(captured.value, "receipt") is Some(receipt) &&
    @json.object_field(receipt, "result_manifest") is Some(manifest_body) &&
    evidence_string(manifest_body, "run_definition_cid") ==
    Some(definition.identity) &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(context, "content_generations")
    is Some(@json.Array(records)) &&
    index >= 0 &&
    index < @json.array_count(records) &&
    @json.array_at(records, index) is Some(record) &&
    content_capture_proof(record, 1) is Some((generation, _)) &&
    content_capture_proof(record, 0) is Some((derivation, _)) &&
    content_capture_proof(record, 3) is Some((reference, _)) &&
    evidence_string(generation, "run_definition_cid") ==
    Some(definition.identity) &&
    evidence_string(generation, "content_store_cid") ==
    Some(store_authority_cid) &&
    evidence_string(generation, "node_id") is Some(node) &&
    evidence_string(reference, "content_ref_cid") is Some(manifest) &&
    evidence_string(derivation, "content_cid") is Some(content) &&
    @json.object_field(derivation, "byte_count") is Some(@json.Number(bytes)) &&
    @scalar.read_safe_integer(bytes) is Some(byte_count) &&
    byte_count >= 0 &&
    content_generation_private_holding_cid(
      definition, store_authority_cid, node, "content_bytes",
    )
    is Some(holding) else {
    return None
  }
  let bindings = []
  for
    (proof, name) in [
      (2, "content_input_artifact"),
      (0, "content_evidence"),
      (1, "content_generation"),
    ] {
    guard content_capture_proof(record, proof) is Some((value, identity_field)) &&
      evidence_string(value, identity_field) is Some(identity) &&
      content_generation_private_holding_cid(
        definition, store_authority_cid, node, name,
      )
      is Some(private_holding) else {
      return None
    }
    // Only fixed metadata proofs, never the actual input rows or byte payload.
    let wire = @json.stringify_value(value, 16384, 256, 16) catch {
      _ => return None
    }
    bindings.push((name, identity, wire, private_holding))
  }
  Some((holding, manifest, content, byte_count, bindings))
}

///|
/// Select recovery proofs from this admitted CapturedRun, not from caller
/// labels or a Model scope. The installing Store must independently confirm
/// this occurrence's original holding and private evidence before issuing the
/// current reference. This operation neither reads bytes nor renews custody.
pub fn readmit_captured_generated_content_observation(
  captured : PublicationContract,
  definition : PublicationContract,
  template : RunEvidenceValue,
  node_id : String,
  barrier_cid : String,
  store_authority_cid : String,
  index : Int,
  candidate : StoredGeneratedContentReference,
  content : @admitted.CheckedValue,
) -> Result[BoundContentGeneration, RunEvidenceValueIssue] {
  let issue = RunEvidenceReferenceMismatch(
    "content_generation.captured_recovery",
  )
  guard captured_content_generation_storage(
      captured, definition, store_authority_cid, index,
    )
    is Some(_) &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(context, "content_generations")
    is Some(@json.Array(records)) &&
    @json.array_at(records, index) is Some(record) else {
    return Err(issue)
  }
  let proofs = []
  for
    (proof, name) in [
      (2, "content_input_artifact"),
      (0, "content_evidence"),
      (1, "content_generation"),
    ] {
    guard content_capture_proof(record, proof) is Some((body, _)) else {
      return Err(issue)
    }
    let wire = @json.stringify_value(body, 16384, 256, 16) catch {
      _ => return Err(issue)
    }
    match admit_run_evidence_value(name, wire, 16384, 256, 16) {
      Ok(value) => proofs.push(value)
      Err(error) => return Err(error)
    }
  }
  readmit_generated_content_observation(
    template,
    definition.identity,
    node_id,
    barrier_cid,
    proofs[2].identity,
    proofs[0],
    proofs[1],
    proofs[2],
    candidate,
    content,
  )
}

///|
pub fn bound_content_generation_derivation(
  generation : BoundContentGeneration,
) -> RunEvidenceValue? {
  if bound_content_generation_value(generation) is None {
    return None
  }
  Some(generation.derivation)
}

///|
pub fn bound_content_generation_value(
  generation : BoundContentGeneration,
) -> RunEvidenceValue? {
  if !@admitted.reference_available(generation.reference) {
    return None
  }
  Some(generation.evidence)
}

///|
pub fn bound_content_generation_reference(
  generation : BoundContentGeneration,
) -> String? {
  if !@admitted.reference_available(generation.reference) {
    return None
  }
  Some(@admitted.reference_identity_cid(generation.reference))
}

///|
pub fn bound_content_generation_availability(
  generation : BoundContentGeneration,
) -> String? {
  if bound_content_generation_value(generation) is None {
    return None
  }
  contract_string_from_value(
    generation.evidence.value,
    "availability_evidence_cid",
  )
}

///|
/// Borrow the exact original proofs for the existing capture emitter. A saved
/// envelope is evidence, not a ReferenceIssuer or renewed read authority.
fn content_generation_capture_field(
  generation : BoundContentGeneration,
  index : Int,
) -> @json.CanonicalValue? {
  if bound_content_generation_value(generation) is None {
    return None
  }
  match index {
    0 => Some(generation.derivation.value)
    1 => Some(generation.evidence.value)
    2 => Some(generation.input_artifact.value)
    3 => Some(generation.reference_envelope)
    4 => Some(generation.template.value)
    _ => None
  }
}

///|
/// The opaque generation already binds its input and issued reference policy.
/// A following Model has its own checked output policy; it must not relabel
/// the intermediate Content to that policy. Terminal Content still binds the
/// Result observation directly. Model scope admission checks its output policy.
fn content_generation_observation_policy_matches(
  generation : BoundContentGeneration,
  observation : RunEvidenceValue,
) -> Bool {
  let policy = contract_string_from_value(
    generation.derivation.value,
    "effective_data_policy_cid",
  )
  policy is Some(_) &&
  contract_string_from_value(
    generation.input_artifact.value,
    "effective_data_policy_cid",
  ) ==
  policy &&
  (
    model_template_requires_slots(generation.template) ||
    contract_string_from_value(observation.value, "data_policy_cid") == policy
  )
}

///|
/// Receipt and capture share the authored occurrence inventory; matching bytes
/// never deduplicates two distinct generation occurrences.
fn receipt_content_identities(
  generations : Array[BoundContentGeneration],
  template_cid : String,
  definition_cid : String,
  observation : RunEvidenceValue,
) -> Result[Array[String], RunReceiptIssuanceIssue] {
  let expected = match
    @json.object_field(observation.value, "content_generation_cids") {
    None => []
    Some(value) =>
      match evidence_string_array(value) {
        Some(values) => values
        None =>
          return Err(
            ReceiptIssuanceInventoryMismatch("content_generation_cids"),
          )
      }
  }
  if expected.length() != generations.length() {
    return Err(ReceiptIssuanceInventoryMismatch("content_generation_cids"))
  }
  let identities : Array[String] = []
  for index, generation in generations {
    guard bound_content_generation_value(generation) is Some(evidence) &&
      generation.template.identity == template_cid &&
      contract_string_from_value(evidence.value, "run_definition_cid") ==
      Some(definition_cid) &&
      content_generation_observation_policy_matches(generation, observation) &&
      evidence.identity == expected[index] &&
      !identities.contains(evidence.identity) else {
      return Err(ReceiptIssuanceReferenceMismatch("content_generation_cids"))
    }
    identities.push(evidence.identity)
  }
  Ok(identities)
}

///|
/// Match the installing checked owner's entire ordered component inventory.
/// Do not sort or deduplicate occurrences by content CID. This checks saved
/// evidence identity, not physical reservation/cleanup completion.
pub fn issue_content_run_invocation(
  template : RunEvidenceValue,
  observation : RunEvidenceValue,
  expected : Array[BoundContentGeneration],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, RunEvidenceValueIssue] {
  // Model observations still require their own complete capture proof. The
  // joint capture issuer must be connected before a mixed component can pass.
  if model_template_requires_slots(template) ||
    @json.object_field(observation.value, "model_slot_capture_cids") is Some(_) {
    return Err(RunEvidenceReferenceMismatch("model_slot_capture_cids"))
  }
  match verify_content_invocation_observation(template, observation, expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  issue_run_invocation_owned(
    template, observation, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn verify_content_invocation_observation(
  template : RunEvidenceValue,
  observation : RunEvidenceValue,
  expected : Array[BoundContentGeneration],
) -> Result[Unit, RunEvidenceValueIssue] {
  if !content_template_requires_generation(template) ||
    expected.is_empty() ||
    observation.name != "observation_set" {
    return Err(RunEvidenceReferenceMismatch("content_generation_cids"))
  }
  guard @json.object_field(observation.value, "content_generation_cids")
    is Some(@json.Array(identities)) &&
    @json.array_count(identities) == expected.length() else {
    return Err(RunEvidenceReferenceMismatch("content_generation_cids"))
  }
  guard @json.object_field(observation.value, "replayability") is Some(replay) &&
    @json.object_field(replay, "materialized") is Some(@json.Bool(true)) &&
    @json.object_field(replay, "availability_evidence_cids")
    is Some(@json.Array(availability)) &&
    @json.array_count(availability) == expected.length() else {
    return Err(RunEvidenceReferenceMismatch("content_generation.availability"))
  }
  let nodes : Map[String, Bool] = Map([])
  for index, generation in expected {
    guard bound_content_generation_value(generation) is Some(evidence) &&
      generation.template.identity == template.identity &&
      contract_string_from_value(evidence.value, "node_id") is Some(node) &&
      content_generation_observation_policy_matches(generation, observation) &&
      optional_string(@json.array_at(identities, index)) ==
      Some(evidence.identity) &&
      !nodes.contains(node) else {
      return Err(RunEvidenceReferenceMismatch("content_generation_cids"))
    }
    if optional_string(@json.array_at(availability, index)) !=
      bound_content_generation_availability(generation) {
      return Err(
        RunEvidenceReferenceMismatch("content_generation.availability"),
      )
    }
    nodes[node] = true
  }
  Ok(())
}

///|
/// Neither dedicated issuer supplies the other component's evidence. This
/// joint path requires both complete opaque inventories under one template;
/// saved JSON, equal CIDs or a successful physical call cannot substitute.
pub fn issue_content_model_run_invocation(
  template : RunEvidenceValue,
  observation : RunEvidenceValue,
  models : Array[BoundModelSlotCapture],
  generations : Array[BoundContentGeneration],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, RunEvidenceValueIssue] {
  match
    verify_content_invocation_observation(template, observation, generations) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match verify_model_invocation_observation(template, observation, models) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  issue_run_invocation_owned(
    template, observation, max_wire_bytes, max_nodes, max_depth,
  )
}
