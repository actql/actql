///|
/// Failures while issuing evidence for one exact checked Result occurrence.
/// The output identity and schema are supplied by the completed Relation
/// export; this API never accepts an adapter-produced replacement body.
pub(all) enum ResultEvidenceIssuanceIssue {
  IssuanceWrongDefinition
  IssuanceInvalidIdentity
  IssuanceEmptyIssuer
  IssuanceDuplicateInput
  IssuanceEncoding
  IssuanceContract(PublicationContractIssue)
  IssuanceEvidence(ResultOrderingEvidenceIssue)
} derive(Eq, Debug)

///|
fn issuance_cids(
  values : Array[String],
) -> Result[Array[String], ResultEvidenceIssuanceIssue] {
  let sorted = values.copy()
  sorted.sort()
  for index, value in sorted {
    if !valid_cid(value) {
      return Err(IssuanceInvalidIdentity)
    }
    if index > 0 && sorted[index - 1] == value {
      return Err(IssuanceDuplicateInput)
    }
  }
  Ok(sorted)
}

///|
fn emit_derivation_evidence_body(
  definition_cid : String,
  logical_value_cid : String,
  result_schema_cid : String,
  computation_contract_cid : String,
  input_relation_cids : Array[String],
  scope_cid : String,
  effective_data_policy_cid : String,
  issuer_id : String,
  authority_scope_cid : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "authority_scope_cid")
  @encode.string_value(writer, authority_scope_cid)
  @encode.key(writer, "computation_contract_cid")
  @encode.string_value(writer, computation_contract_cid)
  @encode.key(writer, "effective_data_policy_cid")
  @encode.string_value(writer, effective_data_policy_cid)
  @encode.key(writer, "input_relation_cids")
  @encode.begin_array(writer)
  for cid in input_relation_cids {
    @encode.string_value(writer, cid)
  }
  @encode.end_array(writer)
  @encode.key(writer, "issuer_id")
  @encode.string_value(writer, issuer_id)
  @encode.key(writer, "logical_value_cid")
  @encode.string_value(writer, logical_value_cid)
  @encode.key(writer, "ordering")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "occurrence")
  @encode.key(writer, "terms")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.key(writer, "producer_contract_cid")
  @encode.string_value(writer, definition_cid)
  @encode.key(writer, "relation_schema_cid")
  @encode.string_value(writer, result_schema_cid)
  @encode.key(writer, "scope_cid")
  @encode.string_value(writer, scope_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-acquisition-derivation-evidence/0.1")
  @encode.end_object(writer)
}

///|
fn emit_ordering_evidence_body(
  definition_cid : String,
  derivation_cid : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "occurrence")
  @encode.key(writer, "producer_contract_cid")
  @encode.string_value(writer, definition_cid)
  @encode.key(writer, "terms")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-acquisition-ordering/0.1")
  @encode.key(writer, "witness_evidence")
  @encode.begin_array(writer)
  @encode.begin_object(writer)
  @encode.key(writer, "cid")
  @encode.string_value(writer, derivation_cid)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "derivation")
  @encode.end_object(writer)
  @encode.end_array(writer)
  @encode.end_object(writer)
}

///|
/// Issue the finite occurrence-order evidence profile from identities already
/// established by the exact completed Result export. Context CIDs still have
/// to resolve through the surrounding publication chain; sealing them here
/// does not establish those referenced contracts or Host authority.
pub fn issue_result_occurrence_evidence(
  definition : PublicationContract,
  logical_value_cid : String,
  result_schema_cid : String,
  computation_contract_cid : String,
  input_relation_cids : Array[String],
  scope_cid : String,
  effective_data_policy_cid : String,
  issuer_id : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResultOrderingEvidence, ResultEvidenceIssuanceIssue] {
  if definition.name != "result_definition" {
    return Err(IssuanceWrongDefinition)
  }
  issue_occurrence_evidence_for_producer(
    definition.identity,
    logical_value_cid,
    result_schema_cid,
    computation_contract_cid,
    input_relation_cids,
    scope_cid,
    effective_data_policy_cid,
    issuer_id,
    authority_scope_cid,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Build evidence for a checked local Result producer. The caller must retain
/// its typed local Definition and resolve the returned references in the
/// local Stage registry; a producer CID alone is not execution evidence.
pub fn issue_local_result_occurrence_evidence(
  local_definition_cid : String,
  logical_value_cid : String,
  result_schema_cid : String,
  computation_contract_cid : String,
  input_relation_cids : Array[String],
  scope_cid : String,
  effective_data_policy_cid : String,
  issuer_id : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResultOrderingEvidence, ResultEvidenceIssuanceIssue] {
  if !valid_cid(local_definition_cid) {
    return Err(IssuanceInvalidIdentity)
  }
  issue_occurrence_evidence_for_producer(
    local_definition_cid, logical_value_cid, result_schema_cid, computation_contract_cid,
    input_relation_cids, scope_cid, effective_data_policy_cid, issuer_id, authority_scope_cid,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn issue_occurrence_evidence_for_producer(
  producer_cid : String,
  logical_value_cid : String,
  result_schema_cid : String,
  computation_contract_cid : String,
  input_relation_cids : Array[String],
  scope_cid : String,
  effective_data_policy_cid : String,
  issuer_id : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResultOrderingEvidence, ResultEvidenceIssuanceIssue] {
  if issuer_id.is_empty() {
    return Err(IssuanceEmptyIssuer)
  }
  for
    cid in [
      logical_value_cid, result_schema_cid, computation_contract_cid, scope_cid,
      effective_data_policy_cid, authority_scope_cid,
    ] {
    if !valid_cid(cid) {
      return Err(IssuanceInvalidIdentity)
    }
  }
  let inputs = match issuance_cids(input_relation_cids) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let derivation_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(IssuanceEncoding)
  }
  emit_derivation_evidence_body(
    producer_cid, logical_value_cid, result_schema_cid, computation_contract_cid,
    inputs, scope_cid, effective_data_policy_cid, issuer_id, authority_scope_cid,
    derivation_writer,
  ) catch {
    _ => return Err(IssuanceEncoding)
  }
  let derivation_body = @encode.finish(derivation_writer) catch {
    _ => return Err(IssuanceEncoding)
  }
  let derivation = match
    seal_publication_contract(
      "derivation_evidence", derivation_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(IssuanceContract(issue))
  }
  let ordering_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(IssuanceEncoding)
  }
  emit_ordering_evidence_body(
    producer_cid,
    derivation.identity,
    ordering_writer,
  ) catch {
    _ => return Err(IssuanceEncoding)
  }
  let ordering_body = @encode.finish(ordering_writer) catch {
    _ => return Err(IssuanceEncoding)
  }
  let ordering = match
    seal_publication_contract(
      "ordering_evidence", ordering_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(IssuanceContract(issue))
  }
  match
    validate_result_occurrence_ordering_for_producer(
      producer_cid, derivation, ordering, logical_value_cid, result_schema_cid, effective_data_policy_cid,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(IssuanceEvidence(issue))
  }
}
