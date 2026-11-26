///|
// Exact Query originals for EVERY capture, never a selected primary source.
// One synchronous identity scan is retained before each fallible advance;
// already-completed evidence coexists in the same quoted metadata frontier.
fn NativeClientRelationFileWork::managed_query_publication_invocation(
  self : NativeClientRelationFileWork,
  owner : @local.ClientInstalledManagedRun,
  sources : Array[NativeRelationFileQuerySource],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  result_controls : Int64,
) -> Result[
  (
    Array[@publication.RunEvidenceValue],
    Array[@publication.RunEvidenceValue],
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
    Array[String],
    String,
  ),
  NativeClientSourceWorkIssue,
] {
  guard self.source is Managed(physical, _) &&
    sources.length() > 0 &&
    physical.length() == sources.length() &&
    sources.length() <= 1073741822 &&
    self.capture_times is Some((started, completed)) &&
    self.identity_scan is None &&
    managed_relation_file_sources_match(
      owner,
      self.prepared,
      self.start.request,
      sources,
    ) else {
    return Err(Configuration)
  }
  // Two original artifacts per Source plus observation/invocation/retention;
  // the independently funded Work vectors and source/scan payloads stay live.
  guard @execution.preparation_representation_cost({
      record_headers: 12L,
      reference_slots: 24L,
      scalar_words: 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(controls, result_controls, 1L)
    is Some(controls) &&
    @host.client_protocol_metadata_construction_bytes(
      max_wire_bytes,
      max_nodes.to_int64(),
      copies=2 * sources.length() + 3,
      extra_controls=controls,
    )
    is Some((metadata, _)) else {
    return Err(Configuration)
  }
  // No new arrays/identity serialization before the selected original body
  // grows through its actual native backing/current boundary.
  let first_capture = match physical[0].capture() {
    Err(issue) => return Err(RelationFile(issue))
    Ok(value) => value
  }
  let first_input = match @rows.row_capture_source(first_capture) {
    Err(issue) => return Err(CaptureIdentity(issue))
    Ok(value) => value
  }
  guard @execution_query.captured_source_cell_identity_start_capacity(
      first_input,
    )
    is Some(initial) else {
    return Err(Configuration)
  }
  match self.grow_publication_identity(metadata, initial) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let lookup = match self.access.lookup() {
    Err(issue) => return Err(OriginalOperation(issue))
    Ok(Retained(value)) => value
    Ok(_) => return Err(NeedsOriginalReconciliation)
  }
  let policy = match
    original_work_publication_policy(
      self.prepared,
      self.compiled,
      lookup,
      self.start.journal,
    ) {
    Err(issue) => return Err(Journal(issue))
    Ok(value) => value
  }
  let scope = @host.client_request_authority_scope_cid(self.start.request)
  let captures = []
  let identities = []
  let requirements = []
  let evidences = []
  let logicals = []
  let cids = []
  for index in 0..<sources.length() {
    match self.require_current() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let captured = match physical[index].capture() {
      Err(issue) => return Err(RelationFile(issue))
      Ok(value) => value
    }
    let input = match @rows.row_capture_source(captured) {
      Err(issue) => return Err(CaptureIdentity(issue))
      Ok(value) => value
    }
    let acquisition = sources[index].acquisition
    let requirement = @rows.row_acquisition_requirement(acquisition)
    let bounds = @rows.row_query_acquisition_completion_limits(acquisition)
    let values = bounds.execution.rows.output_values
    let wire = bounds.retention.measurement
    guard @execution_query.captured_source_cell_identity_start_capacity(input)
      is Some(start_capacity) &&
      @execution_query.captured_source_cell_identity_workspace_slots(
        input, values, wire, wire,
      )
      is Some(slots) else {
      return Err(Configuration)
    }
    match self.grow_publication_identity(metadata, start_capacity) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let scan = match
      @execution_query.start_captured_source_cell_identity(
        input,
        @rows.row_acquisition_max_rows(acquisition),
        values,
        wire,
        wire,
        {
          max_fields: wire.max_columns,
          max_bytes: wire.max_bytes,
          max_nodes: wire.max_nodes,
          max_depth: wire.max_depth,
        },
        values.max_work,
        slots,
        wire.max_bytes,
      ) {
      Err(issue) => return Err(CaptureIdentity(issue))
      Ok(value) => value
    }
    self.identity_scan = Some(scan)
    while true {
      guard @execution_query.captured_source_cell_identity_next_capacity(scan)
        is Some(next) else {
        return Err(Configuration)
      }
      match self.grow_publication_identity(metadata, next) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      match
        @execution_query.advance_captured_source_cell_identity(scan, 31, next) {
        Err(issue) => return Err(CaptureIdentity(issue))
        Ok((true, _)) => break
        Ok((false, _)) => ()
      }
    }
    let identity = match
      @execution_query.finish_captured_source_cell_identity(scan) {
      Err(issue) => return Err(CaptureIdentity(issue))
      Ok(value) => value
    }
    self.identity_scan = None
    let logical = match
      @host.issue_captured_source_input_logical(
        @strategy.captured_dag_graph(self.run),
        input,
        identity,
        requirement,
        task=index,
      ) {
      Err(issue) => return Err(InputLogical(issue))
      Ok(value) => value
    }
    guard @planning.query_requirement_source_evidence_facts(requirement)
      is Some(facts) else {
      return Err(Configuration)
    }
    let evidence = match
      @rows.issue_row_source_evidence(
        acquisition,
        captured,
        identity,
        logical,
        scope,
        facts.source_data_policy_cid,
        completed,
      ) {
      Err(issue) => return Err(SourceEvidence(issue))
      Ok(value) => value
    }
    captures.push(input)
    identities.push(identity)
    requirements.push(requirement)
    evidences.push(evidence)
    logicals.push(logical)
    cids.push(@execution_query.captured_source_relation_logical_cid(identity))
  }
  let (observation, invocation) = match
    @local.issue_program_captured_publication_invocation(
      owner,
      self.prepared,
      self.compiled,
      self.definition,
      captures,
      identities,
      requirements,
      evidences,
      logicals,
      None,
      scope,
      policy,
      started,
      completed,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  let original = (evidences, logicals, observation, invocation, cids, policy)
  self.publication_original = Some(original)
  self.require_current().map(_ => original)
}
