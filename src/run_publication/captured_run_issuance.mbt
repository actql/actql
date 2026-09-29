///|
/// Exact logical rows and field order for one Result occurrence captured from
/// the same immutable export that issued its Result Artifact. This is private
/// Run evidence, not a caller-authored replacement for a retained Result.
struct CapturedResultSnapshot {
  name : String
  definition : PublicationContract
  artifact : PublicationContract
  rows : @json.CanonicalValue
  fields : Array[String]
}

///|
/// A private Effect-source artifact and an independent Store holding. The
/// artifact describes the checked Stage Result, not a published Program
/// Result. Store availability is checked separately at publication commit.
struct CapturedEffectSourceArtifact {
  effect_id : String
  artifact : PublicationContract
  holding_cid : String
}

///|
pub fn captured_effect_source_holding_cid(
  source : CapturedEffectSourceArtifact,
) -> String {
  source.holding_cid
}

///|
pub fn captured_effect_source_artifact_cid(
  source : CapturedEffectSourceArtifact,
) -> String {
  source.artifact.identity
}

///|
pub fn captured_effect_source_store_authority_cid(
  source : CapturedEffectSourceArtifact,
) -> String {
  contract_string(source.artifact, "store_authority_cid").unwrap()
}

///|
/// Compare facts established by one completed export across the local
/// semantic Artifact and the Run-bound physical Effect source. The caller
/// must also prove that the local Artifact has the exact checked owner.
pub fn captured_effect_source_matches_result_facts(
  source : CapturedEffectSourceArtifact,
  result : PublicationContract,
  result_name : String,
) -> Bool {
  effect_source_contract_matches_result_facts(
    source.artifact,
    result,
    result_name,
  )
}

///|
fn effect_source_contract_matches_result_facts(
  physical : PublicationContract,
  result : PublicationContract,
  result_name : String,
) -> Bool {
  if physical.name != "effect_source_artifact" ||
    result.name != "result_artifact" ||
    contract_string(physical, "source_result") != Some(result_name) ||
    contract_string(physical, "actual_completeness") != Some("complete") ||
    contract_string(result, "actual_completeness") != Some("complete") {
    return false
  }
  for
    field in [
      "logical_result_cid", "result_schema_cid", "effective_data_policy_cid", "effective_retention_policy_cid",
    ] {
    if contract_string(physical, field) != contract_string(result, field) {
      return false
    }
  }
  contract_count(physical, "actual_row_count") ==
  contract_count(result, "actual_row_count")
}

///|
/// One admitted source-state update staged by the captured observation. It is
/// embedded only after its ObservationSet and checkpoint value identity agree.
struct PendingSourceStateAdvance {
  value : @json.CanonicalValue
}

///|
pub(all) enum CapturedRunIssuanceIssue {
  CaptureIssuanceWrongContract(String)
  CaptureIssuanceReferenceMismatch(String)
  CaptureIssuanceInventoryMismatch(String)
  CaptureIssuanceInvalidRows(String)
  CaptureIssuanceInvalidFields(String)
  CaptureIssuanceInvalidSourceAdvance
  CaptureIssuanceEncoding
  CaptureIssuanceContract(PublicationContractIssue)
  CaptureIssuanceChain(RunEvidenceChainIssue)
} derive(Eq, Debug)

