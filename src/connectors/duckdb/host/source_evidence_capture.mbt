///|
/// One exact completed observation and its live source. This is issuer
/// custody, not a serializable read grant or durable replay authorization.
struct NativeHostSourceCapture {
  run : NativeHostRun
  observation : @duckdb_query.DuckDBNativeObservation
  source : @query.CapturedInputSource
}

///|
pub fn capture_native_host_source(
  run : NativeHostRun,
  observation : @duckdb_query.DuckDBNativeObservation,
  retained : Bool,
  max_rows : Int,
  values : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[NativeHostSourceCapture, @query.CapturedSourceIssue] {
  if !verify_native_host(run, observation) {
    return Err(Unavailable)
  }
  let source = if retained {
    native_host_retained_source(run, observation, max_entries, max_name_bytes)
  } else {
    let material = match native_host_output(run, observation, max_rows, values) {
      Ok(material) => material
      Err(_) => return Err(Unavailable)
    }
    @duckdb_query.native_captured_source(material, max_entries, max_name_bytes)
  }
  source.map(source => { run, observation, source, })
}

///|
pub fn native_host_source_capture_source(
  capture : NativeHostSourceCapture,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  if !verify_native_host(capture.run, capture.observation) ||
    !@query.captured_source_available(capture.source) {
    return Err(Unavailable)
  }
  Ok(capture.source)
}

///|
/// Reuse the already measured row/schema identity only for its exact source.
/// No second payload traversal or hash is needed at Source Evidence issuance.
pub fn native_host_source_capture_identity_matches(
  capture : NativeHostSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  match native_host_source_capture_source(capture) {
    Ok(source) =>
      @query.captured_source_relation_identity_matches_source(identity, source)
    Err(_) => false
  }
}

///|
pub(all) enum NativeSourceEvidenceIssue {
  ObservationUnavailable
  ObservationMismatch
  Member(@environment.SourceEvidenceMemberIssue)
  LogicalInput(@publication.SourceInputLogicalIssue)
  InvalidPolicy
  Encoding(@encode.EncodeFailure)
  Evidence(@publication.RunEvidenceValueIssue)
} derive(Debug)

///|
/// Resolve checked Catalog maps in the runtime that owns the Query. The
/// opaque context crosses the in-process ABI without re-reading a Map using
/// another compiled runtime's hash seed. It grants no physical read authority.
pub struct NativeSourceEvidenceContext {
  requirement : @planning.QueryRequirement
  facts : @planning.QuerySourceEvidenceFacts
  members : @environment.ConnectorSourceEvidenceMembers
}

///|
pub fn prepare_native_source_evidence_context(
  requirement : @planning.QueryRequirement,
) -> Result[NativeSourceEvidenceContext, NativeSourceEvidenceIssue] {
  let members = match @planning.query_requirement_source_evidence_members(requirement) {
    Ok(members) => members
    Err(issue) => return Err(Member(issue))
  }
  guard @planning.query_requirement_source_evidence_facts(requirement)
    is Some(facts) else {
    return Err(ObservationUnavailable)
  }
  Ok({ requirement, facts, members, })
}

///|
/// Trusted Connector issuance after current read authorization. Capture
/// custody proves actual schema validation and two-receipt completion. No
/// caller-provided completion, schema CID, capability CID or row hash is used.
pub fn issue_native_host_source_evidence(
  capture : NativeHostSourceCapture,
  context : NativeSourceEvidenceContext,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> Result[@publication.RunEvidenceValue, NativeSourceEvidenceIssue] {
  if !native_host_source_capture_identity_matches(capture, identity) {
    return Err(ObservationMismatch)
  }
  if !physical_equal(context.requirement, capture.run.requirement) {
    return Err(ObservationMismatch)
  }
  let members = context.members
  let facts = context.facts
  if !@environment.connector_source_evidence_supports(members,
    [capture.run.capability_contract_cid]) {
    return Err(Member(@environment.CapabilityMismatch))
  }
  // This profile has no policy transformation. It cannot weaken the checked
  // source's policy using a caller-supplied effective policy CID.
  if effective_data_policy_cid != facts.source_data_policy_cid {
    return Err(InvalidPolicy)
  }
  let logical = match @publication.admit_completed_source_input_logical(
    logical_input, @query.captured_source_relation_logical_cid(identity),
    @query.captured_source_relation_schema_cid(identity),
    facts.source_contract_cid, "{\"stable\":false,\"keys\":[]}", 4096, 128, 16,
  ) {
    Ok(value) => value
    Err(issue) => return Err(LogicalInput(issue))
  }
  let (schema_cid, capability_cid) =
    @environment.connector_source_evidence_member_cids(members)
  let writer = @encode.writer(16384, 256, 16) catch {
    issue => return Err(Encoding(issue))
  }
  let body = try {
    @encode.begin_object(writer)
    for (key, value) in [
      ("version", "actql-source-evidence/0.1"),
      ("source_ref", facts.source_ref),
      ("input_logical_cid", logical),
      ("source_contract_cid", facts.source_contract_cid),
      ("schema_evidence_cid", schema_cid),
      ("capability_evidence_cid", capability_cid),
      ("authority_scope_cid", authority_scope_cid),
      ("source_data_policy_cid", facts.source_data_policy_cid),
      ("effective_data_policy_cid", effective_data_policy_cid),
      ("data_classification", facts.data_classification),
      ("source_view_contract_cid", facts.source_view_contract_cid),
      ("output_carrier", "relation"), ("read_mode", "snapshot"),
      ("observed_at", observed_at),
      ("snapshot_ref", @duckdb_query.duckdb_native_observation_cid(
        capture.observation)),
      ("completeness", "complete"), ("consistency_level", "snapshot"),
    ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "ordering_evidence")
    @encode.begin_object(writer)
    @encode.key(writer, "stable")
    @encode.bool_value(writer, false)
    @encode.key(writer, "keys")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    issue => return Err(Encoding(issue))
  }
  @publication.seal_run_evidence_value("source_evidence", body, 16384, 256, 16)
  .map_err(issue => Evidence(issue))
}

///|
pub fn native_host_source_capture_source_ref(
  capture : NativeHostSourceCapture,
) -> String? {
  if !verify_native_host(capture.run, capture.observation) {
    return None
  }
  Some(@planning.query_requirement_source(capture.run.requirement).0)
}
