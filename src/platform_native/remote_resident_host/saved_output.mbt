///|
/// One original completed Output continuation. The existing journal, Store
/// and Transfer owners retain all physical custody; this value adds no ledger.
pub struct ResidentSavedOutput {
  journal : @journal.Journal
  request : @remote.DispatchRequest
  output : @remote.RemotePollOutput
  subject : @remote.RemoteManagedOutputSubject
  payload : @payload.PublicationPayloadRequest
  current : () -> Bool
}

///|
/// Admit the original checked consumer and saved Output without selecting an
/// executor, acquiring Source, claiming start or reconstructing output bytes.
/// The caller's Site and exclusive-slot ports must inspect current ownership.
pub fn prepare_resident_saved_output(
  journal : @journal.Journal,
  site : @site.ExecutionSite,
  admission : ResidentRunAdmission,
  delegation : @resident.ResidentSiteDelegation,
  attempt : String,
  intent_key : String,
  current_time : () -> String,
  exclusive_current : () -> Bool,
) -> Result[ResidentSavedOutput, ResidentHostIssue] {
  if !exclusive_current() {
    return Err(Refused(@resident.NotCurrent))
  }
  let envelope = match journal.dispatch_envelope(attempt) {
    Ok(Some(value)) => value
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  if @remote.dispatch_request_attempt_identity(request) != Ok(attempt) {
    return Err(EnvelopeMissing)
  }
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(body) else {
    return Err(EnvelopeMissing)
  }
  let materials = match rebuild_materials(admission, request, body) {
    Ok(value) => value
    Err(issue) => return Err(Refused(issue))
  }
  let graph = @host.prepared_client_graph(materials.prepared)
  guard materials.compilation is @host.Tasks(compilation) &&
    admission.source is Some((source_ref, source_contract)) &&
    @strategy.graph_task_count(graph) == 2 &&
    !@strategy.graph_program_has_effects(graph) &&
    @host.prepared_client_acquisition_count(materials.prepared) == 1 &&
    @host.prepared_client_result_count(materials.prepared) == 1 &&
    @strategy.graph_result_task(graph, 0) == Some(1) &&
    @strategy.graph_task_target(graph, 0) is None &&
    @strategy.graph_task_target(graph, 1) is Some(_) &&
    @host.bind_client_task_run(
      materials.prepared,
      compilation,
      materials.admission,
      materials.run_definition,
    )
    is Ok(_) &&
    @host.prepared_client_source_evidence_facts(materials.prepared, 0, 0)
    is Some(facts) else {
    return Err(Refused(@resident.UnsupportedTask))
  }
  let selected = @planning.query_source_evidence_fact_values(facts)
  if selected[0] != source_ref || selected[1] != source_contract {
    return Err(Refused(@resident.ForeignSource))
  }
  let fragment = match
    @host.issue_prepared_client_task_fragment(
      materials.prepared,
      1,
      admission.limits.sequence,
      admission.limits.max_evidence_bytes,
      admission.limits.max_evidence_nodes,
      admission.limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.UnsupportedTask))
  }
  if @remote.dispatch_request_task_scope(request) !=
    (
      @publication.publication_contract_identity(materials.run_definition),
      @host.client_task_fragment_node_id(fragment),
    ) ||
    !@remote.remote_input_binding_matches_dispatch(
      @remote.remote_poll_dispatch_input_binding(dispatch),
      request,
    ) {
    return Err(Protocol(@remote.DispatchIdentityMismatch))
  }
  let scope = @remote.dispatch_request_execution_scope(request)
  let current = () => {
    exclusive_current() &&
    @site.site_key(site) == scope[0] &&
    @site.site_generation(site).to_string() == scope[1] &&
    @site.site_runtime_revision(site) == scope[2] &&
    @site.site_binding_current(
      site,
      @site.site_generation(site),
      delegation.runtime_bundle_cid,
    ) &&
    @resident.check_resident_dispatch_delegation(
      delegation,
      request,
      @site.site_generation(site),
    )
    is Ok(_) &&
    @resident.check_resident_materials_current(materials, current_time())
    is Ok(_) &&
    journal.cancellation_requested(request) is Ok(false)
  }
  if !current() {
    return Err(Refused(@resident.NotCurrent))
  }
  let observed = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard @journal.recovered_site_dispatch_evidence(observed) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(observed) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(observed) is Some(measurement) else {
    return Err(Runtime(@runtime.CompletedRestorationPending))
  }
  match
    @remote.restore_remote_runtime_completed_custody(
      @journal.recovered_site_dispatch_record(observed),
      evidence,
      subject,
      measurement,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Protocol(issue))
  }
  let output = match journal.reserved_output(request, intent_key) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Runtime(@runtime.CompletedRestorationPending))
    Err(issue) => return Err(Journal(issue))
  }
  let inventory = match
    @publication.prepare_checked_publication_inventory(
      @host.prepared_client_identity(materials.prepared).program_definition_cid,
      @host.client_task_compilation_result_names(compilation),
      [0],
    ) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.UnsupportedTask))
  }
  let result_definition = match
    @publication.checked_publication_inventory_definition_cid(inventory, 0) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.UnsupportedTask))
  }
  let selection = @remote.remote_output_intent_projection(
    @remote.remote_poll_output_intent(output),
  )
  if selection.result_definition_cid != result_definition ||
    selection.coordinator_authority != delegation.coordinator_authority {
    return Err(Protocol(@remote.DispatchIdentityMismatch))
  }
  let pending = match journal.pending_output_intents() {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let mut payload : @payload.PublicationPayloadRequest? = None
  for (key, body) in pending {
    guard output_intent_matches_dispatch(body, request) else { continue }
    guard output_intent_request(key, body) is Some(candidate) else {
      return Err(Protocol(@remote.InvalidDispatch))
    }
    if payload is Some(_) {
      return Err(Protocol(@remote.DispatchIdentityMismatch))
    }
    payload = Some(candidate)
  }
  guard payload is Some(payload) else {
    return Err(Runtime(@runtime.CompletedRestorationPending))
  }
  if !current() {
    return Err(Refused(@resident.NotCurrent))
  }
  Ok({ journal, request, output, subject, payload, current, })
}

