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
  // Exact bare-row extent from the original successful logical hash.
  row_wire_bytes : Int
  row_nodes : Int
  row_depth : Int
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
  effect_source_contract_matches_relation_facts(
    physical,
    result,
    Result(result_name),
  )
}

///|
/// Match semantic export facts only in the private Table input namespace.
/// A matching name or content in the ordinary Result namespace is insufficient.
pub fn captured_effect_source_matches_table_input_facts(
  source : CapturedEffectSourceArtifact,
  artifact : PublicationContract,
  table_input : String,
) -> Bool {
  effect_source_contract_matches_relation_facts(
    source.artifact,
    artifact,
    TableInput(table_input),
  )
}

///|
fn effect_source_contract_matches_relation_facts(
  physical : PublicationContract,
  result : PublicationContract,
  source : EffectPreviewRelationSource,
) -> Bool {
  if physical.name != "effect_source_artifact" ||
    result.name != "result_artifact" ||
    effect_source_artifact_relation_source(physical) != Some(source) ||
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
    parse_contract_wire(
      rows_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
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
  // Explicit synchronous callers drain the same owner; environments poll it.
  let preparation = match
    start_captured_result_snapshot(
      definition, artifact, rows_wire, fields, max_wire_bytes, max_nodes, max_depth,
      2147483647,
    ) {
    Ok(preparation) => preparation
    Err(issue) => return Err(issue)
  }
  while true {
    match preparation.advance(64) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => return preparation.finish()
      Ok((false, _)) => ()
    }
  } nobreak {
    Err(CaptureIssuanceEncoding)
  }
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
  admit_captured_effect_source_binding(
    preview,
    member_index,
    invocation,
    artifact,
    artifact.identity,
    store_authority_cid,
  )
}

///|
/// A Preview may name the checked semantic Result Artifact while its private
/// holding retains the Run-bound physical Effect-source Artifact. Their exact
/// logical content/schema/measurement must agree; a matching CID is not custody.
pub fn admit_captured_effect_source_from_result(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  artifact : PublicationContract,
  result : PublicationContract,
  store_authority_cid : String,
) -> Result[CapturedEffectSourceArtifact, CapturedRunIssuanceIssue] {
  guard effect_preview_member_source_result(preview, member_index) is Some(name) &&
    effect_source_contract_matches_result_facts(artifact, result, name) else {
    return Err(
      CaptureIssuanceReferenceMismatch("effect_source_result_artifact"),
    )
  }
  admit_captured_effect_source_binding(
    preview,
    member_index,
    invocation,
    artifact,
    result.identity,
    store_authority_cid,
  )
}

///|
/// The private semantic Artifact is admitted under its checked producer and
/// owner by the Host. This binding preserves the typed Preview source and all
/// export facts; it is not proof of durable capture or current Store custody.
pub fn admit_captured_effect_source_from_table_input(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  artifact : PublicationContract,
  table_artifact : PublicationContract,
  store_authority_cid : String,
) -> Result[CapturedEffectSourceArtifact, CapturedRunIssuanceIssue] {
  guard effect_preview_member_source_table_input(preview, member_index)
    is Some(name) &&
    effect_source_contract_matches_relation_facts(
      artifact,
      table_artifact,
      TableInput(name),
    ) else {
    return Err(
      CaptureIssuanceReferenceMismatch("effect_source_table_input_artifact"),
    )
  }
  admit_captured_effect_source_binding(
    preview,
    member_index,
    invocation,
    artifact,
    table_artifact.identity,
    store_authority_cid,
  )
}

///|
fn admit_captured_effect_source_binding(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  artifact : PublicationContract,
  preview_artifact_cid : String,
  store_authority_cid : String,
) -> Result[CapturedEffectSourceArtifact, CapturedRunIssuanceIssue] {
  guard effect_preview_member_effect_id(preview, member_index)
    is Some(effect_id) &&
    effect_preview_member_relation_source(preview, member_index) is Some(source) &&
    effect_preview_member_source_binding_cid(preview, member_index)
    is Some(source_binding_cid) &&
    effect_preview_member_result_artifact_cid(preview, member_index)
    is Some(artifact_cid) else {
    return Err(CaptureIssuanceInventoryMismatch("effect_source_artifacts"))
  }
  if invocation.name != "run_invocation" ||
    artifact.name != "effect_source_artifact" ||
    preview_artifact_cid != artifact_cid ||
    contract_string(artifact, "store_authority_cid") !=
    Some(store_authority_cid) ||
    effect_source_artifact_relation_source(artifact) != Some(source) ||
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
  content_generations? : Array[BoundContentGeneration] = [],
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
    content_generations~,
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
fn prepare_captured_effect_sources(
  inputs : CapturedRunIssuanceInputs,
) -> Result[
  (
    Array[CapturedEffectSourceArtifact],
    Array[CapturedLocalEffectSourceEvidence],
  ),
  CapturedRunIssuanceIssue,
] {
  let {
    sources,
    local_sources,
    preview,
    max_wire_bytes,
    max_nodes,
    max_depth,
    ..
  } = inputs
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
        if effect_preview_member_relation_source(identity, index) is Some(_) {
          expected_source_count += 1
          let matches = ordered_sources.filter(source => {
            source.effect_id == identity.member_effect_ids[index]
          })
          let locals = ordered_local_sources.filter(local_evidence => {
            local_evidence.effect_id == identity.member_effect_ids[index]
          })
          if matches.length() != 1 ||
            locals.length() != 1 ||
            !captured_local_effect_source_matches_preview(
              identity,
              index,
              matches[0].artifact,
              locals[0].value,
              max_wire_bytes,
              max_nodes,
              max_depth,
            ) {
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
  Ok((ordered_sources, ordered_local_sources))
}

///|
fn prepare_captured_context_inputs(
  inputs : CapturedRunIssuanceInputs,
  ordered_snapshots : Array[CapturedResultSnapshot],
  ordered_sources : Array[CapturedEffectSourceArtifact],
  ordered_local_sources : Array[CapturedLocalEffectSourceEvidence],
  ordered_models : Array[RunEvidenceValue],
) -> Result[EffectContextInputs, CapturedRunIssuanceIssue] {
  let {
    advances,
    authoring,
    preview,
    plan_values,
    max_wire_bytes,
    max_nodes,
    max_depth,
    dependency_inventory,
    ..
  } = inputs
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
  Ok({
    snapshots: ordered_snapshots,
    sources: ordered_sources,
    local_sources: ordered_local_sources,
    dependencies,
    advances,
    authoring,
    models: ordered_models,
    content_generations: inputs.content_generations,
    preview,
    plans,
  })
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
  content_generations? : Array[BoundContentGeneration] = [],
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  let workspace = publication_evidence_workspace(max_nodes)
  let preparation = start_captured_computation_preparation(
    {
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
      content_generations,
      preview,
      plan_values,
      max_wire_bytes,
      max_nodes,
      max_depth,
      dependency_inventory,
    },
    workspace,
  )
  while true {
    match preparation.advance(256) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => return preparation.finish()
      Ok((false, _)) => ()
    }
  } nobreak {
    Err(CaptureIssuanceEncoding)
  }
}
