///|
pub(all) enum ClientRetainedExplanationIssue {
  ForeignOriginal
  InvalidReadLimits
  Contract(@publication.PublicationContractIssue)
  Evidence(@publication.RunEvidenceValueIssue)
  Encoding(@encode.EncodeFailure)
  ConstructionUnavailable
} derive(Eq, Debug)

///|
// Bounded projection of retained original DATA only. The actual read Owner
// must back parse/validation/map binding/writer overlap BEFORE calling this;
// this function grants neither capacity nor Account/current/egress authority.
// It cannot compile, acquire, execute, or repair absent historical metadata.
pub fn retained_client_run_explanation_view(
  definition : @publication.PublicationContract,
  plan : @publication.PublicationContract?,
  program_cid : String,
  parameters_cid : String,
  plan_view_wire : String?,
  facts_wire : String?,
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_binding? : ((
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
  ) -> Bool)? = None,
) -> Result[String, ClientRetainedExplanationIssue] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidReadLimits)
  }
  guard @publication.publication_contract_run_definition_scope(definition) ==
    Some(namespace_id) &&
    @publication.publication_contract_identity(definition) == definition_cid else {
    return Err(ForeignOriginal)
  }
  let facts = match facts_wire {
    None => None
    Some(wire) =>
      match
        read_retained_explanation_original(
          definition,
          plan,
          program_cid,
          parameters_cid,
          plan_view_wire,
          wire,
          max_bytes,
          max_nodes,
          max_depth,
          before_binding,
          None,
        ) {
        Err(issue) => return Err(issue)
        Ok(facts) => Some(facts)
      }
  }
  let wire = try {
    let w = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(w)
    @encode.key(w, "explanation")
    @encode.begin_object(w)
    match facts {
      Some(value) => {
        @encode.key(w, "facts")
        @canonical.emit_value(value, w)
        @encode.key(w, "state")
        @encode.string_value(w, "projected")
      }
      None => {
        @encode.key(w, "reason")
        @encode.string_value(w, "not_retained")
        @encode.key(w, "state")
        @encode.string_value(w, "not_projected")
      }
    }
    @encode.end_object(w)
    @encode.key(w, "run_ref")
    @encode.begin_object(w)
    @encode.key(w, "authorityScopeCid")
    @encode.string_value(w, authority_scope_cid)
    @encode.key(w, "namespaceId")
    @encode.string_value(w, namespace_id)
    @encode.key(w, "runDefinitionCid")
    @encode.string_value(w, definition_cid)
    @encode.end_object(w)
    @encode.key(w, "version")
    @encode.string_value(w, "actql-run-explanation-view/0.1")
    @encode.end_object(w)
    @encode.finish(w)
  } catch {
    issue => return Err(Encoding(issue))
  }
  // Full closed envelope validation, including every original reference and
  // the structural-only profile. A failed encoding/limit is never absence.
  @publication.parse_interactive_run_control_shape(
    "run_explanation_view", wire, max_bytes, max_nodes, max_depth,
  )
  .map(_ => wire)
  .map_err(issue => Contract(issue))
}

