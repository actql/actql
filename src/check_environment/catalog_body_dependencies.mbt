///|
pub(all) enum CatalogBodyAdmission {
  ValueBody(ContractBodyDependencies)
  CarrierBody(CarrierSchema)
  DataPolicyBody(SourceDataPolicy)
  LookupFactsBody(LookupFacts)
  ListingFactsBody(LookupFacts, FileListProfile)
  ContentFactsBody(LookupFacts, FileContentProfile)
  RelationKeysFactsBody(
    SourceRelationKeys,
    LookupFacts,
    FileListProfile?,
    FileContentProfile?
  )
  RelationScoresFactsBody(SourceRelationScores, SourceRelationKeys?, LookupFacts, FileListProfile?, FileContentProfile?)
  PushdownBody(PushdownContract)
}

///|
pub(all) enum CatalogBodyDependencyRole {
  GoverningGrammar
  ValueGrammar
  GraphIdentityLaw
  GraphValueLaw
  RelationLaws
  ExpressionContract
} derive(Eq, Debug)

///|
pub struct CatalogBodyDependency {
  role : CatalogBodyDependencyRole
  cid : String
}

///|
struct CatalogBodyDependencies {
  envelope : ContractEnvelope
  admission : CatalogBodyAdmission
}

///|
/// Direct dependencies of an admitted body, not the complete Unit closure.
/// No arbitrary body strings or unrecognized grammar are treated as references.
pub fn check_catalog_body_dependencies(
  schemas : CarrierSchemas,
  envelope : ContractEnvelope,
) -> Result[CatalogBodyDependencies, BodyDependencyIssue] {
  let values = schemas.modes.shapes.values
  if !physical_equal(
      member_environment(envelope.item),
      values.policies.references.contents.registry.environment,
    ) {
    return Err(ForeignEnvironment)
  }
  let admission = match envelope.kind {
    "carrier_schema" =>
      match carrier_schema_for(schemas, envelope) {
        Some(schema) => CarrierBody(schema)
        None => return Err(MissingBodyAdmission)
      }
    "data_policy" =>
      match values.policies.by_cid.get(envelope.cid) {
        Some(policy) => DataPolicyBody(policy)
        None => return Err(MissingBodyAdmission)
      }
    _ =>
      match check_body_dependencies(values, envelope) {
        Ok(dependencies) => ValueBody(dependencies)
        Err(issue) => return Err(issue)
      }
  }
  Ok({ envelope, admission, })
}

