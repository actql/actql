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
    Some(wire) => {
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
      guard retained_explanation_text(view, "compiled_plan_cid") ==
        Some(plan_cid) &&
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
          "explanation_facts", wire, max_bytes, max_nodes, max_depth,
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
      Some(facts)
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
fn retained_explanation_text(
  value : @canonical.CanonicalValue,
  field : String,
) -> String? {
  match @canonical.object_field(value, field) {
    Some(@canonical.String(text)) => Some(text)
    _ => None
  }
}
