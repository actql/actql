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
// The exact objects produced from the still-held physical captures, before
// choosing whether Source-only or Model observation owns the invocation.
priv struct NativeRelationFileWholeEvidence {
  captures : Array[@rows.RowSourceCapture]
  identities : Array[@execution_query.CapturedSourceRelationIdentity]
  evidences : Array[@publication.RunEvidenceValue]
  logicals : Array[@publication.RunEvidenceValue]
  cids : Array[String]
  scope : String
  policy : String
  started : String
  completed : String
  max_wire_bytes : Int
  max_nodes : Int
}

///|
// Exact complete-input originals for EVERY capture, never Query substitutes.
// One synchronous identity scan is retained before each fallible advance;
// already-completed evidence coexists in the same quoted metadata frontier.
fn NativeClientRelationFileWork::prepare_managed_whole_source_evidence(
  self : NativeClientRelationFileWork,
  owner : @local.ClientInstalledManagedRun,
  sources : Array[NativeRelationFileWholeSource],
  max_wire_bytes : Int,
  max_nodes : Int,
  result_controls : Int64,
  model_source_binding~ : Bool,
) -> Result[NativeRelationFileWholeEvidence, NativeClientSourceWorkIssue] {
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
  let source_count = sources.length().to_int64()
  // Base evidence retains two artifacts per Source. Model binding additionally
  // emits four order-only wires per Source and parses one fixed empty order.
  // Include all of them without depending on reclamation between validators.
  let copies = (if model_source_binding { 6L } else { 2L }) * source_count +
    (if model_source_binding { 4L } else { 3L })
  guard copies <= 2147483647L else { return Err(Configuration) }
  let binding : @execution.PreparationRepresentationUnits = if model_source_binding {
    let graph = @host.prepared_client_graph(self.prepared)
    let program = @strategy.graph_program(graph)
    let checks = @checked.source_execution_count(program).to_int64()
    let tasks = @strategy.graph_task_count(graph).to_int64()
    // A direct-occurrence inventory and one recheck per tuple each build
    // coordinate/check arrays. Per check allow selector result frames and
    // stage/task projections; port/ancestry checks borrow the checked graph.
    guard @execution.checked_preparation_add_product(
        1L,
        source_count + 1L,
        checks + tasks + 1L,
      )
      is Some(visits) &&
      @execution.checked_preparation_add_product(0L, visits, 16L)
      is Some(headers) &&
      @execution.checked_preparation_add_product(0L, headers, 2L) is Some(slots) else {
      return Err(Configuration)
    }
    {
      record_headers: headers,
      reference_slots: slots,
      scalar_words: slots,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }
  } else {
    {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }
  }
  // Two original artifacts per Source plus observation/invocation/retention;
  // the independently funded Work vectors and source/scan payloads stay live.
  guard @execution.compose_preparation_representation([
      binding,
      {
        // Per Source, same-original Stage requests Some H1/R1/W1 plus
        // graph_stage_operation_task H8/R4/W10: unit get/map Some+closure,
        // Step tag, Stage-task and task gets, owner get and returned Some.
        // Sum H9/R5/W11 = 272 logical bytes per original, before allocation;
        // no cursor/metadata phase or GC reuse supplies these products.
        // Retain the evidence and its Result beside the capture arrays. A
        // Model Work also holds one Some with the exact funded writer bounds.
        record_headers: 15L + 9L * source_count,
        reference_slots: 35L + 5L * source_count,
        scalar_words: 20L + 11L * source_count,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(controls) &&
    @execution.checked_preparation_add_product(controls, result_controls, 1L)
    is Some(controls) &&
    @host.client_protocol_metadata_construction_bytes(
      max_wire_bytes,
      max_nodes.to_int64(),
      copies=copies.to_int(),
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
  Ok({
    captures,
    identities,
    evidences,
    logicals,
    cids,
    scope,
    policy,
    started,
    completed,
    max_wire_bytes,
    max_nodes,
  })
}

///|
// Borrow the same ordered captures that entered the configured DAG. Common
// binds them to the original Model occurrence and rejects equal foreign data.
fn NativeClientRelationFileWork::admit_managed_whole_model_sources(
  self : Self,
  origin : @host.ClientInferOccurrence,
  captures : Array[@execution_query.CapturedInputSource],
  originals : Array[NativeRelationFileWholeSource],
  evidence : NativeRelationFileWholeEvidence,
) -> Result[@host.ClientInferComposedSources, NativeClientSourceWorkIssue] {
  guard self.whole_evidence is Some(original) &&
    physical_equal(original, evidence) &&
    self.execution is None else {
    return Err(FileWorkSourceBinding)
  }
  @host.admit_client_infer_composed_whole_sources(
    origin,
    captures,
    evidence.identities,
    originals.map(value => {
      @local.installed_whole_source_original(value.capacity)
    }),
    evidence.logicals,
    evidence.evidences,
    evidence.scope,
    evidence.started,
    evidence.completed,
  )
  .map_err(_ => FileWorkSourceBinding)
  .bind(binding => self.require_current().map(_ => binding))
}

///|
/// Bind the Model issuer only after its Source evidence is the exact ordered
/// inventory retained by this Work. The issuer owns all Model slot material.
pub fn NativeClientRelationFileWork::bind_model_publication(
  self : Self,
  leader : NativeClientMockModelWork,
) -> Result[Unit, NativeClientSourcePublicationIssue] {
  guard self.publication_original is None &&
    self.execution is Some(_) &&
    self.whole_evidence is Some(original) &&
    self.access.source is ManagedWholeRelationFiles(owner, _) &&
    leader.publication_inputs is None &&
    leader.provider_role is PortableHttp(_) &&
    physical_equal(leader.request, self.start.request) &&
    physical_equal(leader.compiled, self.compiled) &&
    physical_equal(leader.definition, self.definition) &&
    leader.observation is Some(issued) else {
    return Err(SourceBindingMismatch)
  }
  match self.require_current() {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  guard leader.observation_original() is Some((observation, invocation)) &&
    @infer.original_model_publication_inputs(
      issued,
      self.compiled,
      self.definition,
    )
    is Some((inputs, _) as material) &&
    @infer.observation_issuance_source_originals(issued) is Some(sources) &&
    sources.length() == original.evidences.length() else {
    return Err(SourceBindingMismatch)
  }
  for index, source in sources {
    if !physical_equal(source, original.evidences[index]) {
      return Err(SourceBindingMismatch)
    }
  }
  @local.bind_program_model_publication_invocation(
    owner,
    self.prepared,
    self.compiled,
    self.definition,
    self.run,
    observation,
    invocation,
    inputs,
    original.policy,
    whole_sources=Some({
      captures: original.captures,
      evidence: sources,
      started_at: original.started,
      completed_at: original.completed,
    }),
  )
  .map_err(issue => NativeClientSourcePublicationIssue::Work(Preparation(issue)))
  .bind(_ => {
    // Retain both edges before rechecking current for the caller. Error/close
    // retires the same aliases before returning the issuer's reservation.
    leader.publication_inputs = Some(material)
    self.publication_original = Some(
      (
        sources,
        original.logicals,
        observation,
        invocation,
        inputs,
        original.policy,
      ),
    )
    self.require_current().map_err(issue => Work(issue))
  })
}

///|
/// End the File Work's publication aliases after Store retirement, before the
/// original Model Work settles the publication reservation.
pub fn NativeClientRelationFileWork::retire_model_publication(
  self : Self,
) -> Bool {
  guard @host.client_compiled_run_has_infers(self.compiled) &&
    self.publication_original is Some((_, _, _, invocation, _, _)) else {
    return true
  }
  self.close_export()
  guard self.output_bridges is None &&
    self.access.source is ManagedWholeRelationFiles(owner, _) &&
    @local.retire_program_model_publication_invocation(owner, invocation) else {
    return false
  }
  self.publication = None
  self.publication_original = None
  true
}

///|
fn NativeClientRelationFileWork::managed_whole_publication_invocation(
  self : NativeClientRelationFileWork,
  owner : @local.ClientInstalledManagedRun,
  sources : Array[NativeRelationFileWholeSource],
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
  let evidence = match self.whole_evidence {
    Some(evidence) => {
      guard evidence.max_wire_bytes == max_wire_bytes &&
        evidence.max_nodes == max_nodes else {
        return Err(Configuration)
      }
      evidence
    }
    None =>
      match
        self.prepare_managed_whole_source_evidence(
          owner,
          sources,
          max_wire_bytes,
          max_nodes,
          result_controls,
          model_source_binding=false,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
  }
  let (observation, invocation) = match
    @local.issue_program_whole_sources_publication_invocation(
      owner,
      self.prepared,
      self.compiled,
      self.definition,
      evidence.captures,
      evidence.identities,
      evidence.evidences,
      evidence.logicals,
      evidence.scope,
      evidence.policy,
      evidence.started,
      evidence.completed,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  let original = (
    evidence.evidences,
    evidence.logicals,
    observation,
    invocation,
    evidence.cids,
    evidence.policy,
  )
  self.publication_original = Some(original)
  self.whole_evidence = None
  self.require_current().map(_ => original)
}