///|
/// Lookup admission covers only its known component, not arbitrary fact
/// extensions. Refuse a complete-body interpretation if other members exist.
pub fn check_lookup_body_dependencies(
  facts : LookupCapacities,
  envelope : ContractEnvelope,
) -> Result[CatalogBodyDependencies, BodyDependencyIssue] {
  if !physical_equal(
      member_environment(envelope.item),
      facts.references.contents.registry.environment,
    ) {
    return Err(ForeignEnvironment)
  }
  if envelope.kind != "carrier_facts" {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  guard facts.by_cid.get(envelope.cid) is Some(admitted) else {
    return Err(MissingBodyAdmission)
  }
  let known = if admitted.capacity is Some(_) { 1 } else { 0 }
  if @decode.object_length(envelope.body) != Some(known) {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  Ok({ envelope, admission: LookupFactsBody(admitted), })
}

///|
/// A selected Relation key component retains its original SourceView/schema.
/// Existing lookup/file components are admitted by their own owners. Unknown
/// extensions remain unsupported as a complete body, without closing facts.
pub fn check_relation_key_body_dependencies(
  requests : SourceRequestContracts,
  view : SourceViewRequestContract,
  facts : LookupCapacities,
  envelope : ContractEnvelope,
) -> Result[CatalogBodyDependencies, BodyDependencyIssue] {
  let environment = member_environment(envelope.item)
  if !physical_equal(environment, member_environment(view.item)) ||
    !physical_equal(environment, facts.references.contents.registry.environment) ||
    source_request_for(requests, view.item) is None {
    return Err(ForeignEnvironment)
  }
  if envelope.kind != "carrier_facts" {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  guard source_view_carrier(requests.carriers, view.item) is Some(carrier) &&
    carrier.relation_keys is Some(keys) &&
    physical_equal(keys.facts.envelope, envelope) &&
    facts.by_cid.get(envelope.cid) is Some(admitted) else {
    return Err(MissingBodyAdmission)
  }
  let mut known = 1 + (if admitted.capacity is Some(_) { 1 } else { 0 })
  if carrier.relation_scores is Some(_) {
    return check_relation_score_body_dependencies(requests, view, facts, envelope)
  }
  if view.file_listing is Some(profile) {
    if profile.facts_cid != envelope.cid {
      return Err(MissingBodyAdmission)
    }
    known += 1
  }
  if view.file_content is Some(profile) {
    if profile.facts_cid != envelope.cid {
      return Err(MissingBodyAdmission)
    }
    known += 1
  }
  if @decode.object_length(envelope.body) != Some(known) {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  Ok({
    envelope,
    admission: RelationKeysFactsBody(
      keys,
      admitted,
      view.file_listing,
      view.file_content,
    ),
  })
}

///|
/// Interpret the complete selected facts body through its original owners.
/// Empty score maps contribute a known facet but no ranking assertion.
pub fn check_relation_score_body_dependencies(
  requests : SourceRequestContracts,
  view : SourceViewRequestContract,
  facts : LookupCapacities,
  envelope : ContractEnvelope,
) -> Result[CatalogBodyDependencies, BodyDependencyIssue] {
  let environment = member_environment(envelope.item)
  if !physical_equal(environment, member_environment(view.item)) ||
    !physical_equal(environment, facts.references.contents.registry.environment) ||
    source_request_for(requests, view.item) is None {
    return Err(ForeignEnvironment)
  }
  if envelope.kind != "carrier_facts" { return Err(UnsupportedBodyGrammar(envelope.kind)) }
  guard source_view_carrier(requests.carriers, view.item) is Some(carrier) &&
    carrier.relation_scores is Some(scores) &&
    physical_equal(scores.facts.envelope, envelope) &&
    facts.by_cid.get(envelope.cid) is Some(admitted) else {
    return Err(MissingBodyAdmission)
  }
  let mut known = 1 + (if admitted.capacity is Some(_) { 1 } else { 0 })
  if carrier.relation_keys is Some(keys) {
    if !physical_equal(keys.facts.envelope, envelope) { return Err(MissingBodyAdmission) }
    known += 1
  }
  if view.file_listing is Some(profile) {
    if profile.facts_cid != envelope.cid { return Err(MissingBodyAdmission) }
    known += 1
  }
  if view.file_content is Some(profile) {
    if profile.facts_cid != envelope.cid { return Err(MissingBodyAdmission) }
    known += 1
  }
  if @decode.object_length(envelope.body) != Some(known) {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  Ok({ envelope, admission: RelationScoresFactsBody(
    scores, carrier.relation_keys, admitted, view.file_listing, view.file_content,
  ), })
}

///|
/// Interpret only a listing component already checked against this exact
/// SourceView's Request and output schema. A matching CID in another admitted
/// environment cannot substitute its owner. Unknown fact extensions stay refused.
pub fn check_listing_body_dependencies(
  requests : SourceRequestContracts,
  view : SourceViewRequestContract,
  facts : LookupCapacities,
  envelope : ContractEnvelope,
) -> Result[CatalogBodyDependencies, BodyDependencyIssue] {
  let environment = member_environment(envelope.item)
  if !physical_equal(environment, member_environment(view.item)) ||
    !physical_equal(environment, facts.references.contents.registry.environment) ||
    source_request_for(requests, view.item) is None {
    return Err(ForeignEnvironment)
  }
  if envelope.kind != "carrier_facts" {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  guard facts.by_cid.get(envelope.cid) is Some(admitted) &&
    view.file_listing is Some(profile) &&
    profile.facts_cid == envelope.cid else {
    return Err(MissingBodyAdmission)
  }
  let known = 1 + (if admitted.capacity is Some(_) { 1 } else { 0 })
  if @decode.object_length(envelope.body) != Some(known) {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  Ok({ envelope, admission: ListingFactsBody(admitted, profile), })
}

///|
pub fn catalog_body_contract(v : CatalogBodyDependencies) -> ContractEnvelope {
  v.envelope
}

///|
/// Only the exact SourceView-owned strict capture profile discharges this
/// complete carrier-facts body. Uninterpreted extensions remain refused.
pub fn check_content_body_dependencies(
  requests : SourceRequestContracts,
  view : SourceViewRequestContract,
  facts : LookupCapacities,
  envelope : ContractEnvelope,
) -> Result[CatalogBodyDependencies, BodyDependencyIssue] {
  let environment = member_environment(envelope.item)
  if !physical_equal(environment, member_environment(view.item)) ||
    !physical_equal(environment, facts.references.contents.registry.environment) ||
    source_request_for(requests, view.item) is None {
    return Err(ForeignEnvironment)
  }
  if envelope.kind != "carrier_facts" {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  guard facts.by_cid.get(envelope.cid) is Some(admitted) &&
    admitted.capacity is Some(_) &&
    view.file_content is Some(profile) &&
    profile.facts_cid == envelope.cid else {
    return Err(MissingBodyAdmission)
  }
  if @decode.object_length(envelope.body) != Some(2) {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  Ok({ envelope, admission: ContentFactsBody(admitted, profile), })
}

///|
pub fn check_pushdown_body_dependencies(
  contracts : PushdownContracts,
  envelope : ContractEnvelope,
) -> Result[CatalogBodyDependencies, BodyDependencyIssue] {
  if !physical_equal(
      member_environment(envelope.item),
      contracts.shapes.values.policies.references.contents.registry.environment,
    ) {
    return Err(ForeignEnvironment)
  }
  if envelope.kind != "pushdown" {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  match contracts.by_cid.get(envelope.cid) {
    Some(body) => Ok({ envelope, admission: PushdownBody(body), })
    None => Err(MissingBodyAdmission)
  }
}

///|
pub fn catalog_body_admission(
  v : CatalogBodyDependencies,
) -> CatalogBodyAdmission {
  v.admission
}

///|
/// Reference roles remain separate even when both Graph law CIDs are equal.
pub fn catalog_body_dependency_count(v : CatalogBodyDependencies) -> Int {
  match v.admission {
    ValueBody(_)
    | DataPolicyBody(_)
    | LookupFactsBody(_)
    | ListingFactsBody(_, _)
    | ContentFactsBody(_, _)
    | RelationKeysFactsBody(_, _, _, _)
    | RelationScoresFactsBody(_, _, _, _, _) => 1
    PushdownBody(body) =>
      1 +
      (if body.operations.length() > 0 { 1 } else { 0 }) +
      (if body.operations.contains("filter") { 1 } else { 0 })
    CarrierBody(schema) =>
      match @carrier.kind(schema.carrier) {
        RelationKind | EventsKind | VectorsKind => 2
        GraphKind => 4
      }
  }
}

///|
/// Constant-time access without copying fields or traversing a checked type.
pub fn catalog_body_dependency_at(
  v : CatalogBodyDependencies,
  index : Int,
) -> CatalogBodyDependency? {
  if index < 0 || index >= catalog_body_dependency_count(v) {
    return None
  }
  match v.admission {
    ValueBody(value) =>
      Some({
        role: GoverningGrammar,
        cid: body_dependency_at(value, 0).unwrap(),
      })
    DataPolicyBody(_)
    | LookupFactsBody(_)
    | ListingFactsBody(_, _)
    | ContentFactsBody(_, _)
    | RelationKeysFactsBody(_, _, _, _)
    | RelationScoresFactsBody(_, _, _, _, _) =>
      Some({ role: GoverningGrammar, cid: catalog_body_grammar_cid(), })
    PushdownBody(_) =>
      match index {
        0 => Some({ role: GoverningGrammar, cid: catalog_body_grammar_cid(), })
        1 => Some({ role: RelationLaws, cid: pushdown_relation_laws_cid(), })
        _ =>
          Some({
            role: ExpressionContract,
            cid: pushdown_expression_contract_cid(),
          })
      }
    CarrierBody(_) =>
      match index {
        0 => Some({ role: GoverningGrammar, cid: catalog_body_grammar_cid(), })
        1 => Some({ role: ValueGrammar, cid: protocol_value_grammar_cid(), })
        2 => Some({ role: GraphIdentityLaw, cid: @graph.law_cid(), })
        _ => Some({ role: GraphValueLaw, cid: @graph.law_cid(), })
      }
  }
}
