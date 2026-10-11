///|
pub(all) enum LocalSourcePublicationIssue {
  ForeignCompute
  Authorization(LocalNativeSourceIssue)
  Source(@query.CapturedSourceIssue)
  Evidence(@acquisition_host.NativeSourceEvidenceIssue)
  Logical(@host.ClientCapturedSourceLogicalIssue)
  MissingFacts
}

///|
/// Preparation borrows the original acquisition and Compute host. Traversal,
/// cancellation and workspace remain owned by the existing Relation frame.
pub struct LocalSourcePublicationPreparation {
  configuration : LocalNativeSourceConfiguration
  host : LocalComputeHost
  capture : @acquisition_host.NativeHostSourceCapture
  context : @acquisition_host.NativeSourceEvidenceContext
  scan : @query.CapturedSourceIdentityPreparation
}

///|
/// Typed facts for publication only. They do not admit, start or restore a Run.
pub struct LocalSourcePublication {
  logical : @publication.RunEvidenceValue
  evidence : @publication.RunEvidenceValue
}

///|
pub fn prepare_local_source_publication(
  configuration : LocalNativeSourceConfiguration,
  host : LocalComputeHost,
  capture : @acquisition_host.NativeHostSourceCapture,
  account : @authorization.AdmittedAccountConfiguration,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  max_workspace_slots : Int,
) -> Result[LocalSourcePublicationPreparation, LocalSourcePublicationIssue] {
  if !physical_equal(configuration.plan, host.plan) {
    return Err(ForeignCompute)
  }
  match authorize_local_native_source(configuration, account) {
    Err(issue) => return Err(Authorization(issue))
    Ok(_) => ()
  }
  let source = match
    @acquisition_host.native_host_source_capture_source(capture) {
    Ok(source) => source
    Err(issue) => return Err(Source(issue))
  }
  let context = match
    @acquisition_host.prepare_native_source_evidence_context(
      configuration.requirement,
    ) {
    Ok(context) => context
    Err(issue) => return Err(Evidence(issue))
  }
  let scan = match
    @query.start_captured_source_identity(
      source, max_rows, values, payload_wire, logical_wire, schema_limits, max_work,
      max_workspace_slots,
    ) {
    Ok(scan) => scan
    Err(issue) => return Err(Source(issue))
  }
  Ok({ configuration, host, capture, context, scan, })
}

///|
pub fn LocalSourcePublicationPreparation::advance(
  self : LocalSourcePublicationPreparation,
  quantum : Int,
) -> Result[(Bool, Int), LocalSourcePublicationIssue] {
  self.scan.advance(quantum).map_err(issue => Source(issue))
}

///|
pub fn LocalSourcePublicationPreparation::work(
  self : LocalSourcePublicationPreparation,
) -> Int64 {
  self.scan.work()
}

///|
pub fn LocalSourcePublicationPreparation::cancel(
  self : LocalSourcePublicationPreparation,
) -> Bool {
  self.scan.cancel()
}

///|
/// Recheck current read authority after the last yield. Source identity and
/// Catalog membership are checked independently by their existing issuers.
pub fn LocalSourcePublicationPreparation::finish(
  self : LocalSourcePublicationPreparation,
  account : @authorization.AdmittedAccountConfiguration,
  observed_at : String,
) -> Result[LocalSourcePublication, LocalSourcePublicationIssue] {
  match authorize_local_native_source(self.configuration, account) {
    Err(issue) => return Err(Authorization(issue))
    Ok(_) => ()
  }
  let source = match
    @acquisition_host.native_host_source_capture_source(self.capture) {
    Ok(source) => source
    Err(issue) => return Err(Source(issue))
  }
  let identity = match self.scan.finish() {
    Ok(identity) => identity
    Err(issue) => return Err(Source(issue))
  }
  let logical = match
    @host.issue_captured_source_input_logical(
      @strategy.captured_dag_graph(local_compute_run(self.host)),
      source,
      identity,
      self.configuration.requirement,
    ) {
    Ok(logical) => logical
    Err(issue) => return Err(Logical(issue))
  }
  guard @planning.query_requirement_source_evidence_facts(
      self.configuration.requirement,
    )
    is Some(facts) else {
    return Err(MissingFacts)
  }
  let evidence = match
    @acquisition_host.issue_native_host_source_evidence(
      self.capture,
      self.context,
      identity,
      logical,
      @host.client_request_authority_scope_cid(self.configuration.plan.request),
      @planning.query_source_evidence_fact_values(facts)[3],
      observed_at,
    ) {
    Ok(evidence) => evidence
    Err(issue) => return Err(Evidence(issue))
  }
  Ok({ logical, evidence, })
}

///|
pub fn local_source_publication_logical(
  publication : LocalSourcePublication,
) -> @publication.RunEvidenceValue {
  publication.logical
}

///|
pub fn local_source_publication_evidence(
  publication : LocalSourcePublication,
) -> @publication.RunEvidenceValue {
  publication.evidence
}
