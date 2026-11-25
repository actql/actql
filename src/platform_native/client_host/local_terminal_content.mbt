///|
/// Borrow of the original bounded Native generation, before any Store write.
struct NativeTerminalContent {
  work : NativeTerminalSerializationWork
  encoder : @publication.ContentByteEncoder
  input : @host.ClientSerializationInput
  evidence : @host.ClientSerializationInputEvidence
  mut output : @publication_store.NativeGeneratedContentOutput?
  demand : @local.ClientSerializationOutputDemand
  work_remaining : Int
}

///|
struct NativeTerminalSerializationWork {
  publisher : NativeLocalPublisherBinding
  access : NativeLocalValuesOriginalAccess
  start : NativeClientWorkFirstStart
  owner : @local.ClientInstalledManagedRun
  prepared : @host.PreparedClientProgram
  compiled : @host.ClientCompiledRun
}

///|
struct NativeCompletedTerminalContent {
  work : NativeTerminalSerializationWork
  generation : @host.ClientSerializationGeneration
  demand : @local.ClientSerializationOutputDemand
  work_remaining : Int
}

///|
pub(all) enum NativeTerminalContentIssue {
  TerminalContentCurrent
  TerminalContentOriginal
  TerminalContentWorkLimit
  TerminalContentPlan(@local.ClientInstalledManagedRunIssue)
  TerminalContentCompute(@connector.FixedComputeIssue)
  TerminalContentInput(@host.ClientSerializationInputIssue)
  TerminalContentEncoding(@publication.ContentSerializationIssue)
  TerminalContentIdentity(@execution.CompletedExportIssue)
  TerminalContentEvidence(@publication.RunEvidenceValueIssue)
  TerminalContentStore(@publication_store.NativePublicationStoreIssue)
  TerminalContentReference(@publication.GeneratedContentReferenceIssue)
  TerminalContentGeneration(@host.ClientSerializationGenerationIssue)
  TerminalContentFirstStart(NativeClientValuesWorkIssue)
  TerminalContentPublisher(NativeLocalPublisherBindingIssue)
  TerminalContentService(@native_publication.NativeRunPublicationIssue)
  TerminalContentPublication(
    @native_publication.NativeCapturedRunPublicationPreparationIssue
  )
}

///|
/// Claim the original submit capability and Journal transition. A prior
/// first-start cannot reopen the terminal Content continuation.
pub fn NativeLocalPublisherBinding::open_terminal_content_work(
  self : Self,
  owner : @local.ClientInstalledManagedRun,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
) -> Result[NativeTerminalSerializationWork, NativeTerminalContentIssue] {
  guard @local.terminal_serialization_run_matches(
      owner,
      self.request,
      prepared,
      compiled,
      self.definition,
    ) &&
    self.operation is Some(operation) &&
    operation.receiver.borrowed_read &&
    !operation.receiver.business_pending &&
    self.current() else {
    return Err(TerminalContentCurrent)
  }
  let access : NativeLocalValuesOriginalAccess = {
    operation,
    host: self.authority.host,
    principal: self.authority.principal,
    connection: self.authority.connection,
    request: self.request,
    primary: None,
  }
  let start = match access.claim() {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentFirstStart(issue))
  }
  guard start.definition_cid ==
    @publication.publication_contract_identity(self.definition) else {
    return Err(TerminalContentOriginal)
  }
  Ok({ publisher: self, access, start, owner, prepared, compiled, })
}

///|
fn NativeTerminalSerializationWork::current(self : Self) -> Bool {
  self.access.require_start_current(self.start) is Ok(_) &&
  self.publisher.current()
}