///|
/// Exact metadata binding on the existing intent; neither requestId nor
/// payload-key equality alone authorizes another dispatch's continuation.
fn output_intent_matches_dispatch(
  body : String,
  request : @remote.DispatchRequest,
) -> Bool {
  let parsed = @json.parse(body) catch { _ => return false }
  guard parsed is Object(fields) else { return false }
  match @remote.dispatch_request_attempt_identity(request) {
    Ok(attempt) =>
      fields.get("attempt") == Some(Json::string(attempt)) &&
      fields.get("dispatch_request_cid") ==
      Some(Json::string(@remote.dispatch_request_identity(request)))
    Err(_) => false
  }
}

///|
/// Reconcile only the original committed destination and make the first real
/// report durable. The payload and intent remain owned until formal cleanup.
pub fn ResidentSavedOutput::recover(
  self : ResidentSavedOutput,
  store : @publication_store.Store,
  transfer_journal : @transfer_journal.Journal,
  client : @http.Client,
  origin : String,
  max_transfers : Int,
) -> ResidentDelivery {
  let owned = Some(self.payload)
  let failure = issue => { payload: owned, result: Err(issue), }
  if max_transfers < 1 || !(self.current)() {
    return failure(OutputUnavailable)
  }
  let key = @remote.remote_output_intent_identity(
    @remote.remote_poll_output_intent(self.output),
  )
  match self.journal.output_report(key) {
    Ok((custody, _)) if @remote.dispatch_request_identity(
        @remote.remote_output_report_custody_dispatch(custody),
      ) ==
      @remote.dispatch_request_identity(self.request) =>
      return {
        payload: owned,
        result: Ok(@remote.remote_output_report_custody_result(custody)),
      }
    Ok(_) => return failure(OutputForeign)
    Err(@journal.Physical(@sqlite.NotFound)) => ()
    Err(issue) => return failure(OutputJournal(issue))
  }
  let mut cursor = ""
  let mut selected : @transfer.RemoteTransferRequest? = None
  let mut scanned = 0
  while true {
    match transfer_journal.recover_after(cursor) {
      Ok(None) => break
      Err(issue) =>
        return failure(
          OutputTransfer(@output.Transfer(@transfer_client.Durable(issue))),
        )
      Ok(Some(value)) => {
        scanned += 1
        if scanned > max_transfers {
          return failure(OutputUnavailable)
        }
        cursor = @transfer_journal.recovered_remote_transfer_key(value)
        let candidate = @transfer.record_request(
          @transfer_journal.recovered_remote_transfer_record(value),
        )
        if @remote.prepare_remote_output_plan(
            self.output,
            self.subject,
            self.payload,
            candidate,
          )
          is Ok(_) {
          if selected is Some(_) {
            return failure(OutputForeign)
          }
          selected = Some(candidate)
        }
      }
    }
  }
  guard selected is Some(transfer) else { return failure(OutputUnavailable) }
  let selection = @remote.remote_output_intent_projection(
    @remote.remote_poll_output_intent(self.output),
  )
  if selection.transfer_route != @transfer.DirectStream ||
    selection.transfer_origin != origin ||
    !(self.current)() {
    return failure(OutputRouteRefused)
  }
  let payload = match store.reconcile_payload(self.payload) {
    Ok(Some(value)) => value
    Ok(None) => return failure(OutputUnavailable)
    Err(issue) => return failure(OutputPayloadStore(issue))
  }
  // Construct the close owner before acquiring the physical reader, so a
  // rejected source cannot strand an acquired reader.
  let retained : Ref[@publication_store.PayloadReader?] = { val: None, }
  let source = match
    @transfer_client.prepare_transfer_chunk_source(
      @transfer.request_projection(transfer)[6],
      @transfer.request_projection(transfer)[7],
      _ => Err("recovery-payload-read-refused"),
      () => Err("recovery-payload-finish-refused"),
      () => {
        match retained.val {
          Some(reader) =>
            reader.close().map_err(_ => "recovery-payload-close-pending")
          None => Err("recovery-payload-reader-unavailable")
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => return failure(OutputTransfer(@output.Transfer(issue)))
  }
  match
    store.open_payload_reader(
      @payload.publication_payload_material_identity(self.payload),
    ) {
    Ok(value) => retained.val = Some(value)
    Err(issue) => return failure(OutputPayloadStore(issue))
  }
  let record = match
    @transfer_client.reconcile_durable_direct_transfer_from_source(
      transfer_journal,
      client,
      origin,
      transfer,
      source,
      self.current,
    ) {
    Ok(value) => value
    Err(issue) => return failure(OutputTransfer(@output.TransferSend(issue)))
  }
  if !(self.current)() {
    return failure(OutputUnavailable)
  }
  let result = match
    @remote.prepare_remote_output_result(
      self.output,
      self.payload,
      payload.physical_digest,
      record,
    ) {
    Ok(value) => value
    Err(issue) => return failure(OutputProtocol(issue))
  }
  let custody = match
    @remote.prepare_remote_output_report_custody(
      self.output,
      self.payload,
      transfer,
      result,
    ) {
    Ok(value) => value
    Err(issue) => return failure(OutputProtocol(issue))
  }
  if !(self.current)() {
    return failure(OutputUnavailable)
  }
  match self.journal.retain_output_report(custody) {
    Ok(_) => { payload: owned, result: Ok(result), }
    Err(issue) => failure(OutputReportPending(custody, issue))
  }
}

///|
/// Recheck the same trusted ownership, Run lifetime and cancellation ports
/// before handing the durable report to the authenticated client.
pub fn ResidentSavedOutput::is_current(self : ResidentSavedOutput) -> Bool {
  (self.current)()
}
