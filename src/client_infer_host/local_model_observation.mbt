///|
/// A borrowed semantic projection of the actual accepted Model. The caller
/// retains its existing OutputUse and complete observation issuer; this token
/// neither acquires another output use nor authenticates Store custody.
pub struct LocalModelObservation {
  held : OutputUse
  issued : ObservationIssuance
  body : @publication.CapturedEffectDependencyBody
}

///|
/// Borrow the original unfiltered Model outcomes through the SAME accepted
/// invocation binding used by the installed publisher. A Result suffix is not
/// this relation; the existing output use and issuer retain its lifetime.
pub fn invocation_binding_original_model_outcomes(
  binding : InvocationBinding,
) -> @relation.CompletedOutput? {
  guard binding.issuance is Some(issued) &&
    binding.output_use.owner.plan is Some(plan) &&
    original_local_model_observation_current(binding.output_use, issued) else {
    return None
  }
  borrow_original_model_observation_relations(
    binding.output_use,
    issued.state.compiled,
    issued.state.definition,
    plan,
  ).map(pair => pair.1)
}

///|
/// Immutable original checked coordinates, alongside the same live Model
/// observation. The task and Unit are distinct and are never inferred from
/// a Source's position in a JavaScript array.
pub fn original_local_model_observation_coordinates(
  value : LocalModelObservation,
) -> (Int, Int, Int)? {
  if !original_local_model_observation_current(value.held, value.issued) {
    return None
  }
  Some(
    @publication_host.client_infer_occurrence_coordinates(
      value.held.owner.occurrence,
    ),
  )
}

