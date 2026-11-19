///|
// Resolve DATA from the SAME original acquisition and prepared Program. The
// physical Source-input graph preserves these task numbers/owners; this is
// neither a completion, a current observation nor permission to read again.
fn native_whole_source_publication_task(
  prepared : @host.PreparedClientProgram,
  original : @sourceviews.SourceAcquisition,
) -> Int? {
  let stage = @sourceviews.declaration(
      @sourceviews.mode_input(@sourceviews.source_acquisition_mode(original)),
    ).stage_index
  let source_index = @sourceviews.source_acquisition_source_index(original)
  if !@host.client_source_acquisition_matches_program(
      prepared, stage, source_index, original,
    ) {
    return None
  }
  @strategy.graph_stage_operation_task(
    @host.prepared_client_graph(prepared),
    stage,
    0,
  )
}

///|
// Exact complete-input originals for EVERY capture, never Query substitutes.
// One synchronous identity scan is retained before each fallible advance;
// already-completed evidence coexists in the same quoted metadata frontier.
fn NativeClientRelationFileWork::managed_whole_publication_invocation(
  self : NativeClientRelationFileWork,
  owner : @local.ClientInstalledManagedRun,
  sources : Array[NativeRelationFileWholeSource],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
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
    managed_whole_relation_file_sources_match(
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
      // Per Source, same-original Stage requests Some H1/R1/W1 plus
      // graph_stage_operation_task H8/R4/W10: unit get/map Some+closure,
      // Step tag, Stage-task and task gets, owner get and returned Some.
      // Sum H9/R5/W11 = 272 logical bytes per original, before allocation;
      // no cursor/metadata phase or GC reuse supplies these products.
      record_headers: 12L + 9L * sources.length().to_int64(),
      reference_slots: 24L + 5L * sources.length().to_int64(),
      scalar_words: 16L + 11L * sources.length().to_int64(),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
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
    let acquisition = @local.installed_whole_source_acquisition(
      sources[index].capacity,
    )
    let original = @local.installed_whole_source_original(
      sources[index].capacity,
    )
    let bounds = @rows.row_input_acquisition_limits(acquisition)
    let values = bounds.retention
    let wire = bounds.wire
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
        bounds.max_rows,
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
    let task = match
      native_whole_source_publication_task(self.prepared, original) {
      None => return Err(InputLogical(@host.ForeignPrepared))
      Some(value) => value
    }
    let logical = match
      @host.issue_captured_whole_source_input_logical(
        @strategy.captured_dag_graph(self.run),
        input,
        identity,
        original,
        task~,
      ) {
      Err(issue) => return Err(InputLogical(issue))
      Ok(value) => value
    }
    let facts = @rows.row_input_acquisition_facts(acquisition)
    let evidence = match
      @rows.issue_row_input_source_evidence(
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
    captures.push(captured)
    identities.push(identity)
    evidences.push(evidence)
    logicals.push(logical)
    cids.push(@execution_query.captured_source_relation_logical_cid(identity))
  }
  let (observation, invocation) = match
    @local.issue_program_whole_sources_publication_invocation(
      owner,
      self.prepared,
      self.compiled,
      self.definition,
      captures,
      identities,
      evidences,
      logicals,
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