///|
fn canonical_string_array(
  values : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @json.CanonicalValue? {
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return None
  }
  try {
    @encode.begin_array(writer)
    for value in values {
      @encode.string_value(writer, value)
    }
    @encode.end_array(writer)
  } catch {
    _ => return None
  }
  let wire = @encode.finish(writer) catch { _ => return None }
  match parse_contract_wire(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn captured_relation_cid(
  rows : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return None
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "sort")
    @encode.string_value(writer, "relation")
    @encode.key(writer, "value")
    @json.emit_value(rows, writer)
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}

///|
fn captured_fields_valid(
  rows : Array[@json.CanonicalValue],
  fields : Array[String],
) -> Bool {
  let seen : Array[String] = []
  for field in fields {
    if field.is_empty() || seen.contains(field) {
      return false
    }
    guard @canonical.normalize_nfc_lf(field) is Ok(normalized) else {
      return false
    }
    if normalized != field {
      return false
    }
    seen.push(field)
  }
  let expected = fields.copy()
  expected.sort_by(@canonical.compare_utf16)
  for row in rows {
    guard object_fields(row) is Ok(entries) else { return false }
    let actual = entries.map(entry => entry.0)
    if actual != expected {
      return false
    }
  }
  true
}

///|
/// Inspect a bounded, canonical ordered-row payload at its physical holder.
/// This establishes a logical Relation CID from bytes; the caller must still
/// bind the checked fields, schema, Result Definition and Store custody before
/// issuing any publication or read grant.
pub fn inspect_canonical_result_rows(
  rows_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, Int), CapturedRunIssuanceIssue] {
  let rows = match
    parse_contract_wire(rows_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(CaptureIssuanceInvalidRows("payload"))
  }
  guard rows is @json.Array(frozen) else {
    return Err(CaptureIssuanceInvalidRows("payload"))
  }
  let row_values = @json.array_values(frozen)
  let canonical = @json.stringify_value(
    rows, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  if canonical != rows_wire {
    return Err(CaptureIssuanceInvalidRows("payload"))
  }
  if !captured_fields_valid(row_values, fields) {
    return Err(CaptureIssuanceInvalidFields("payload"))
  }
  guard captured_relation_cid(rows, max_wire_bytes, max_nodes, max_depth)
    is Some(logical_cid) else {
    return Err(CaptureIssuanceEncoding)
  }
  Ok((logical_cid, row_values.length()))
}

///|
/// Admit the exact canonical row array produced by a checked Result export.
/// The logical Relation CID and row count must equal the already issued
/// Artifact, so arbitrary JSON cannot become Captured Run evidence.
pub fn admit_captured_result_snapshot(
  definition : PublicationContract,
  artifact : PublicationContract,
  rows_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedResultSnapshot, CapturedRunIssuanceIssue] {
  if definition.name != "result_definition" ||
    artifact.name != "result_artifact" {
    return Err(CaptureIssuanceWrongContract("result"))
  }
  guard contract_string(definition, "result_name") is Some(name) else {
    return Err(CaptureIssuanceInvalidFields("result_name"))
  }
  if contract_string(artifact, "result_definition_cid") !=
    Some(definition.identity) {
    return Err(CaptureIssuanceReferenceMismatch("result_definition_cid"))
  }
  let rows = match
    parse_contract_wire(rows_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(CaptureIssuanceInvalidRows(name))
  }
  guard rows is @json.Array(frozen) else {
    return Err(CaptureIssuanceInvalidRows(name))
  }
  let row_values = @json.array_values(frozen)
  let canonical = @json.stringify_value(
    rows, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  if canonical != rows_wire {
    return Err(CaptureIssuanceInvalidRows(name))
  }
  if !captured_fields_valid(row_values, fields) {
    return Err(CaptureIssuanceInvalidFields(name))
  }
  if contract_count(artifact, "actual_row_count") !=
    Some(row_values.length().to_int64()) {
    return Err(CaptureIssuanceReferenceMismatch("actual_row_count"))
  }
  guard captured_relation_cid(rows, max_wire_bytes, max_nodes, max_depth)
    is Some(logical_cid) else {
    return Err(CaptureIssuanceEncoding)
  }
  if contract_string(artifact, "logical_result_cid") != Some(logical_cid) {
    return Err(CaptureIssuanceReferenceMismatch("logical_result_cid"))
  }
  Ok({ name, definition, artifact, rows, fields: fields.copy(), })
}

///|
/// Bind one retained Stage Result artifact to the exact Preview member. This
/// admission does not turn a caller-supplied CID into physical Store custody.
pub fn admit_captured_effect_source_artifact(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  artifact : PublicationContract,
  store_authority_cid : String,
) -> Result[CapturedEffectSourceArtifact, CapturedRunIssuanceIssue] {
  guard effect_preview_member_effect_id(preview, member_index)
    is Some(effect_id) &&
    effect_preview_member_source_result(preview, member_index)
    is Some(source_result) &&
    effect_preview_member_source_binding_cid(preview, member_index)
    is Some(source_binding_cid) &&
    effect_preview_member_result_artifact_cid(preview, member_index)
    is Some(artifact_cid) else {
    return Err(CaptureIssuanceInventoryMismatch("effect_source_artifacts"))
  }
  if invocation.name != "run_invocation" ||
    artifact.name != "effect_source_artifact" ||
    artifact.identity != artifact_cid ||
    contract_string(artifact, "store_authority_cid") !=
    Some(store_authority_cid) ||
    contract_string(artifact, "source_result") != Some(source_result) ||
    contract_string(artifact, "source_binding_cid") != Some(source_binding_cid) ||
    contract_string(artifact, "invocation_cid") != Some(invocation.identity) {
    return Err(CaptureIssuanceReferenceMismatch("effect_source_artifact"))
  }
  guard effect_source_artifact_holding_cid(
      artifact,
      effect_id,
      preview.run_identity_cid,
      store_authority_cid,
    )
    is Some(holding_cid) else {
    return Err(CaptureIssuanceReferenceMismatch("effect_source_holding"))
  }
  Ok({ effect_id, artifact, holding_cid, })
}

///|
/// Admit one exact pending checkpoint update. This does not commit source
/// state; it only fixes the evidence later consumed by the source-state CAS.
pub fn admit_pending_source_state_advance(
  complete_wire : String,
  observation : RunEvidenceValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PendingSourceStateAdvance, CapturedRunIssuanceIssue] {
  if observation.name != "observation_set" {
    return Err(CaptureIssuanceWrongContract("observation_set"))
  }
  let value = match
    parse_contract_wire(complete_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(CaptureIssuanceInvalidSourceAdvance)
  }
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  if canonical != complete_wire {
    return Err(CaptureIssuanceInvalidSourceAdvance)
  }
  guard object_fields(value) is Ok(fields) && fields.length() == 6 else {
    return Err(CaptureIssuanceInvalidSourceAdvance)
  }
  for
    field in [
      "requirement_cid", "checkpoint_contract_cid", "next_checkpoint_value_cid",
      "observation_set_cid",
    ] {
    guard optional_string(@json.object_field(value, field)) is Some(cid) &&
      valid_contract_cid(cid) else {
      return Err(CaptureIssuanceInvalidSourceAdvance)
    }
  }
  guard @json.object_field(value, "previous_generation")
    is Some(previous_generation) &&
    valid_safe_count(previous_generation) &&
    @json.object_field(value, "next_checkpoint_value") is Some(next_value) else {
    return Err(CaptureIssuanceInvalidSourceAdvance)
  }
  let expected = @json.cid_value(
    next_value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  if optional_string(@json.object_field(value, "next_checkpoint_value_cid")) !=
    Some(expected) ||
    optional_string(@json.object_field(value, "observation_set_cid")) !=
    Some(observation.identity) {
    return Err(CaptureIssuanceReferenceMismatch("source_state_advance"))
  }
  Ok({ value, })
}

///|
fn captured_snapshot_inventory(
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  snapshots : Array[CapturedResultSnapshot],
) -> Result[Array[CapturedResultSnapshot], CapturedRunIssuanceIssue] {
  if definitions.length() != artifacts.length() ||
    definitions.length() != snapshots.length() {
    return Err(CaptureIssuanceInventoryMismatch("results"))
  }
  let output = snapshots.copy()
  output.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  for index = 0; index < output.length(); index = index + 1 {
    if index > 0 && output[index - 1].name == output[index].name {
      return Err(CaptureIssuanceInventoryMismatch(output[index].name))
    }
    let snapshot = output[index]
    let has_definition = definitions.any(value => {
      value.identity == snapshot.definition.identity
    })
    let has_artifact = artifacts.any(value => {
      value.identity == snapshot.artifact.identity
    })
    if !has_definition || !has_artifact {
      return Err(CaptureIssuanceInventoryMismatch(snapshot.name))
    }
  }
  Ok(output)
}

///|
fn captured_model_evidence(
  receipt : PublicationContract,
  models : Array[RunEvidenceValue],
) -> Result[Array[RunEvidenceValue], CapturedRunIssuanceIssue] {
  let output = models.copy()
  output.sort_by((left, right) => {
    @canonical.compare_utf16(left.identity, right.identity)
  })
  for index = 0; index < output.length(); index = index + 1 {
    if output[index].name != "model_invocation_evidence" ||
      (index > 0 && output[index - 1].identity == output[index].identity) {
      return Err(CaptureIssuanceInventoryMismatch("model_evidence"))
    }
  }
  guard @json.object_field(receipt.value, "external_observation_evidence")
    is Some(@json.Array(frozen)) else {
    return Err(CaptureIssuanceReferenceMismatch("external_observations"))
  }
  let expected : Array[String] = []
  for item in @json.array_values(frozen) {
    if evidence_string(item, "kind") == Some("model_invocation") {
      guard evidence_string(item, "evidence_cid") is Some(cid) else {
        return Err(CaptureIssuanceReferenceMismatch("external_observations"))
      }
      expected.push(cid)
    }
  }
  expected.sort_by(@canonical.compare_utf16)
  if expected != output.map(value => value.identity) {
    return Err(CaptureIssuanceReferenceMismatch("model_evidence"))
  }
  Ok(output)
}

///|
fn seal_effect_context(
  snapshots : Array[CapturedResultSnapshot],
  sources : Array[CapturedEffectSourceArtifact],
  local_sources : Array[CapturedLocalEffectSourceEvidence],
  dependencies : CapturedEffectDependencyInventory,
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity?,
  plans : Array[(String, @json.CanonicalValue)],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, CapturedRunIssuanceIssue] {
  let effect_ids = match preview {
    Some(identity) => identity.member_effect_ids.copy()
    None => []
  }
  effect_ids.sort_by(@canonical.compare_utf16)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authoring_context")
    @json.emit_value(authoring.value, writer)
    @encode.key(writer, "effect_dependency_inventory")
    let inventory = parse_contract_wire(
      dependencies.wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ).unwrap()
    @json.emit_value(inventory, writer)
    @encode.key(writer, "effect_plan_logical_cids")
    @encode.begin_object(writer)
    if preview is Some(identity) {
      for name in effect_ids {
        let mut index = -1
        for position in 0..<identity.member_effect_ids.length() {
          if identity.member_effect_ids[position] == name {
            index = position
            break
          }
        }
        if index >= 0 && identity.member_effect_plan_cids[index] is Some(cid) {
          @encode.key(writer, name)
          @encode.string_value(writer, cid)
        }
      }
    }
    @encode.end_object(writer)
    @encode.key(writer, "effect_plans")
    @encode.begin_object(writer)
    for (name, plan) in plans {
      @encode.key(writer, name)
      @json.emit_value(plan, writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "effects")
    @encode.begin_object(writer)
    for name in effect_ids {
      @encode.key(writer, name)
      @encode.begin_object(writer)
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "effect_source_artifacts")
    @encode.begin_object(writer)
    for source in sources {
      @encode.key(writer, source.effect_id)
      @json.emit_value(source.artifact.value, writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "effect_source_holding_cids")
    @encode.begin_object(writer)
    for source in sources {
      @encode.key(writer, source.effect_id)
      @encode.string_value(writer, source.holding_cid)
    }
    @encode.end_object(writer)
    @encode.key(writer, "effect_source_local_inventory")
    @encode.begin_object(writer)
    for source in local_sources {
      @encode.key(writer, source.effect_id)
      @json.emit_value(source.value, writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "model_invocation_evidence")
    @encode.begin_array(writer)
    for model in models {
      @json.emit_value(model.value, writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "model_invocation_evidence_cids")
    @encode.begin_array(writer)
    for model in models {
      @encode.string_value(writer, model.identity)
    }
    @encode.end_array(writer)
    @encode.key(writer, "pending_source_state_advances")
    @encode.begin_array(writer)
    for advance in advances {
      @json.emit_value(advance.value, writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "result_artifacts")
    @encode.begin_object(writer)
    for snapshot in snapshots {
      @encode.key(writer, snapshot.name)
      @json.emit_value(snapshot.artifact.value, writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "result_fields")
    @encode.begin_object(writer)
    for snapshot in snapshots {
      @encode.key(writer, snapshot.name)
      guard canonical_string_array(
          snapshot.fields,
          max_wire_bytes,
          max_nodes,
          max_depth,
        )
        is Some(fields) else {
        return Err(CaptureIssuanceEncoding)
      }
      @json.emit_value(fields, writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "result_values")
    @encode.begin_object(writer)
    for snapshot in snapshots {
      @encode.key(writer, snapshot.name)
      @json.emit_value(snapshot.rows, writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-effect-context/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  let body_wire = @encode.finish(writer) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  let body = match
    parse_contract_wire(body_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(CaptureIssuanceEncoding)
  }
  let identity = @json.cid_value(body, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  guard @json.object_with_string_field(body, "effect_context_cid", identity)
    is Some(complete) else {
    return Err(CaptureIssuanceEncoding)
  }
  Ok(complete)
}

///|
/// Issue a private Effect-free Captured Run from exact Result snapshots and
/// admitted evidence. The issuer never accepts a preassembled Effect context.
pub fn issue_effect_free_captured_run(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  issue_captured_computation_run(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    snapshots,
    [],
    [],
    advances,
    authoring,
    models,
    None,
    [],
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Issue the Effectful computation capture without claiming apply authority.
/// Plan values are bounded context observations; the physical Plan payload
/// still requires an exact checked output proof before any mutation.
pub fn issue_effectful_captured_run(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  sources : Array[CapturedEffectSourceArtifact],
  local_sources : Array[CapturedLocalEffectSourceEvidence],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity,
  plan_values : Array[(String, String)],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  dependency_inventory? : CapturedEffectDependencyInventory? = None,
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  issue_captured_computation_run(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    snapshots,
    sources,
    local_sources,
    advances,
    authoring,
    models,
    Some(preview),
    plan_values,
    max_wire_bytes,
    max_nodes,
    max_depth,
    dependency_inventory~,
  )
}

///|
fn issue_captured_computation_run(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  sources : Array[CapturedEffectSourceArtifact],
  local_sources : Array[CapturedLocalEffectSourceEvidence],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity?,
  plan_values : Array[(String, String)],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  dependency_inventory? : CapturedEffectDependencyInventory? = None,
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  if authoring.name != "authoring_context" {
    return Err(CaptureIssuanceWrongContract("authoring_context"))
  }
  match
    validate_run_publication_chain(
      run_definition, invocation, definitions, artifacts, manifest, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(CaptureIssuanceChain(EvidenceRoot(issue)))
  }
  if receipt.name != "run_receipt" {
    return Err(CaptureIssuanceWrongContract("run_receipt"))
  }
  guard contract_string(invocation, "observation_set_cid")
    is Some(observation_set_cid) else {
    return Err(CaptureIssuanceReferenceMismatch("observation_set_cid"))
  }
  for advance in advances {
    if optional_string(@json.object_field(advance.value, "observation_set_cid")) !=
      Some(observation_set_cid) {
      return Err(CaptureIssuanceReferenceMismatch("source_state_advance"))
    }
  }
  guard evidence_string(receipt.value, "program_definition_cid")
    is Some(program_definition_cid) else {
    return Err(CaptureIssuanceReferenceMismatch("program_definition_cid"))
  }
  if evidence_string(authoring.value, "program_definition_cid") !=
    Some(program_definition_cid) {
    return Err(CaptureIssuanceReferenceMismatch("authoring_context"))
  }
  let ordered_snapshots = match
    captured_snapshot_inventory(definitions, artifacts, snapshots) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let ordered_sources = sources.copy()
  ordered_sources.sort_by((left, right) => {
    @canonical.compare_utf16(left.effect_id, right.effect_id)
  })
  let ordered_local_sources = local_sources.copy()
  ordered_local_sources.sort_by((left, right) => {
    @canonical.compare_utf16(left.effect_id, right.effect_id)
  })
  if ordered_sources.length() != ordered_local_sources.length() {
    return Err(
      CaptureIssuanceInventoryMismatch("effect_source_local_inventory"),
    )
  }
  for index in 0..<ordered_sources.length() {
    if ordered_sources[index].effect_id !=
      ordered_local_sources[index].effect_id ||
      validate_captured_local_effect_source_value(
        ordered_local_sources[index].value,
        ordered_sources[index].artifact,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Err(_) {
      return Err(
        CaptureIssuanceInventoryMismatch("effect_source_local_inventory"),
      )
    }
  }
  let mut expected_source_count = 0
  match preview {
    None =>
      if !ordered_sources.is_empty() {
        return Err(CaptureIssuanceInventoryMismatch("effect_source_artifacts"))
      }
    Some(identity) => {
      for index in 0..<identity.member_effect_ids.length() {
        if effect_preview_member_source_result(identity, index) is Some(_) {
          expected_source_count += 1
          let matches = ordered_sources.filter(source => {
            source.effect_id == identity.member_effect_ids[index]
          })
          if matches.length() != 1 ||
            matches[0].artifact.identity !=
            effect_preview_member_result_artifact_cid(identity, index).unwrap() {
            return Err(
              CaptureIssuanceInventoryMismatch("effect_source_artifacts"),
            )
          }
        }
      }
      if ordered_sources.length() != expected_source_count {
        return Err(CaptureIssuanceInventoryMismatch("effect_source_artifacts"))
      }
    }
  }
  let ordered_models = match captured_model_evidence(receipt, models) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let plans : Array[(String, @json.CanonicalValue)] = []
  for (name, wire) in plan_values {
    guard preview is Some(identity) && identity.member_effect_ids.contains(name) else {
      return Err(CaptureIssuanceInventoryMismatch("effect_plans"))
    }
    let mut index = -1
    for position in 0..<identity.member_effect_ids.length() {
      if identity.member_effect_ids[position] == name {
        index = position
        break
      }
    }
    if index < 0 ||
      identity.member_effect_plan_cids[index] is None ||
      plans.any(fn(value) { value.0 == name }) {
      return Err(CaptureIssuanceInventoryMismatch("effect_plans"))
    }
    let value = match
      parse_contract_wire(wire, max_wire_bytes, max_nodes, max_depth) {
      Ok(value) => value
      Err(_) => return Err(CaptureIssuanceInvalidRows("effect_plans"))
    }
    plans.push((name, value))
  }
  if preview is Some(identity) {
    let mut expected_plans = 0
    for cid in identity.member_effect_plan_cids {
      if cid is Some(_) {
        expected_plans += 1
      }
    }
    if identity.member_effect_ids.is_empty() || expected_plans != plans.length() {
      return Err(CaptureIssuanceInventoryMismatch("effect_plans"))
    }
  }
  plans.sort_by(fn(left, right) { @canonical.compare_utf16(left.0, right.0) })
  let dependencies = match
    admit_effect_context_dependencies(
      ordered_local_sources.map(source => source.value),
      match dependency_inventory {
        Some(value) => value.wire
        None => "[]"
      },
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(
        CaptureIssuanceInventoryMismatch("effect_dependency_inventory"),
      )
  }
  let effect_context = match
    seal_effect_context(
      ordered_snapshots, ordered_sources, ordered_local_sources, dependencies, advances,
      authoring, ordered_models, preview, plans, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "effect_context")
    @json.emit_value(effect_context, writer)
    @encode.key(writer, "encryption_required")
    @encode.bool_value(writer, true)
    @encode.key(writer, "receipt")
    @json.emit_value(receipt.value, writer)
    @encode.key(writer, "retention_class")
    @encode.string_value(writer, "run-evidence")
    @encode.key(writer, "sensitivity")
    @encode.string_value(writer, "private")
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-captured-run/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  let captured = match
    seal_publication_contract(
      "captured_run", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(CaptureIssuanceContract(issue))
  }
  let validation = match preview {
    None =>
      validate_effect_free_run_evidence_chain(
        run_definition, invocation, definitions, artifacts, manifest, receipt, captured,
        max_wire_bytes, max_nodes, max_depth,
      )
    Some(identity) =>
      validate_effectful_computation_evidence_chain(
        run_definition, invocation, definitions, artifacts, manifest, receipt, captured,
        identity, max_wire_bytes, max_nodes, max_depth,
      )
  }
  match validation {
    Ok(_) => Ok(captured)
    Err(issue) => Err(CaptureIssuanceChain(issue))
  }
}
