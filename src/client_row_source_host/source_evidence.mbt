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
  guard capture.run.configuration is DirectConfiguration(configuration) &&
    physical_equal(context.requirement, configuration.requirement) &&
    capture.observation is QueryObservation(observation) else {
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
  match
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
    Ok(_) => ()
    Err(issue) => return Err(SourceEvidence(LogicalInput(issue)))
  }
  let (schema_cid, capability_cid) = @environment.connector_source_evidence_member_cids(
    members,
  )
  let fields : @publication.CompletedSourceObservationBody = {
    input: logical_input,
    source_ref: facts.source_ref,
    source_contract_cid: facts.source_contract_cid,
    schema_evidence_cid: schema_cid,
    capability_evidence_cid: capability_cid,
    authority_scope_cid,
    source_data_policy_cid: facts.source_data_policy_cid,
    data_classification: facts.data_classification,
    source_view_contract_cid: facts.source_view_contract_cid,
    observed_at,
    snapshot_ref: row_observation_cid(observation),
  }
  // Only the selected funded report variant has the additional data/custody
  // obligation. Ordinary resolved listings retain their preactivation evidence
  // scope; absence never becomes a zero-row report or completed correlation.
  if configuration.listing_rows is Some(ReportListingRows(_, _)) {
    guard !capture.run.closed &&
      capture.run.physical is Some(physical) &&
      row_listing_encoding_reservation_live(physical) &&
      configuration.listing_rows is Some(ReportListingRows(resolved, reports)) &&
      acquisition.configuration.listing_rows is Some(original) &&
      physical_equal(resolved, listing_rows_resolution(original)) &&
      reports.scan is Some(scan) &&
      reports.rows is Some(rows) &&
      capture.run.residual is Some(residual) &&
      physical_equal(scan, @query.query_receipt_rows(residual.receipt)) &&
      @execution.captured_row_count(scan) == rows.length() else {
      return Err(SourceEvidence(ObservationMismatch))
    }
    // The existing Query observation snapshot commits its access scope's
    // received_rows_cid, while input_logical_cid names the acquired output.
    // These reports refer to that same original scan, not a residual Result.
    // Borrow the original array synchronously; the codec never receives a
    // copied/reconstructed correlation list or custody permission from data.
    return @publication.seal_completed_file_listing_observation(
      fields,
      rows.length(),
      rows,
    ).map_err(issue => SourceEvidence(Evidence(issue)))
  }
  @publication.seal_completed_source_observation(fields).map_err(issue => {
    SourceEvidence(Evidence(issue))
  })
}

///|
/// General Source evidence from the same completed whole-input RowRun. It
/// carries no Query receipt. The content-derived observation identity names
/// this completed logical input under the existing weak read-committed law;
/// it is not a provider snapshot guarantee or permission to reread.
pub fn issue_row_input_source_evidence(
  acquisition : RowInputAcquisition,
  capture : RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> Result[@publication.RunEvidenceValue, RowHostIssue] {
  let preparation = acquisition.preparation
  let source = match row_capture_source(capture) {
    Ok(value) => value
    Err(_) => return Err(SourceEvidence(ObservationUnavailable))
  }
  guard capture.run.configuration is InputConfiguration(selected) &&
    physical_equal(selected.preparation, preparation) &&
    capture.observation is InputObservation(observation) &&
    capture.run.attempt.authority is InputAuthority(authority) &&
    physical_equal(authority, observation.authority) &&
    @query.captured_source_matches_input_acquisition(
      source,
      preparation.original,
    ) &&
    @query.captured_source_relation_identity_matches_source(identity, source) else {
    return Err(SourceEvidence(ObservationMismatch))
  }
  let facts = preparation.facts
  if effective_data_policy_cid != facts.source_data_policy_cid {
    return Err(SourceEvidence(InvalidPolicy))
  }
  match
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
    Ok(_) => ()
    Err(issue) => return Err(SourceEvidence(LogicalInput(issue)))
  }
  let (schema_cid, capability_cid) = @environment.connector_source_evidence_member_cids(
    preparation.members,
  )
  @publication.seal_completed_source_observation({
    input: logical_input,
    source_ref: facts.source_ref,
    source_contract_cid: facts.source_contract_cid,
    schema_evidence_cid: schema_cid,
    capability_evidence_cid: capability_cid,
    authority_scope_cid,
    source_data_policy_cid: facts.source_data_policy_cid,
    data_classification: facts.data_classification,
    source_view_contract_cid: facts.source_view_contract_cid,
    observed_at,
    snapshot_ref: @publication.run_evidence_value_identity(logical_input),
  }).map_err(issue => SourceEvidence(Evidence(issue)))
}

///|
// Explicit report-capable entry in the same Source Owner. A resolved listing,
// even a genuinely empty one, cannot satisfy this entry without selecting the
// additional accounted profile and retaining its original scan/report custody.
// The common issuer below still checks all nominal bindings and live funding.
// Include this call-frame overlap in the selected report execution envelope;
// no ordinary Source call acquires an additional standing field or wrapper.
pub fn issue_row_listing_source_evidence(
  acquisition : RowAcquisition,
  capture : RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> Result[@publication.RunEvidenceValue, RowHostIssue] {
  guard capture.run.configuration is DirectConfiguration(configuration) &&
    configuration.listing_rows is Some(ReportListingRows(_, _)) else {
    return Err(SourceEvidence(ObservationUnavailable))
  }
  issue_row_source_evidence(
    acquisition, capture, identity, logical_input, authority_scope_cid, effective_data_policy_cid,
    observed_at,
  )
}