///|
/// Connect the installed binding to the existing Model observation owner.
/// The receipt must be the complete original outcome export; the input comes
/// from its first checked CallScope scan. No Source/Model is read again, and
/// neither raw body DATA nor a filtered Result can stand in for this receipt.
pub fn issue_invocation_binding_original_model_observation(
  binding : InvocationBinding,
  outcome_receipt : @relation.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> LocalModelObservation? {
  guard binding.issuance is Some(issued) else { return None }
  issue_original_local_model_observation_from_scope(
    binding.output_use,
    issued,
    outcome_receipt,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Actual outcome scan controls before allocation. The installed caller must
/// back this extent on its SAME terminal Model publication borrow first.
pub fn invocation_binding_original_model_identity_start_capacity(
  binding : InvocationBinding,
) -> @relation.ExecutionCapacity? {
  invocation_binding_original_model_outcomes(binding).bind(outcomes => {
    @relation.completed_relation_identity_scan_start_construction_capacity(
      outcomes,
      retain_body=true,
    )
  })
}

///|
/// Scan the original unfiltered outcomes under that execution's existing
/// row/value/wire/work bounds. The original input identity is not scanned.
pub fn start_invocation_binding_original_model_identity(
  binding : InvocationBinding,
) -> Result[
  @relation.CompletedRelationIdentityScan,
  @relation.CompletedExportIssue,
] {
  guard invocation_binding_original_model_outcomes(binding) is Some(outcomes) else {
    return Err(Unavailable)
  }
  let limits = binding.output_use.owner.limits
  @relation.start_completed_relation_identity_scan(
    outcomes,
    limits.output_rows,
    limits.output_values,
    limits.identity.wire,
    limits.identity.logical_wire,
    limits.identity.schema,
    limits.identity.work,
    limits.identity.workspace,
    incremental_metadata=true,
    retain_body=true,
  )
}

///|
/// Closed eight-member observation metadata, beside the retained outcome
/// scan/body. The existing shared writer/representation recipes price the
/// actual original CID strings; byte DATA is not funding or permission.
pub fn invocation_binding_original_model_observation_capacity(
  binding : InvocationBinding,
  receipt : @relation.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
) -> @relation.ExecutionCapacity? {
  guard max_wire_bytes >= 0 &&
    binding.output_use.owner.call_scope is Some(scope) &&
    @publication.model_input_artifact_relation_identities(
      @publication_host.client_infer_call_scope_artifact(scope),
    )
    is Some((logical, schema)) else {
    return None
  }
  let (unit, _) = @publication_host.client_infer_call_scope_local_coordinate(
    scope,
  )
  let outcome = @relation.logical_relation_cid(
    @relation.completed_relation_export_identity(receipt),
  )
  let outcome_schema = @relation.relation_schema_cid(
    @relation.completed_relation_export_schema_identity(receipt),
  )
  let strings = unit.length().to_int64() +
    logical.length().to_int64() +
    schema.length().to_int64() +
    outcome.length().to_int64() +
    outcome_schema.length().to_int64() +
    71L
  let bytes = Int64::min(max_wire_bytes.to_int64(), 512L + 6L * strings).to_int()
  guard @encode.hash_writer_construction_inventory(9, 1) is Some(hash) &&
    @encode.text_writer_construction_inventory(bytes, 9, 1) is Some(text) &&
    @relation.preparation_execution_capacity({
      retained: {
        record_headers: 6L + hash.record_headers + text.record_headers,
        reference_slots: 16L + hash.reference_slots + text.reference_slots,
        // The existing JS Model observation also retains its already-read
        // task and step beside Unit for optional failure diagnostics.
        scalar_words: 10L + hash.scalar_words + text.scalar_words,
        owned_utf16_units: hash.owned_utf16_units + text.owned_utf16_units,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(writers) else {
    return None
  }
  @input.installed_json_effect_request_construction_capacity(
    writers, bytes, 9, 1,
  )
}

///|
fn original_local_model_observation_current(
  held : OutputUse,
  issued : ObservationIssuance,
) -> Bool {
  !issued.reclaimed &&
  issued.accepted &&
  issued.state.owners.any(owner => physical_equal(owner, held.owner)) &&
  held.owner.plan is Some(plan) &&
  original_host_output_matches(
    held,
    issued.state.compiled,
    issued.state.definition,
    plan,
  ) &&
  observation_issuance_value(issued) is Some(_) &&
  (
    held.owner.saved_call_scope is None ||
    restored_model_observation_scope_current(
      held,
      issued.state.compiled,
      issued.state.definition,
      plan,
    )
  ) &&
  !issued.reclaimed &&
  issued.accepted &&
  original_host_output_matches(
    held,
    issued.state.compiled,
    issued.state.definition,
    plan,
  )
}

///|
/// Borrow both relations of the original live INFER, before the WHERE/Result
/// suffix. Returning the already completed Model output does not execute it
/// again. Saved replay requires its own authenticated original projection.
pub fn borrow_original_live_model_relations(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> (@relation.CompletedOutput, @relation.CompletedOutput)? {
  let active = held.owner
  guard original_host_output_matches(held, compiled, definition, plan) &&
    active.source is Physical(_) &&
    active.saved_call_scope is None &&
    active.call_scope is Some(scope) &&
    active.output is Some(preparation) &&
    @input.client_infer_completed_input(active.input) is Some(input) &&
    @publication_host.client_infer_call_scope_matches(
      scope,
      active.occurrence.owner,
      input,
    ) &&
    @model.complete_model_output(preparation) is Ok(outcomes) &&
    original_host_output_matches(held, compiled, definition, plan) else {
    return None
  }
  let current = () => {
    original_host_output_matches(held, compiled, definition, plan) &&
    @publication_host.client_infer_call_scope_matches(
      scope,
      active.occurrence.owner,
      input,
    ) &&
    original_host_output_matches(held, compiled, definition, plan)
  }
  Some(
    (
      @relation.restrict_completed_output(input, current),
      @relation.restrict_completed_output(outcomes, current),
    ),
  )
}

///|
// The original restored owner authenticates this SAME scope against the
// compiled Run/occurrence/Plan. Fence callbacks with the caller's original
// local completion checks; equal rows or a caller's Saved label grant none.
fn restored_model_observation_scope_current(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> Bool {
  guard held.owner.saved_call_scope is Some(saved) else { return false }
  @publication_host.client_infer_saved_call_scope_matches_originals(
    saved,
    compiled,
    definition,
    held.owner.occurrence,
    plan,
  ) &&
  held.owner.saved_call_scope is Some(current) &&
  physical_equal(saved, current)
}

///|
// A restored, still-live physical Model needs its original unfiltered
// relations too. Keep the public live-only entrance unchanged; this private
// observation projection adds the existing authenticated Saved scope fence.
fn borrow_original_model_observation_relations(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> (@relation.CompletedOutput, @relation.CompletedOutput)? {
  let active = held.owner
  if active.saved_call_scope is None {
    return borrow_original_live_model_relations(
      held, compiled, definition, plan,
    )
  }
  guard original_host_output_matches(held, compiled, definition, plan) &&
    active.source is Physical(_) &&
    active.call_scope is Some(scope) &&
    active.output is Some(preparation) &&
    @input.client_infer_completed_input(active.input) is Some(input) &&
    @publication_host.client_infer_call_scope_matches(
      scope,
      active.occurrence.owner,
      input,
    ) &&
    @model.complete_model_output(preparation) is Ok(outcomes) &&
    restored_model_observation_scope_current(held, compiled, definition, plan) &&
    original_host_output_matches(held, compiled, definition, plan) else {
    return None
  }
  let current = () => {
    original_host_output_matches(held, compiled, definition, plan) &&
    @publication_host.client_infer_call_scope_matches(
      scope,
      active.occurrence.owner,
      input,
    ) &&
    restored_model_observation_scope_current(held, compiled, definition, plan) &&
    original_host_output_matches(held, compiled, definition, plan)
  }
  Some(
    (
      @relation.restrict_completed_output(input, current),
      @relation.restrict_completed_output(outcomes, current),
    ),
  )
}

///|
/// Issue only from exact complete export receipts of this Model's original
/// input and unfiltered outcomes. The existing complete issuer retains all
/// slot/audit/Run evidence outside the semantic preimage. The caller must back
/// these bounded metadata writers before entering, as for local Invocations.
pub fn issue_original_local_model_observation(
  held : OutputUse,
  issued : ObservationIssuance,
  input_receipt : @relation.CompletedRelationExportReceipt,
  outcome_receipt : @relation.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> LocalModelObservation? {
  guard original_local_model_observation_current(held, issued) &&
    held.owner.plan is Some(plan) &&
    held.owner.call_scope is Some(scope) &&
    borrow_original_model_observation_relations(
      held,
      issued.state.compiled,
      issued.state.definition,
      plan,
    )
    is Some((input, outcomes)) &&
    @relation.completed_relation_export_matches_output(input_receipt, input) &&
    @relation.completed_relation_export_matches_output(
      outcome_receipt, outcomes,
    ) &&
    original_local_model_observation_current(held, issued) else {
    return None
  }
  issue_local_model_observation_body(
    held,
    issued,
    scope,
    @relation.logical_relation_cid(
      @relation.completed_relation_export_identity(input_receipt),
    ),
    @relation.relation_schema_cid(
      @relation.completed_relation_export_schema_identity(input_receipt),
    ),
    outcome_receipt,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Reuse the original Scope's already exported input identity. Only the raw
/// Model outcomes need another export for this local projection. No input
/// rows, schema or Model task are re-admitted or hashed a second time.
pub fn issue_original_local_model_observation_from_scope(
  held : OutputUse,
  issued : ObservationIssuance,
  outcome_receipt : @relation.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> LocalModelObservation? {
  guard original_local_model_observation_current(held, issued) &&
    held.owner.plan is Some(plan) &&
    held.owner.call_scope is Some(scope) &&
    borrow_original_model_observation_relations(
      held,
      issued.state.compiled,
      issued.state.definition,
      plan,
    )
    is Some((_, outcomes)) &&
    @relation.completed_relation_export_matches_output(
      outcome_receipt, outcomes,
    ) &&
    @publication.model_input_artifact_relation_identities(
      @publication_host.client_infer_call_scope_artifact(scope),
    )
    is Some((logical, schema)) &&
    original_local_model_observation_current(held, issued) else {
    return None
  }
  issue_local_model_observation_body(
    held, issued, scope, logical, schema, outcome_receipt, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
fn issue_local_model_observation_body(
  held : OutputUse,
  issued : ObservationIssuance,
  scope : @publication_host.ClientInferCallScope,
  input_logical : String,
  input_schema : String,
  outcome_receipt : @relation.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> LocalModelObservation? {
  let (unit, ordinal) = @publication_host.client_infer_call_scope_local_coordinate(
    scope,
  )
  let references = [
    ("input_logical_relation_cid", input_logical),
    ("input_relation_schema_cid", input_schema),
    (
      "outcome_logical_relation_cid",
      @relation.logical_relation_cid(
        @relation.completed_relation_export_identity(outcome_receipt),
      ),
    ),
    (
      "outcome_relation_schema_cid",
      @relation.relation_schema_cid(
        @relation.completed_relation_export_schema_identity(outcome_receipt),
      ),
    ),
  ]
  fn emit(
    writer : @encode.Writer,
    identity : String?,
  ) -> Unit raise @encode.EncodeFailure {
    @encode.begin_object(writer)
    for (name, cid) in references {
      @encode.key(writer, name)
      @encode.string_value(writer, cid)
    }
    if identity is Some(cid) {
      @encode.key(writer, "self_cid")
      @encode.string_value(writer, cid)
    }
    @encode.key(writer, "source_ordinal")
    @encode.number_value(writer, ordinal.to_double())
    @encode.key(writer, "unit_definition_cid")
    @encode.string_value(writer, unit)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-local-model-observation/0.1")
    @encode.end_object(writer)
  }
  try {
    let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth)
    emit(hash, None)
    let identity = "sha256:" + @encode.finish_hash(hash)
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit(writer, Some(identity))
    let wire = @encode.finish(writer)
    guard @publication.admit_local_effect_dependency_body(
        "local_model_observation", wire, max_wire_bytes, max_nodes, max_depth,
      )
      is Ok(body) &&
      original_local_model_observation_current(held, issued) else {
      return None
    }
    Some({ held, issued, body, })
  } catch {
    _ => None
  }
}

///|
/// Availability is tied to the same original output use and observation
/// issuer. Equal body bytes, an unrelated Run or retired context is no grant.
pub fn original_local_model_observation_body(
  value : LocalModelObservation,
) -> @publication.CapturedEffectDependencyBody? {
  if original_local_model_observation_current(value.held, value.issued) {
    Some(value.body)
  } else {
    None
  }
}

///|
/// The normal Model consumer supplies its SAME live output and complete issuer,
/// not a caller-authored semantic body. The publication Host projects only the
/// retained compiler/Scope; this neither executes the Model nor grants Effect
/// publication. The caller backs the bounded metadata writers before entry.
pub fn issue_original_local_model_effect_invocation(
  value : LocalModelObservation,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication_host.ClientEffectLocalInvocation? {
  guard original_local_model_observation_current(value.held, value.issued) &&
    value.held.owner.call_scope is Some(scope) else {
    return None
  }
  let invocation = @publication_host.issue_single_model_client_effect_local_invocation(
    value.issued.state.compiled,
    scope,
    value.body,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).to_option()
  if original_local_model_observation_current(value.held, value.issued) {
    invocation
  } else {
    None
  }
}

///|
/// Original Model input body retained during its FIRST pre-dispatch identity
/// scan. Read only the same input Scope/receipt, with the existing live Model
/// use and complete issuer. No rows, input identity or schema are regenerated.
pub fn original_local_model_observation_input_bodies(
  value : LocalModelObservation,
) -> Array[(String, String)]? {
  guard original_local_model_observation_current(value.held, value.issued) &&
    value.held.owner.identity is Some(scan) &&
    value.held.owner.call_scope is Some(scope) &&
    @relation.completed_relation_identity_scan_body_receipt(scan)
    is Some(receipt) &&
    @relation.completed_relation_identity_scan_body(scan, receipt) is Some(body) &&
    @publication.model_input_artifact_relation_identities(
      @publication_host.client_infer_call_scope_artifact(scope),
    )
    is Some((logical, schema)) &&
    logical ==
    @relation.logical_relation_cid(
      @relation.completed_relation_export_identity(receipt),
    ) &&
    schema ==
    @relation.relation_schema_cid(
      @relation.completed_relation_export_schema_identity(receipt),
    ) else {
    return None
  }
  Some([
    ("relation_value", body),
    (
      "relation_schema",
      @relation.relation_schema_wire(
        @relation.completed_relation_export_schema_identity(receipt),
      ),
    ),
  ])
}

///|
/// Keep each original first-scan body paired with its retained identity. The
/// existing body entrance performs the sole current/Scope/receipt comparison;
/// these following pure projections neither scan nor hash input again.
pub fn original_local_model_observation_input_dependency_bodies(
  value : LocalModelObservation,
) -> Array[(String, String, String)]? {
  guard original_local_model_observation_input_bodies(value) is Some(bodies) &&
    value.held.owner.identity is Some(scan) &&
    @relation.completed_relation_identity_scan_body_receipt(scan)
    is Some(receipt) else {
    return None
  }
  let logical = @relation.logical_relation_cid(
    @relation.completed_relation_export_identity(receipt),
  )
  let schema = @relation.relation_schema_cid(
    @relation.completed_relation_export_schema_identity(receipt),
  )
  Some(
    bodies.map(entry => {
      let (kind, wire) = entry
      (kind, if kind == "relation_value" { logical } else { schema }, wire)
    }),
  )
}

///|
/// Contributing Direct/Whole Source provenance from this SAME accepted Model
/// and its original retained composed inputs. The separate keyed proof is not
/// completed by this projection. No second output use, Source read or issuer.
pub fn issue_original_local_model_direct_source_evidence(
  value : LocalModelObservation,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    @publication_host.ClientEffectLocalInvocation,
    Array[@publication_host.ClientEffectAcquiredEvidence],
  ),
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  guard original_local_model_observation_current(value.held, value.issued) &&
    value.held.owner.call_scope is Some(scope) &&
    value.held.owner.composed_sources is Some(sources) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let result = @publication_host.issue_single_model_client_effect_direct_source_evidence(
    value.issued.state.compiled,
    scope,
    value.body,
    sources,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
  )
  // Static Request emission can call an original Ref current observer. Do not
  // return a semantic projection if that callback retired the actual Model.
  if !original_local_model_observation_current(value.held, value.issued) {
    return Err(Invocation(ForeignCapturedInput))
  }
  result
}
