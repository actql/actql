///|
/// One exact completed broad observation and its live captured source. This
/// is issuer custody, not a serializable read grant or replay authorization.
struct SalesforceBroadSourceCapture {
  run : SalesforceBroadHostRun
  observation : SalesforceBroadObservation
  source : @query.CapturedInputSource
}

///|
pub fn capture_salesforce_broad_host_source(
  run : SalesforceBroadHostRun,
  observation : SalesforceBroadObservation,
) -> Result[SalesforceBroadSourceCapture, SalesforceBroadHostIssue] {
  salesforce_broad_host_source(run, observation).map(source => {
    run,
    observation,
    source,
  })
}

///|
pub fn salesforce_broad_source_capture_source(
  capture : SalesforceBroadSourceCapture,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  if capture.run.closed || !@query.captured_source_available(capture.source) {
    return Err(Unavailable)
  }
  Ok(capture.source)
}

///|
pub(all) enum SalesforceSourceEvidenceIssue {
  ObservationUnavailable
  ObservationMismatch
  Member(@environment.SourceEvidenceMemberIssue)
  LogicalInput(@publication.SourceInputLogicalIssue)
  InvalidPolicy
  Encoding(@encode.EncodeFailure)
  Evidence(@publication.RunEvidenceValueIssue)
} derive(Debug)

///|
/// Checked Catalog facts resolved in the runtime that owns the Query.
pub struct SalesforceSourceEvidenceContext {
  requirement : @planning.QueryRequirement
  facts : @planning.QuerySourceEvidenceFacts
  members : @environment.ConnectorSourceEvidenceMembers
}

///|
pub fn prepare_salesforce_source_evidence_context(
  requirement : @planning.QueryRequirement,
) -> Result[SalesforceSourceEvidenceContext, SalesforceSourceEvidenceIssue] {
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
/// Trusted Connector issuance after the current read decision. Capture
/// custody proves the checked input admission and the verified broad receipt;
/// no caller-provided completion, schema CID or capability CID is used. The
/// capability used is the admitted process-evidence contract of the broad
/// receipt, and the snapshot is the verified observation's identity.
pub fn issue_salesforce_broad_source_evidence(
  capture : SalesforceBroadSourceCapture,
  context : SalesforceSourceEvidenceContext,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> Result[@publication.RunEvidenceValue, SalesforceSourceEvidenceIssue] {
  match salesforce_broad_source_capture_source(capture) {
    Ok(source) =>
      if !@query.captured_source_relation_identity_matches_source(
          identity, source,
        ) {
        return Err(ObservationMismatch)
      }
    Err(_) => return Err(ObservationUnavailable)
  }
  if !physical_equal(context.requirement, capture.run.configuration.requirement) {
    return Err(ObservationMismatch)
  }
  let members = context.members
  let facts = context.facts
  if !@environment.connector_source_evidence_supports(members, [
      @planning.query_evidence_contract_identity(),
    ]) {
    return Err(Member(@environment.CapabilityMismatch))
  }
  // No policy transformation: the effective policy is the source's own.
  if effective_data_policy_cid != facts.source_data_policy_cid {
    return Err(InvalidPolicy)
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
    Err(issue) => return Err(LogicalInput(issue))
  }
  let (schema_cid, capability_cid) = @environment.connector_source_evidence_member_cids(
    members,
  )
  let writer = @encode.writer(16384, 256, 16) catch {
    issue => return Err(Encoding(issue))
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
        ("snapshot_ref", salesforce_broad_observation_cid(capture.observation)),
        ("completeness", "complete"),
        // One query and its locator chain is not a provider snapshot:
        // rows may change between pages.
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
    issue => return Err(Encoding(issue))
  }
  @publication.seal_run_evidence_value("source_evidence", body, 16384, 256, 16).map_err(issue => {
      Evidence(issue)
    },
  )
}
