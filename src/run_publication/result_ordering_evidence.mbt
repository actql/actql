///|
/// Result-bound ordering proof accepted by publication. The concrete witness
/// remains a closed acquisition derivation contract; a bare CID cannot create
/// this value or satisfy a Result Artifact dependency.
struct ResultOrderingEvidence {
  derivation : PublicationContract
  ordering : PublicationContract
}

///|
pub(all) enum ResultOrderingEvidenceIssue {
  WrongDefinition
  WrongDerivation
  WrongOrdering
  ProducerMismatch
  LogicalValueMismatch
  SchemaMismatch
  PolicyMismatch
  OrderingMismatch
  WitnessMismatch
  Encoding
} derive(Eq, Debug)

///|
pub(all) enum ResultArtifactEvidenceIssue {
  ArtifactWrongContract
  ArtifactDefinitionMismatch
  ArtifactLogicalValueMismatch
  ArtifactSchemaMismatch
  ArtifactOrderingMismatch
  ArtifactPolicyMismatch
  ArtifactRetentionMismatch
  ArtifactMissingDerivation
  ArtifactEncoding
} derive(Eq, Debug)

///|
pub(all) enum ResultEvidenceSetIssue {
  ResultEvidenceCount
  ResultEvidenceMissingDefinition
  ResultEvidenceMissingDerivation
  ResultEvidenceMissingOrdering
  ResultEvidenceMissingRetention
  ResultEvidenceDuplicate
  ResultEvidenceArtifact(ResultArtifactEvidenceIssue)
  ResultEvidenceOrdering(ResultOrderingEvidenceIssue)
} derive(Eq, Debug)

///|
fn exact_occurrence_order(value : @json.CanonicalValue) -> Bool {
  guard object_fields(value) is Ok(fields) else { return false }
  guard field_value(fields, "terms") is Some(@json.Array(values)) else {
    return false
  }
  fields.length() == 2 &&
  optional_string(field_value(fields, "kind")) == Some("occurrence") &&
  @json.array_values(values).is_empty()
}

///|
fn exact_derivation_witness(value : @json.CanonicalValue, cid : String) -> Bool {
  guard value is @json.Array(values) else { return false }
  let entries = @json.array_values(values)
  if entries.length() != 1 {
    return false
  }
  guard object_fields(entries[0]) is Ok(fields) else { return false }
  fields.length() == 2 &&
  optional_string(field_value(fields, "kind")) == Some("derivation") &&
  optional_string(field_value(fields, "cid")) == Some(cid)
}

///|
/// Admit the initial Result publication ordering profile. It deliberately
/// supports occurrence order only: the exact checked Result export establishes
/// the sequence, and a bound derivation witness proves where that sequence came
/// from. Key-order publication can be added without changing Artifact shape.
pub fn validate_result_occurrence_ordering_evidence(
  definition : PublicationContract,
  derivation : PublicationContract,
  ordering : PublicationContract,
  logical_value_cid : String,
  result_schema_cid : String,
  effective_data_policy_cid : String,
) -> Result[ResultOrderingEvidence, ResultOrderingEvidenceIssue] {
  if definition.name != "result_definition" {
    return Err(WrongDefinition)
  }
  if derivation.name != "derivation_evidence" {
    return Err(WrongDerivation)
  }
  if ordering.name != "ordering_evidence" {
    return Err(WrongOrdering)
  }
  let producer = definition.identity
  if contract_string(derivation, "producer_contract_cid") != Some(producer) ||
    contract_string(ordering, "producer_contract_cid") != Some(producer) {
    return Err(ProducerMismatch)
  }
  if contract_string(derivation, "logical_value_cid") != Some(logical_value_cid) {
    return Err(LogicalValueMismatch)
  }
  if contract_string(derivation, "relation_schema_cid") !=
    Some(result_schema_cid) {
    return Err(SchemaMismatch)
  }
  if contract_string(derivation, "effective_data_policy_cid") !=
    Some(effective_data_policy_cid) {
    return Err(PolicyMismatch)
  }
  guard @json.object_field(derivation.value, "ordering")
    is Some(derivation_order) else {
    return Err(Encoding)
  }
  if !exact_occurrence_order(derivation_order) ||
    contract_string(ordering, "kind") != Some("occurrence") {
    return Err(OrderingMismatch)
  }
  guard @json.object_field(ordering.value, "terms")
    is Some(@json.Array(ordering_terms)) else {
    return Err(Encoding)
  }
  if !@json.array_values(ordering_terms).is_empty() {
    return Err(OrderingMismatch)
  }
  guard @json.object_field(ordering.value, "witness_evidence")
    is Some(witnesses) else {
    return Err(Encoding)
  }
  if !exact_derivation_witness(witnesses, derivation.identity) {
    return Err(WitnessMismatch)
  }
  Ok({ derivation, ordering, })
}

///|
pub fn result_ordering_evidence_cid(value : ResultOrderingEvidence) -> String {
  value.ordering.identity
}

///|
pub fn result_ordering_derivation_cid(value : ResultOrderingEvidence) -> String {
  value.derivation.identity
}

///|
pub fn result_ordering_evidence_contract(
  value : ResultOrderingEvidence,
) -> PublicationContract {
  value.ordering
}

///|
pub fn result_ordering_derivation_contract(
  value : ResultOrderingEvidence,
) -> PublicationContract {
  value.derivation
}

///|
fn artifact_cid_list_contains(
  artifact : PublicationContract,
  field : String,
  expected : String,
) -> Bool {
  guard @json.object_field(artifact.value, field) is Some(@json.Array(values)) else {
    return false
  }
  for value in @json.array_values(values) {
    if string_value(value) == Some(expected) {
      return true
    }
  }
  false
}