///|
fn read_retained_explanation_original(
  definition : @publication.PublicationContract,
  plan : @publication.PublicationContract?,
  program_cid : String,
  parameters_cid : String,
  plan_view_wire : String?,
  facts_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_binding : ((
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
  ) -> Bool)?,
  view_out : Ref[@canonical.CanonicalValue?]?,
) -> Result[@canonical.CanonicalValue, ClientRetainedExplanationIssue] {
  guard plan is Some(plan) &&
    plan_view_wire is Some(view_wire) &&
    @publication.saved_compiled_plan_matches_definition(
      plan,
      definition,
      Some(program_cid),
    ) else {
    return Err(ForeignOriginal)
  }
  let view = match
    @publication.parse_interactive_run_control_shape(
      "plan_view", view_wire, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(Contract(issue))
    Ok(value) => value
  }
  let plan_cid = @publication.publication_contract_identity(plan)
  guard retained_explanation_text(view, "compiled_plan_cid") == Some(plan_cid) &&
    @canonical.object_field(view, "logical_map") is Some(map) else {
    return Err(ForeignOriginal)
  }
  let map = match
    @publication.admit_interactive_run_evidence_value(
      "logical_map", map, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(Evidence(issue))
    Ok(value) => value
  }
  // The installed read's SAME owner reserves the measured binding work
  // here, after its separately paid codec read but before key constructors.
  // A sizing refusal remains a refusal, never missing historical facts.
  if before_binding is Some(reserve) && !reserve(map, plan) {
    return Err(ConstructionUnavailable)
  }
  match
    @publication.check_interactive_logical_map_binding(
      map, plan, max_bytes, max_nodes, max_depth,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  let facts = match
    @publication.parse_interactive_run_control_shape(
      "explanation_facts", facts_wire, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(Contract(issue))
    Ok(value) => value
  }
  for
    (field, original) in [
      ("compiled_plan_cid", plan_cid),
      ("program_definition_cid", program_cid),
      ("parameter_values_cid", parameters_cid),
      ("logical_map_cid", @publication.run_evidence_value_identity(map)),
    ] {
    if retained_explanation_text(facts, field) != Some(original) {
      return Err(ForeignOriginal)
    }
  }
  if view_out is Some(retained) {
    retained.val = Some(view)
  }
  Ok(facts)
}

///|
/// The parsed and cross-checked members for the additive cold projection.
/// The existing read owner holds construction and disclosure custody.
pub struct ClientRetainedExplanationContext {
  plan : @canonical.CanonicalValue
  facts : @canonical.CanonicalValue
  context : @canonical.CanonicalValue
}

///|
/// Validate the original Context on the same selected Run and logical map.
/// The original Journal verifies the exact retained bytes before this read.
/// A missing companion is historical absence; partial or foreign input refuses.
pub fn retained_client_run_explanation_context(
  definition : @publication.PublicationContract,
  plan : @publication.PublicationContract?,
  program_cid : String,
  parameters_cid : String,
  plan_view_wire : String?,
  facts_wire : String?,
  context_wire : String?,
  invocation_template_wire : String?,
  namespace_id : String,
  definition_cid : String,
  stored_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_binding : (
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
  ) -> Bool,
) -> Result[ClientRetainedExplanationContext?, ClientRetainedExplanationIssue] {
  if stored_bytes < 1 || max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidReadLimits)
  }
  guard @publication.publication_contract_run_definition_scope(definition) ==
    Some(namespace_id) &&
    @publication.publication_contract_identity(definition) == definition_cid else {
    return Err(ForeignOriginal)
  }
  if context_wire is None && invocation_template_wire is None {
    return Ok(None)
  }
  guard context_wire is Some(context_wire) &&
    invocation_template_wire is Some(template_wire) &&
    facts_wire is Some(facts_wire) else {
    return Err(ForeignOriginal)
  }
  let context = match
    @publication.parse_interactive_run_control_shape(
      "explanation_context", context_wire, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(Contract(issue))
    Ok(value) => value
  }
  let template = match
    @publication.admit_run_evidence_value(
      "bound_invocation_template", template_wire, stored_bytes, stored_bytes, 64,
    ) {
    Err(issue) => return Err(Evidence(issue))
    Ok(value) => value
  }
  guard @publication.run_evidence_value_json(template) == template_wire &&
    @publication.saved_run_template_environment(
      template, definition, program_cid, parameters_cid,
    )
    is Some(environment) &&
    @canonical.object_field(context, "binding") is Some(binding) &&
    retained_explanation_text(binding, "check_environment_cid") ==
    Some(environment) else {
    return Err(ForeignOriginal)
  }
  let view_out = Ref(None)
  let facts = match
    read_retained_explanation_original(
      definition,
      plan,
      program_cid,
      parameters_cid,
      plan_view_wire,
      facts_wire,
      max_bytes,
      max_nodes,
      max_depth,
      Some(before_binding),
      Some(view_out),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  for
    field in [
      "compiled_plan_cid", "logical_map_cid", "program_definition_cid", "parameter_values_cid",
    ] {
    if retained_explanation_text(binding, field) !=
      retained_explanation_text(facts, field) {
      return Err(ForeignOriginal)
    }
  }
  guard view_out.val is Some(view) else { return Err(ForeignOriginal) }
  Ok(Some({ plan: view, facts, context, }))
}

///|
fn retained_explanation_text(
  value : @canonical.CanonicalValue,
  field : String,
) -> String? {
  match @canonical.object_field(value, field) {
    Some(@canonical.String(text)) => Some(text)
    _ => None
  }
}
