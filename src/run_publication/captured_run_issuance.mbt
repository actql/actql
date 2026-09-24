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
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity,
  plan_values : Array[(String, String)],
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
    advances,
    authoring,
    models,
    Some(preview),
    plan_values,
    max_wire_bytes,
    max_nodes,
    max_depth,
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
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity?,
  plan_values : Array[(String, String)],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
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
  let effect_context = match
    seal_effect_context(
      ordered_snapshots, advances, authoring, ordered_models, preview, plans, max_wire_bytes,
      max_nodes, max_depth,
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
