///|
/// A borrowed semantic projection of the actual accepted Model. The caller
/// retains its existing OutputUse and complete observation issuer; this token
/// neither acquires a third output use nor authenticates Store custody.
pub struct LocalModelObservation {
  held : OutputUse
  issued : ObservationIssuance
  body : @publication.CapturedEffectDependencyBody
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
    borrow_original_live_model_relations(
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
  let (unit, ordinal) = @publication_host.client_infer_call_scope_local_coordinate(
    scope,
  )
  let references = [
    (
      "input_logical_relation_cid",
      @relation.logical_relation_cid(
        @relation.completed_relation_export_identity(input_receipt),
      ),
    ),
    (
      "input_relation_schema_cid",
      @relation.relation_schema_cid(
        @relation.completed_relation_export_schema_identity(input_receipt),
      ),
    ),
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
