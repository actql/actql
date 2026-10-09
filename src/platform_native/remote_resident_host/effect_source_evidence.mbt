///|
/// The original acquisition Owner and its exact checked requirement remain
/// with the producer. Transfer destination bytes cannot issue this observation.
priv struct ResidentEffectSourceCapture {
  owner : @host.PreparedClientEffectComputation
  requirement : @planning.QueryRequirement
  capture : @duckdb_host.NativeHostSourceCapture
}

///|
pub(all) enum ResidentEffectSourceEvidenceIssue {
  Unavailable
  Capture(@query.CapturedSourceIssue)
  Logical(@host.ClientCapturedSourceLogicalIssue)
  Observation(@duckdb_host.NativeSourceEvidenceIssue)
  Acquired(@host.ClientEffectAcquiredEvidenceIssue)
}

///|
/// Issue the original acquired Effect dependency from the actual Native
/// completion. This trusted Host entry requires the original read authority,
/// effective policy and acquisition observation time; it neither checks current
/// permission nor creates approval, Run authorization or a renewed lifetime.
///
/// The bounded identity pass reads only the retained capture, not the Source.
/// Its canonical relation/schema bodies accompany the common acquired-evidence
/// Owner for dependency custody. They do not restore a physical holding or
/// permit a consumer to substitute transferred Cells for the Source observation.
pub fn ResidentSourceCompute::prepare_effect_acquired_evidence(
  self : ResidentSourceCompute,
  authority_scope_cid : String,
  data_policy_cid : String,
  observed_at : String,
  retention : @publication.PublicationContract,
  limits : @host.PublicationOutputExportLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@host.ClientEffectAcquiredEvidence, (String, String)),
  ResidentEffectSourceEvidenceIssue,
] {
  guard !self.stopping &&
    !self.source_closed.val &&
    self.capture is Some(source) &&
    self.effect_source is Some(original) else {
    return Err(Unavailable)
  }
  // The Native issuer checks the original physical observation against this
  // exact requirement. A missing Catalog member is not source-free evidence.
  let context = match
    @duckdb_host.prepare_native_source_evidence_context(original.requirement) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let identity = match
    @query.identify_captured_source_relation(
      source,
      limits.max_rows,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      limits.max_batch_bytes,
      retain_body_bytes=max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let logical = match
    @host.issue_captured_source_input_logical(
      @strategy.captured_dag_graph(self.run),
      source,
      identity,
      original.requirement,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Logical(issue))
  }
  let observation = match
    @duckdb_host.issue_native_host_source_evidence(
      original.capture,
      context,
      identity,
      logical,
      authority_scope_cid,
      data_policy_cid,
      observed_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let evidence = match
    @host.issue_client_effect_acquired_evidence(
      original.owner,
      source,
      identity,
      original.requirement,
      logical,
      observation,
      authority_scope_cid,
      data_policy_cid,
      retention,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Acquired(issue))
  }
  guard @query.captured_source_relation_dependency_bodies(identity, source)
    is Some(bodies) else {
    return Err(Unavailable)
  }
  Ok((evidence, bodies))
}
