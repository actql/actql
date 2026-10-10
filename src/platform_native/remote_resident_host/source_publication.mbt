///|
pub(all) enum ResidentSourcePublicationObservationIssue {
  Unavailable
  Identity(@query.CapturedSourceIssue)
  Logical(@host.ClientCapturedSourceLogicalIssue)
  Evidence(@duckdb_host.NativeSourceEvidenceIssue)
}

///|
/// Evidence from one actual, still retained acquisition. Original requirement,
/// schema validation and two-receipt custody remain with the existing Source
/// owner. This is neither a public Result nor a durable restoration handle.
struct ResidentSourcePublicationObservation {
  evidence : @publication.RunEvidenceValue
  logical : @publication.RunEvidenceValue
  source_ref : String
  source_contract_cid : String
  policy_cid : String
}

///|
pub fn resident_source_publication_observation_values(
  value : ResidentSourcePublicationObservation,
) -> (
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
  String,
  String,
  String,
) {
  (
    value.evidence,
    value.logical,
    value.source_ref,
    value.source_contract_cid,
    value.policy_cid,
  )
}

///|
/// The caller supplies the original acquisition completion time and current
/// Source authority. No provider query is opened, no Policy is invented or
/// weakened, and no publication permission is inferred from the capture.
pub fn ResidentSourceCompute::source_publication_observation(
  self : ResidentSourceCompute,
  authority_scope_cid : String,
  captured_at : String,
  limits : @host.PublicationOutputExportLimits,
) -> Result[
  ResidentSourcePublicationObservation,
  ResidentSourcePublicationObservationIssue,
] {
  guard !self.stopping &&
    !self.source_closed.val &&
    self.capture is Some(captured) &&
    self.acquired_source is Some(original) &&
    @planning.query_requirement_source_evidence_facts(original.requirement)
    is Some(facts) else {
    return Err(Unavailable)
  }
  let context = match
    @duckdb_host.prepare_native_source_evidence_context(original.requirement) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let identity = match
    @query.identify_captured_source_relation(
      captured,
      limits.max_rows,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      limits.max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let logical = match
    @host.issue_captured_source_input_logical(
      @strategy.captured_dag_graph(self.run),
      captured,
      identity,
      original.requirement,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Logical(issue))
  }
  let policy_cid = @planning.query_source_evidence_fact_values(facts)[3]
  let evidence = match
    @duckdb_host.issue_native_host_source_evidence(
      original.capture,
      context,
      identity,
      logical,
      authority_scope_cid,
      policy_cid,
      captured_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  if self.stopping || self.source_closed.val {
    return Err(Unavailable)
  }
  let (source_ref, source_contract_cid) = @planning.query_requirement_source(
    original.requirement,
  )
  Ok({ evidence, logical, source_ref, source_contract_cid, policy_cid, })
}
