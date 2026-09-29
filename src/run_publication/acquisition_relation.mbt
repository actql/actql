///|
/// Closed lists reuse the existing acquisition registry. In particular a
/// self hash alone never establishes the body kind or upstream custody.
fn validate_relation_provenance(value : @json.CanonicalValue) -> Bool {
  guard value is @json.Array(entries) else { return false }
  let mut previous = ""
  for entry in @json.array_values(entries) {
    guard object_fields(entry) is Ok(fields) &&
      fields.length() == 2 &&
      evidence_string(entry, "kind") is Some(kind) &&
      ["source", "derivation", "relation", "attempt_receipt"].contains(kind) &&
      evidence_string(entry, "cid") is Some(cid) &&
      valid_contract_cid(cid) else {
      return false
    }
    let key = kind + ":" + cid
    if @canonical.compare_utf16(key, previous) <= 0 {
      return false
    }
    previous = key
  }
  true
}

///|
fn scope_optional_cid(value : @json.CanonicalValue) -> String? {
  match value {
    @json.Null => Some("null")
    @json.String(cid) if valid_contract_cid(cid) => Some("\"" + cid + "\"")
    _ => None
  }
}

///|
fn validate_scope_sources(value : @json.CanonicalValue) -> Bool {
  guard value is @json.Array(entries) else { return false }
  let mut previous = ""
  for entry in @json.array_values(entries) {
    guard object_fields(entry) is Ok(fields) &&
      fields.length() == 3 &&
      evidence_string(entry, "source_contract_cid") is Some(source) &&
      valid_contract_cid(source) &&
      @json.object_field(entry, "request_values_cid").bind(scope_optional_cid)
      is Some(values) &&
      @json.object_field(entry, "request_key_set_cid").bind(scope_optional_cid)
      is Some(keys) else {
      return false
    }
    // All strings are validated ASCII CIDs. This is the canonical JSON
    // byte ordering of these closed entries, not authored source order.
    let key = keys + "," + values + "," + source
    if @canonical.compare_utf16(key, previous) <= 0 {
      return false
    }
    previous = key
  }
  true
}

///|
pub(all) enum AcquisitionRelationIssue {
  WrongEvidence
  WrongScope
  WrongRetention
  Encoding
  Contract(PublicationContractIssue)
} derive(Eq, Debug)

///|
/// Seal the already checked single non-keyed SourceView request scope. This
/// low-level envelope is not evidence that the request ran; the captured
/// Source owner must supply and validate the matching request and observation.
pub fn issue_single_source_acquisition_scope(
  source_contract_cid : String,
  request_values_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "sources")
    @encode.begin_array(writer)
    @encode.begin_object(writer)
    @encode.key(writer, "request_key_set_cid")
    @encode.null_value(writer)
    @encode.key(writer, "request_values_cid")
    @encode.string_value(writer, request_values_cid)
    @encode.key(writer, "source_contract_cid")
    @encode.string_value(writer, source_contract_cid)
    @encode.end_object(writer)
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-acquisition-scope/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  seal_publication_contract(
    "acquisition_scope", body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => AcquisitionRelationIssue::Contract(issue))
}