///|
/// The command owns cleanup of this Run's retained prefix, even when this call
/// returns an error. No I/O is done by the pure row and byte progress loops.
pub fn NativeTerminalSerializationWork::generate_terminal_content(
  self : Self,
) -> Result[NativeTerminalContent, NativeTerminalContentIssue] {
  if !self.current() {
    return Err(TerminalContentCurrent)
  }
  let publisher = self.publisher
  let compiled = self.compiled
  guard @host.client_compiled_run_serialization(compiled) is Some(graph) else {
    return Err(TerminalContentOriginal)
  }
  let (selected, prefix, demand) = match
    @local.start_installed_managed_terminal_serialization(
      self.owner,
      publisher.request,
      compiled,
      publisher.definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentPlan(issue))
  }
  let mut remaining = @local.terminal_serialization_execution_work(selected)
  let mut completed : @execution.CompletedOutput? = None
  while completed is None {
    if remaining == 0 {
      return Err(TerminalContentWorkLimit)
    }
    let granted = Int::min(32, remaining)
    let poll = match
      @local.advance_client_serialization_prefix(prefix, granted) {
      Ok(value) => value
      Err(issue) => return Err(TerminalContentCompute(issue))
    }
    let work = match poll {
      @compute_local.Complete(output, work~, ..) => {
        completed = Some(output)
        work
      }
      @compute_local.Continue(work~, ..)
      | @compute_local.Settling(_, work~, ..) => {
        if work == 0L {
          return Err(TerminalContentOriginal)
        }
        work
      }
      @compute_local.Failed(issue, ..) =>
        return Err(TerminalContentCompute(issue))
      _ => return Err(TerminalContentOriginal)
    }
    if work < 0L || work > granted.to_int64() {
      return Err(TerminalContentWorkLimit)
    }
    remaining -= work.to_int()
  }
  if !self.current() {
    return Err(TerminalContentCurrent)
  }
  let limits = demand.limits
  let encoder = match
    @host.start_client_serialization_encoder(
      graph.barrier,
      max_rows=demand.generation_rows,
      max_bytes=limits.generation_bytes,
      max_value_nodes=limits.generation_nodes,
      max_value_depth=limits.generation_depth,
      max_frames=limits.generation_frames,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentEncoding(issue))
  }
  let generated = self.encode_terminal_content(
    completed.unwrap(),
    graph,
    encoder,
    demand,
    remaining,
  )
  if generated is Err(_) {
    @publication.cancel_content_byte_encoder(encoder)
  }
  generated
}

///|
fn NativeTerminalSerializationWork::encode_terminal_content(
  self : Self,
  completed : @execution.CompletedOutput,
  graph : @host.ClientSerializationPlanGraph,
  encoder : @publication.ContentByteEncoder,
  demand : @local.ClientSerializationOutputDemand,
  allowance : Int,
) -> Result[NativeTerminalContent, NativeTerminalContentIssue] {
  let input = match
    @host.bind_client_serialization_completed_input(
      graph.barrier,
      completed,
      encoder,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentInput(issue))
  }
  let mut remaining = allowance
  let limits = demand.limits
  let selected = limits.export_limits
  let evidence = {
    let scan = match
      @host.start_client_serialization_input_identity(
        input,
        selected.values,
        selected.payload_wire,
        selected.logical_wire,
        selected.schema,
        remaining,
        limits.identity_slots,
      ) {
      Ok(value) => value
      Err(issue) => return Err(TerminalContentIdentity(issue))
    }
    defer @execution.cancel_completed_relation_identity_scan(scan) |> ignore
    let mut identified = false
    while !identified {
      if remaining == 0 {
        return Err(TerminalContentWorkLimit)
      }
      let granted = Int::min(32, remaining)
      match @execution.advance_completed_relation_identity_scan(scan, granted) {
        Ok((ready, work)) if work >= 0 && work <= granted && (ready || work > 0) => {
          remaining -= work
          identified = ready
        }
        Ok(_) => return Err(TerminalContentWorkLimit)
        Err(issue) => return Err(TerminalContentIdentity(issue))
      }
    }
    let receipt = match
      @execution.finish_completed_relation_identity_scan(scan) {
      Ok(value) => value
      Err(issue) => return Err(TerminalContentIdentity(issue))
    }
    let evidence = @host.bind_client_serialization_input_identity(
      self.compiled,
      input,
      receipt,
      limits.contract_bytes,
      limits.contract_nodes,
      limits.contract_depth,
    )
    @execution.cancel_completed_relation_export_receipt(receipt)
    match evidence {
      Ok(value) => value
      Err(issue) => return Err(TerminalContentEvidence(issue))
    }
  }
  if !self.current() {
    return Err(TerminalContentCurrent)
  }
  let output = match
    @publication_store.start_native_generated_content_output(encoder) {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentStore(issue))
  }
  let rows = @host.client_serialization_input_rows(input)
  for row in -1..<rows {
    if row >= 0 {
      match @host.start_client_serialization_input_row(input, row) {
        Ok(_) => ()
        Err(issue) => return Err(TerminalContentInput(issue))
      }
    }
    let mut complete = false
    while !complete {
      if remaining == 0 {
        return Err(TerminalContentWorkLimit)
      }
      let granted = Int::min(32, remaining)
      let (status, work) = output.advance(granted)
      if work < 0 || work > granted {
        return Err(TerminalContentWorkLimit)
      }
      remaining -= work
      match status {
        Ok(ready) if ready || work > 0 => complete = ready
        Ok(_) => return Err(TerminalContentWorkLimit)
        Err(issue) => return Err(TerminalContentEncoding(issue))
      }
    }
  }
  match @publication.finish_content_bytes(encoder) {
    Err(issue) => return Err(TerminalContentEncoding(issue))
    Ok(_) => ()
  }
  if !self.current() {
    return Err(TerminalContentCurrent)
  }
  Ok({
    work: self,
    encoder,
    input,
    evidence,
    output: Some(output),
    demand,
    work_remaining: remaining,
  })
}

