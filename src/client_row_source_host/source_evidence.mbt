///|
pub(all) enum RowSourceEvidenceIssue {
  ObservationUnavailable
  ObservationMismatch
  Member(@environment.SourceEvidenceMemberIssue)
  LogicalInput(@publication.SourceInputLogicalIssue)
  InvalidPolicy
  Encoding(@encode.EncodeFailure)
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Checked Catalog facts resolved in the runtime that owns the Query.
priv struct RowSourceEvidenceContext {
  requirement : @planning.QueryRequirement
  facts : @planning.QuerySourceEvidenceFacts
  members : @environment.ConnectorSourceEvidenceMembers
}

///|
fn prepare_row_source_evidence_context(
  requirement : @planning.QueryRequirement,
) -> Result[RowSourceEvidenceContext, RowSourceEvidenceIssue] {
  let members = match
    @planning.query_requirement_source_evidence_members(requirement) {
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
/// Source Evidence after the current read decision. Capture custody proves
/// the checked input admission and the verified receipt; nothing here takes
/// a caller-provided completion, schema or capability CID.
pub fn issue_row_source_evidence(
  acquisition : RowAcquisition,
  capture : RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> Result[@publication.RunEvidenceValue, RowHostIssue] {
  let context = acquisition.context
  match row_capture_source(capture) {
    Ok(source) =>
      if !@query.captured_source_relation_identity_matches_source(
          identity, source,
        ) {
        return Err(SourceEvidence(ObservationMismatch))
      }
    Err(_) => return Err(SourceEvidence(ObservationUnavailable))
  }
  if !physical_equal(context.requirement, capture.run.configuration.requirement) {
    return Err(SourceEvidence(ObservationMismatch))
  }
  let members = context.members
  let facts = context.facts
  if !@environment.connector_source_evidence_supports(members, [
      @planning.query_evidence_contract_identity(),
    ]) {
    return Err(SourceEvidence(Member(@environment.CapabilityMismatch)))
  }
  // No policy transformation: the effective policy is the source's own.
  if effective_data_policy_cid != facts.source_data_policy_cid {
    return Err(SourceEvidence(InvalidPolicy))
  }
  let logical = match
    @publication.admit_completed_source_input_logical(
      logical_input,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      facts.source_contract_cid,
      "{\"stable\":false,\"keys\":[]}",
      4096,
      128,
      16,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SourceEvidence(LogicalInput(issue)))
  }
  let (schema_cid, capability_cid) = @environment.connector_source_evidence_member_cids(
    members,
  )
  let writer = @encode.writer(16384, 256, 16) catch {
    issue => return Err(SourceEvidence(Encoding(issue)))
  }
  let body = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
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
        ("output_carrier", "relation"),
        ("read_mode", "snapshot"),
        ("observed_at", observed_at),
        ("snapshot_ref", row_observation_cid(capture.observation)),
        ("completeness", "complete"),
        // Paged provider reads are not provider snapshots: rows may change
        // between pages.
        ("consistency_level", "read_committed"),
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
    issue => return Err(SourceEvidence(Encoding(issue)))
  }
  @publication.seal_run_evidence_value("source_evidence", body, 16384, 256, 16).map_err(issue => {
      SourceEvidence(Evidence(issue))
    },
  )
}