///|
/// A derived Result becomes an upstream Relation without scanning its bytes
/// again. The Artifact supplies its admitted row count and completeness;
/// its physical owner must keep the payload alive. Scope is the exact admitted acquisition scope, not a Run
/// binding CID or a guessed external coverage claim.
pub fn issue_derived_input_relation(
  artifact : PublicationContract,
  evidence : ResultOrderingEvidence,
  scope : PublicationContract,
  retention : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  if scope.name != "acquisition_scope" ||
    contract_string(evidence.derivation, "scope_cid") != Some(scope.identity) {
    return Err(WrongScope)
  }
  if retention.name != "result_retention_policy" ||
    contract_string(evidence.derivation, "effective_data_policy_cid") !=
    contract_string(retention, "effective_data_policy_cid") {
    return Err(WrongRetention)
  }
  if validate_local_result_artifact_evidence(
      contract_string(evidence.derivation, "producer_contract_cid").unwrap(),
      artifact,
      evidence,
      retention,
    )
    is Err(_) {
    return Err(WrongEvidence)
  }
  seal_input_relation(
    contract_string(evidence.derivation, "producer_contract_cid").unwrap(),
    contract_string(evidence.derivation, "logical_value_cid").unwrap(),
    contract_string(evidence.derivation, "relation_schema_cid").unwrap(),
    evidence.ordering.identity,
    scope,
    retention,
    contract_count(artifact, "actual_row_count").unwrap(),
    contract_string(artifact, "actual_completeness").unwrap(),
    "derivation",
    evidence.derivation.identity,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn seal_input_relation(
  producer : String,
  logical : String,
  schema : String,
  ordering : String,
  scope : PublicationContract,
  retention : PublicationContract,
  rows : Int64,
  completeness : String,
  provenance_kind : String,
  provenance : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "actual_completeness")
    @encode.string_value(writer, completeness)
    @encode.key(writer, "actual_row_count")
    @encode.number_value(writer, rows.to_double())
    @encode.key(writer, "effective_data_policy_cid")
    @encode.string_value(
      writer,
      contract_string(retention, "effective_data_policy_cid").unwrap(),
    )
    @encode.key(writer, "effective_retention_policy_cid")
    @encode.string_value(writer, retention.identity)
    @encode.key(writer, "logical_value_cid")
    @encode.string_value(writer, logical)
    @encode.key(writer, "observation_scope_cid")
    @encode.string_value(writer, scope.identity)
    @encode.key(writer, "ordering_evidence_cid")
    @encode.string_value(writer, ordering)
    @encode.key(writer, "producer_contract_cid")
    @encode.string_value(writer, producer)
    @encode.key(writer, "provenance_evidence")
    @encode.begin_array(writer)
    @encode.begin_object(writer)
    @encode.key(writer, "cid")
    @encode.string_value(writer, provenance)
    @encode.key(writer, "kind")
    @encode.string_value(writer, provenance_kind)
    @encode.end_object(writer)
    @encode.end_array(writer)
    @encode.key(writer, "relation_schema_cid")
    @encode.string_value(writer, schema)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-acquisition-relation/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  seal_publication_contract(
    "acquisition_relation", body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => AcquisitionRelationIssue::Contract(issue))
}

///|
/// Closed evidence for one captured non-keyed SourceView input. The Host
/// issuer must first match request identity and row count to its live capture;
/// this envelope builder does not attest physical execution or current access.
pub fn issue_captured_source_input_relation(
  input : RunEvidenceValue,
  source : RunEvidenceValue,
  request_values_cid : String,
  row_count : Int,
  retention : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (PublicationContract, PublicationContract, PublicationContract),
  AcquisitionRelationIssue,
] {
  if input.name != "source_input_logical" ||
    source.name != "source_evidence" ||
    row_count < 0 {
    return Err(WrongEvidence)
  }
  let producer = evidence_string(source.value, "source_contract_cid").unwrap()
  let policy = evidence_string(source.value, "effective_data_policy_cid").unwrap()
  if retention.name != "result_retention_policy" ||
    contract_string(retention, "effective_data_policy_cid") != Some(policy) {
    return Err(WrongRetention)
  }
  if admit_completed_source_observation_binding(
      source,
      input,
      evidence_string(source.value, "source_ref").unwrap(),
      producer,
      evidence_string(source.value, "authority_scope_cid").unwrap(),
      policy,
      max_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) {
    return Err(WrongEvidence)
  }
  let scope = match
    issue_single_source_acquisition_scope(
      producer, request_values_cid, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "occurrence")
    @encode.key(writer, "producer_contract_cid")
    @encode.string_value(writer, producer)
    @encode.key(writer, "terms")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-acquisition-ordering/0.1")
    @encode.key(writer, "witness_evidence")
    @encode.begin_array(writer)
    @encode.begin_object(writer)
    @encode.key(writer, "cid")
    @encode.string_value(writer, source.identity)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "source")
    @encode.end_object(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  let ordering = match
    seal_publication_contract(
      "ordering_evidence", body, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Contract(issue))
  }
  let relation = match
    seal_input_relation(
      producer,
      evidence_string(input.value, "logical_relation_cid").unwrap(),
      evidence_string(input.value, "relation_schema_cid").unwrap(),
      ordering.identity,
      scope,
      retention,
      row_count.to_int64(),
      "complete",
      "source",
      source.identity,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((relation, ordering, scope))
}