///|
let terminal_content_read_bytes : Int = 4096

///|
fn native_terminal_content_policy_cid(
  fields : Array[(String, String)],
) -> String? {
  try {
    let writer = @encode.writer(1024, 16, 4)
    @encode.begin_object(writer)
    // Callers supply lexical key order, matching installed Content policy.
    for (key, value) in fields {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @sha.text_hex(@encode.finish(writer))
    .to_option()
    .map(digest => "sha256:" + digest)
  } catch {
    _ => None
  }
}

///|
/// Select the reference and the exact Store construction inventory before its
/// caller enters the existing resource-owner funding transition.
fn NativeTerminalContent::reference_selection(
  self : Self,
) -> Result[
  (
    @publication.GeneratedContentReference,
    String,
    @execution.PreparationRepresentationUnits,
  ),
  NativeTerminalContentIssue,
] {
  let publisher = self.work.publisher
  if !self.work.current() {
    return Err(TerminalContentCurrent)
  }
  guard self.output is Some(_) &&
    @publication.run_definition_lifetime(publisher.definition)
    is Some((_, expires)) &&
    @host.client_compiled_run_serialization_policy_body(self.work.compiled)
    is Some(policy) &&
    @publication.captured_effective_data_policy_classification(policy)
    is Some(classification) else {
    return Err(TerminalContentOriginal)
  }
  let scope = @host.client_request_authority_scope_cid(publisher.request)
  let authority = publisher.target_cid
  guard native_terminal_content_policy_cid([
      ("expiresAt", expires),
      ("name", "content-availability"),
      (
        "runDefinitionCid",
        @publication.publication_contract_identity(publisher.definition),
      ),
      ("storeAuthorityCid", authority),
      ("version", "actql-installed-local-policy/0.1"),
    ])
    is Some(availability) &&
    native_terminal_content_policy_cid([
      ("authorityScopeCid", scope),
      ("name", "content-issuer"),
      ("storeAuthorityCid", authority),
      ("version", "actql-installed-local-policy/0.1"),
    ])
    is Some(issuer) &&
    @host.client_serialization_byte_holding_cid(
      self.work.compiled,
      publisher.definition,
      authority,
    )
    is Some(holding) else {
    return Err(TerminalContentOriginal)
  }
  let candidate = match
    @publication.prepare_generated_content_reference(
      self.encoder,
      {
        content_store_id: publisher.namespace_id,
        content_store_cid: authority,
        workspace_scope_cid: scope,
        storage_scope: "workspace",
        retention_class: "local-content",
        expires_at: Some(expires),
        availability_evidence_cid: availability,
        effective_data_policy_cid: @publication.captured_effect_dependency_body_cid(
          policy,
        ),
        data_classification: classification,
        issuer_contract_cid: issuer,
        capture_authority_cid: scope,
      },
      self.reference_limits(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentReference(issue))
  }
  guard publisher.store.generated_content_custody_construction_inventory(
      terminal_content_read_bytes, candidate,
    )
    is Some(inventory) else {
    return Err(TerminalContentOriginal)
  }
  Ok((candidate, holding, inventory))
}

///|
fn NativeTerminalContent::reference_limits(
  self : Self,
) -> @values.ReferenceLimits {
  let limits = self.demand.limits
  {
    max_bytes: limits.reference_bytes,
    max_nodes: limits.reference_nodes,
    max_depth: limits.reference_depth,
    max_text_units: limits.reference_bytes,
  }
}

///|
/// The caller retains the exact funded Store child before entering. Require
/// current publisher, exact encoder and actual Store confirmation before the
/// existing Core issuer can produce a typed Result row.
pub fn NativeTerminalContent::persist_generation(
  self : Self,
  candidate : @publication.GeneratedContentReference,
  custody : @publication_store.CapturedContentCustody,
) -> Result[NativeCompletedTerminalContent, NativeTerminalContentIssue] {
  let publisher = self.work.publisher
  if !self.work.current() {
    return Err(TerminalContentCurrent)
  }
  guard @host.client_serialization_byte_holding_cid(
      self.work.compiled,
      publisher.definition,
      publisher.target_cid,
    )
    is Some(holding) &&
    custody.matches_generated_selection(publisher.store, candidate, holding) &&
    @publication.generated_content_reference_completion_for(
      candidate,
      self.encoder,
    )
    is Some(_) else {
    return Err(TerminalContentOriginal)
  }
  let persisted = {
    guard self.output is Some(output) else {
      return Err(TerminalContentOriginal)
    }
    custody.persist_generated_output(output)
  }
  match persisted {
    Ok(_) => self.output = None
    Err(issue) => return Err(TerminalContentStore(issue))
  }
  if !self.work.current() {
    return Err(TerminalContentCurrent)
  }
  match custody.confirm(terminal_content_read_bytes) {
    Ok(_) => ()
    Err(issue) => return Err(TerminalContentStore(issue))
  }
  let work = self.work
  let current = () => {
    work.current() && custody.matches_generated_confirmed(candidate)
  }
  let wire = @publication.generated_content_reference_wire(candidate)
  let issuer = @values.bind_reference_issuer(
    (_, original) => original == wire && current(),
    _ => current(),
  )
  let content = match
    @publication.issue_generated_content_reference(
      candidate,
      issuer,
      self.reference_limits(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentReference(issue))
  }
  match
    @host.complete_client_serialization_generation(
      self.work.compiled,
      publisher.definition,
      self.input,
      self.evidence,
      candidate,
      content,
      current,
      self.demand.limits.export_limits.values,
      256,
    ) {
    Ok(generation) =>
      Ok({
        work: self.work,
        generation,
        demand: self.demand,
        work_remaining: self.work_remaining,
      })
    Err(issue) => Err(TerminalContentGeneration(issue))
  }
}

///|
/// Pay the exact construction before returning the child. The caller keeps
/// it on the command before any of its fallible writes and verification.
pub fn NativeTerminalContent::prepare_custody(
  self : Self,
) -> Result[
  (
    @publication.GeneratedContentReference,
    @publication_store.CapturedContentCustody,
  ),
  NativeTerminalContentIssue,
] {
  let (candidate, holding, units) = match self.reference_selection() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let work = self.work
  let publisher = work.publisher
  match
    @local.fund_terminal_serialization_store(
      work.owner,
      publisher.request,
      work.compiled,
      publisher.definition,
      units,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(TerminalContentPlan(issue))
  }
  if !work.current() {
    return Err(TerminalContentCurrent)
  }
  publisher.store
  .prepare_generated_content_custody(candidate, holding)
  .map(custody => (candidate, custody))
  .map_err(issue => TerminalContentStore(issue))
}

///|
pub fn NativeCompletedTerminalContent::publication_results(
  self : Self,
  retention : @publication.PublicationContract,
  max_payload_bytes : Int64,
) -> Result[
  Array[@native_publication.NativeCapturedResultPublicationContext],
  NativeTerminalContentIssue,
] {
  let work = self.work
  let publisher = work.publisher
  guard work.current() &&
    @host.client_serialization_generation_capture_for(
      self.generation,
      work.compiled,
      publisher.definition,
    )
    is Some(content) &&
    @publication.bound_content_generation_input_relation_cid(content)
    is Some(input) &&
    @host.client_compiled_run_serialization_policy_body(work.compiled)
    is Some(policy) else {
    return Err(TerminalContentCurrent)
  }
  let policy_cid = @publication.captured_effect_dependency_body_cid(policy)
  guard @publication.issue_result_retention_for_data_policy(
      retention, policy_cid, 8192, 64, 8,
    )
    is Ok(retention) else {
    return Err(TerminalContentOriginal)
  }
  let definition_cid = @publication.publication_contract_identity(
    publisher.definition,
  )
  let plan = @publication.publication_contract_identity(
    @host.client_compiled_run_plan(work.compiled),
  )
  let results : Array[
    @native_publication.NativeCapturedResultPublicationContext,
  ] = []
  for _ in 0..<@host.prepared_client_result_count(work.prepared) {
    let material = match publisher.sample_original_generation_cid() {
      Ok(value) => value
      Err(issue) => return Err(TerminalContentPublisher(issue))
    }
    results.push({
      retention,
      computation_contract_cid: plan,
      input_relation_cids: [input],
      scope_cid: definition_cid,
      effective_data_policy_cid: policy_cid,
      store_authority_cid: publisher.target_cid,
      material_generation_cid: material,
      max_payload_bytes,
    })
  }
  Ok(results)
}

///|
pub fn NativeTerminalSerializationWork::publication_service(
  self : Self,
) -> Result[
  @native_publication.NativeRunPublicationService,
  NativeTerminalContentIssue,
] {
  let publisher = self.publisher
  let access = self.access
  install_native_client_work_publication_service(
    self.start.journal,
    self.start.request,
    publisher.definition,
    () => access.current(),
    () => access.require_start_current(self.start),
    publisher.store,
    publisher.namespace_id,
    _ => publisher.current(),
    65536,
    8192,
    64,
    request_authorize=Some((context, facts) => {
      publisher.authorize_request(context, facts)
    }),
    bind_original=Some(binding => access.bind_publication(binding)),
    fence_original=Some((binding, commit) => {
      access.fence_publication(publisher.definition, binding, commit)
    }),
  ).map_err(issue => {
    match issue {
      Work(cause) => TerminalContentFirstStart(cause)
      Journal(cause) => TerminalContentFirstStart(Journal(cause))
      Service(cause) => TerminalContentService(cause)
    }
  })
}

///|
pub fn NativeCompletedTerminalContent::prepare_publication(
  self : Self,
  service : @native_publication.NativeRunPublicationService,
  results : Array[@native_publication.NativeCapturedResultPublicationContext],
  normalization : @host.ClientLocalNormalization,
  authoring : @publication.RunEvidenceValue,
  intent : @native_publication.NativeRunPublicationIntent,
  occurrence : @native_publication.NativeRunPublicationOccurrence,
) -> Result[
  @native_publication.NativePreparedCapturedRunPublication,
  NativeTerminalContentIssue,
] {
  let work = self.work
  if !work.current() {
    return Err(TerminalContentCurrent)
  }
  let audit = match
    @host.prepared_client_local_normalization_evidence(
      work.prepared,
      normalization,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalContentFirstStart(Normalization(issue)))
  }
  @native_publication.prepare_native_terminal_serialization_publication(
    service,
    work.owner,
    work.start.request,
    work.prepared,
    work.compiled,
    self.generation,
    {
      definition: work.publisher.definition,
      normalization_journal: audit,
      binding_names: [],
      binding_digests: [],
      authoring,
    },
    results,
    intent,
    occurrence,
    self.demand,
    self.work_remaining,
  ).map_err(issue => TerminalContentPublication(issue))
}
