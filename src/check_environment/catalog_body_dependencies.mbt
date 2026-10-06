///|
pub(all) enum CatalogBodyAdmission {
  ValueBody(ContractBodyDependencies)
  CarrierBody(CarrierSchema)
  DataPolicyBody(SourceDataPolicy)
  LookupFactsBody(LookupFacts)
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
pub fn catalog_body_contract(v : CatalogBodyDependencies) -> ContractEnvelope {
  v.envelope
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
    ValueBody(_) | DataPolicyBody(_) | LookupFactsBody(_) => 1
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
    DataPolicyBody(_) | LookupFactsBody(_) =>
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