///|
/// Close the Result Artifact dependency edge before Manifest construction.
/// This check intentionally takes admitted opaque contracts rather than CID
/// strings so an adapter cannot substitute an unrelated ordering or policy.
pub fn validate_result_artifact_evidence(
  definition : PublicationContract,
  artifact : PublicationContract,
  evidence : ResultOrderingEvidence,
  retention : PublicationContract,
) -> Result[Unit, ResultArtifactEvidenceIssue] {
  if artifact.name != "result_artifact" {
    return Err(ArtifactWrongContract)
  }
  if definition.name != "result_definition" {
    return Err(ArtifactDefinitionMismatch)
  }
  if retention.name != "result_retention_policy" {
    return Err(ArtifactRetentionMismatch)
  }
  if contract_string(artifact, "result_definition_cid") !=
    Some(definition.identity) {
    return Err(ArtifactDefinitionMismatch)
  }
  if contract_string(artifact, "logical_result_cid") !=
    contract_string(evidence.derivation, "logical_value_cid") {
    return Err(ArtifactLogicalValueMismatch)
  }
  if contract_string(artifact, "result_schema_cid") !=
    contract_string(evidence.derivation, "relation_schema_cid") {
    return Err(ArtifactSchemaMismatch)
  }
  if contract_string(artifact, "ordering_evidence_cid") !=
    Some(evidence.ordering.identity) {
    return Err(ArtifactOrderingMismatch)
  }
  let policy = contract_string(evidence.derivation, "effective_data_policy_cid")
  if contract_string(artifact, "effective_data_policy_cid") != policy ||
    contract_string(retention, "effective_data_policy_cid") != policy {
    return Err(ArtifactPolicyMismatch)
  }
  if contract_string(artifact, "effective_retention_policy_cid") !=
    Some(retention.identity) {
    return Err(ArtifactRetentionMismatch)
  }
  if !artifact_cid_list_contains(
      artifact,
      "provenance_evidence_cids",
      evidence.derivation.identity,
    ) {
    return Err(ArtifactMissingDerivation)
  }
  Ok(())
}

///|
fn unique_contract_by_identity(
  contracts : Array[PublicationContract],
  identity : String,
) -> PublicationContract? {
  let matches = contracts.filter(contract => contract.identity == identity)
  if matches.length() == 1 {
    Some(matches[0])
  } else {
    None
  }
}

///|
fn ordering_derivation_cid(ordering : PublicationContract) -> String? {
  guard @json.object_field(ordering.value, "witness_evidence")
    is Some(@json.Array(values)) else {
    return None
  }
  let witnesses = @json.array_values(values)
  if witnesses.length() != 1 {
    return None
  }
  guard object_fields(witnesses[0]) is Ok(fields) else { return None }
  if optional_string(field_value(fields, "kind")) != Some("derivation") {
    return None
  }
  optional_string(field_value(fields, "cid"))
}

///|
/// Resolve every Artifact dependency from the exact supplied evidence set.
/// Equal content may share physical bytes, but dependency contracts remain
/// one-to-one with the declared Result occurrence and no unreferenced evidence
/// is accepted into the publication commit inventory.
pub fn validate_result_evidence_set(
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
) -> Result[Unit, ResultEvidenceSetIssue] {
  if definitions.length() != artifacts.length() ||
    artifacts.length() != derivations.length() ||
    artifacts.length() != orderings.length() ||
    artifacts.length() != retentions.length() {
    return Err(ResultEvidenceCount)
  }
  let used_derivations : Array[String] = []
  let used_orderings : Array[String] = []
  let used_retentions : Array[String] = []
  for artifact in artifacts {
    guard contract_string(artifact, "result_definition_cid")
      is Some(definition_cid) else {
      return Err(ResultEvidenceMissingDefinition)
    }
    guard unique_contract_by_identity(definitions, definition_cid)
      is Some(definition) else {
      return Err(ResultEvidenceMissingDefinition)
    }
    guard contract_string(artifact, "ordering_evidence_cid")
      is Some(ordering_cid) else {
      return Err(ResultEvidenceMissingOrdering)
    }
    guard unique_contract_by_identity(orderings, ordering_cid) is Some(ordering) else {
      return Err(ResultEvidenceMissingOrdering)
    }
    guard ordering_derivation_cid(ordering) is Some(derivation_cid) else {
      return Err(ResultEvidenceMissingDerivation)
    }
    guard unique_contract_by_identity(derivations, derivation_cid)
      is Some(derivation) else {
      return Err(ResultEvidenceMissingDerivation)
    }
    guard contract_string(artifact, "effective_retention_policy_cid")
      is Some(retention_cid) else {
      return Err(ResultEvidenceMissingRetention)
    }
    guard unique_contract_by_identity(retentions, retention_cid)
      is Some(retention) else {
      return Err(ResultEvidenceMissingRetention)
    }
    if used_derivations.contains(derivation_cid) ||
      used_orderings.contains(ordering_cid) ||
      used_retentions.contains(retention_cid) {
      return Err(ResultEvidenceDuplicate)
    }
    used_derivations.push(derivation_cid)
    used_orderings.push(ordering_cid)
    used_retentions.push(retention_cid)
    let logical = contract_string(artifact, "logical_result_cid").unwrap()
    let schema = contract_string(artifact, "result_schema_cid").unwrap()
    let policy = contract_string(artifact, "effective_data_policy_cid").unwrap()
    let evidence = match
      validate_result_occurrence_ordering_evidence(
        definition, derivation, ordering, logical, schema, policy,
      ) {
      Ok(value) => value
      Err(issue) => return Err(ResultEvidenceOrdering(issue))
    }
    match
      validate_result_artifact_evidence(
        definition, artifact, evidence, retention,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(ResultEvidenceArtifact(issue))
    }
  }
  Ok(())
}
