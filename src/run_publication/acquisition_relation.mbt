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
  KeySetRole(Int, String)
  KeySetArity(Int)
  KeySetContract(Int, Int)
  KeySetOrder(Int, Int, @admitted.KeyOrderIssue)
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
  issue_source_request_acquisition_scope(
    source_contract_cid,
    request_values_cid,
    None,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Bind the existing key-set envelope to its own SourceView/static Request.
/// This is semantic Scope DATA, not evidence of lookup completion or authority.
pub fn issue_keyed_source_acquisition_scope(
  source_contract_cid : String,
  request_values_cid : String,
  key_set : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  if key_set.name != "request_key_set" ||
    contract_string(key_set, "source_view_contract_cid") !=
    Some(source_contract_cid) {
    return Err(WrongScope)
  }
  issue_source_request_acquisition_scope(
    source_contract_cid,
    request_values_cid,
    Some(key_set.identity),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_source_request_acquisition_scope(
  source_contract_cid : String,
  request_values_cid : String,
  key_set_cid : String?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_acquisition_scope_body(writer, writer => {
    emit_acquisition_scope_entry(
      writer,
      source_contract_cid,
      Some(request_values_cid),
      key_set_cid,
    )
  }) catch {
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
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
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
    before_body~,
  )
}

///|
/// A completed private computation can feed acquisition without publishing a
/// Result. The original capture owner supplies actual row count/completeness;
/// the validated derivation/order and same scope/retention bind its metadata.
/// This issues no execution, custody, Source access or completeness attestation.
pub fn issue_computed_input_relation(
  evidence : ResultOrderingEvidence,
  scope : PublicationContract,
  retention : PublicationContract,
  row_count : Int,
  completeness : String,
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
  if row_count < 0 || !["complete", "partial", "unknown"].contains(completeness) {
    return Err(WrongEvidence)
  }
  seal_input_relation(
    contract_string(evidence.derivation, "producer_contract_cid").unwrap(),
    contract_string(evidence.derivation, "logical_value_cid").unwrap(),
    contract_string(evidence.derivation, "relation_schema_cid").unwrap(),
    evidence.ordering.identity,
    scope,
    retention,
    row_count.to_int64(),
    completeness,
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
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  if before_body is Some(back) {
    let measure = @encode.construction_measuring_writer(
      max_bytes, max_nodes, max_depth,
    ) catch {
      _ => return Err(Encoding)
    }
    let shape = try {
      emit_acquisition_relation_body(
        measure,
        producer,
        logical,
        schema,
        ordering,
        scope.identity,
        retention.identity,
        contract_string(retention, "effective_data_policy_cid").unwrap(),
        rows,
        completeness,
        provenance_kind,
        provenance,
      )
      @encode.finish_construction_measurement(measure)
    } catch {
      _ => {
        @encode.cancel_writer(measure)
        return Err(Encoding)
      }
    }
    if !back("acquisition_relation", shape) {
      return Err(Encoding)
    }
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_acquisition_relation_body(
    writer,
    producer,
    logical,
    schema,
    ordering,
    scope.identity,
    retention.identity,
    contract_string(retention, "effective_data_policy_cid").unwrap(),
    rows,
    completeness,
    provenance_kind,
    provenance,
  ) catch {
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
  emit_occurrence_ordering_evidence_body(
    producer,
    source.identity,
    "source",
    writer,
  ) catch {
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

///|
fn emit_acquisition_scope_body(
  writer : @encode.Writer,
  emit_entries : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "sources")
  @encode.begin_array(writer)
  emit_entries(writer)
  @encode.end_array(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-acquisition-scope/0.1")
  @encode.end_object(writer)
}

///|
fn emit_acquisition_scope_entry(
  writer : @encode.Writer,
  source_contract_cid : String,
  request_values_cid : String?,
  key_set_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "request_key_set_cid")
  match key_set_cid {
    Some(cid) => @encode.string_value(writer, cid)
    None => @encode.null_value(writer)
  }
  @encode.key(writer, "request_values_cid")
  match request_values_cid {
    Some(cid) => @encode.string_value(writer, cid)
    None => @encode.null_value(writer)
  }
  @encode.key(writer, "source_contract_cid")
  @encode.string_value(writer, source_contract_cid)
  @encode.end_object(writer)
}

///|
fn emit_acquisition_relation_body(
  writer : @encode.Writer,
  producer : String,
  logical : String,
  schema : String,
  ordering : String,
  scope_cid : String,
  retention_cid : String,
  policy : String,
  rows : Int64,
  completeness : String,
  provenance_kind : String,
  provenance : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "actual_completeness")
  @encode.string_value(writer, completeness)
  @encode.key(writer, "actual_row_count")
  @encode.number_value(writer, rows.to_double())
  @encode.key(writer, "effective_data_policy_cid")
  @encode.string_value(writer, policy)
  @encode.key(writer, "effective_retention_policy_cid")
  @encode.string_value(writer, retention_cid)
  @encode.key(writer, "logical_value_cid")
  @encode.string_value(writer, logical)
  @encode.key(writer, "observation_scope_cid")
  @encode.string_value(writer, scope_cid)
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
}
