///|
// Read only the entered transport retained by this Work. A reserved Run,
// missing response row or accepted cancellation is insufficient evidence.
pub fn NativeClientMockModelWork::closed_http_unknown_observed(
  self : Self,
) -> Bool {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.entry_recorded &&
    self.entry is Some(entry) &&
    self.active is Some(active) &&
    @infer.execution_stopped(active) &&
    @infer.unknown_calls(active) &&
    self.provider_role is PortableHttp(http) &&
    http.installation.runtime.model_http_load is Some(Ok(loaded)) &&
    !loaded.stopping else {
    return false
  }
  let mut pending = loaded.calls
  while pending is Some(call) {
    if physical_equal(call.capture, self.capture) &&
      call.original is Some(original) &&
      original.entry is Some(entered) &&
      physical_equal(entered, entry) &&
      original.terminal is Some(@model.PhysicalUnknown(_)) {
      return call.started &&
        call.client is None &&
        !call.stop_scope_pending &&
        call.response is None &&
        call.raw_store is None &&
        call.outcome is Some(@model.PhysicalUnknown(_))
    }
    pending = call.next_in_runtime
  }
  false
}

///|
fn NativeLocalJournalCapture::prepare_http_unknown_state_construction(
  self : Self,
  max_wire : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard self.original_resources is Some(original) &&
    @publication.run_state_observation_construction_inventory(
      max_wire, max_nodes, max_depth,
    )
    is Some((state, workspace)) &&
    observed_read_inventory_cost(state) is Some(state_bytes) &&
    observed_read_inventory_cost(workspace) is Some(workspace_bytes) &&
    @execution.checked_preparation_add_product(
      observed_read_caller_bytes, state_bytes, 1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, workspace_bytes, 1L)
    is Some(execution) else {
    return Err(ConfigurationLimit)
  }
  let block = @sqlite.publication_construction_block_bound(
    max_nodes, max_nodes, max_wire,
  )
  if block < 1L {
    return Err(ConfigurationLimit)
  }
  self
  .check_original_read_lifetime()
  .bind(_ => {
    original.host
    .prepare_domain_original_read_construction(
      original.read,
      retained,
      execution,
      block,
    )
    .map_err(issue => OriginalResources(@arena.Read(issue)))
  })
}

///|
/// Save a Core-observed, unpublished portable HTTP outcome on the original
/// Submission. The confirmed Client retirement says nothing about enclosing
/// Run cleanup. A Work with no such observation has no state to write.
pub fn NativeClientMockModelWork::retain_http_unknown_in_original_read(
  self : Self,
  publisher : NativeLocalPublisherBinding,
  reference : NativeClientSubmissionReference,
  connection : String,
  observed_at : String,
  now : Double,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !self.closed_http_unknown_observed() {
    return Err(Journal(ForeignRun))
  }
  guard publisher.authority.capture is Some(capture) &&
    physical_equal(capture, self.capture) &&
    self.provider_role is PortableHttp(http) &&
    physical_equal(http.store, publisher.store) &&
    physical_equal(self.definition, publisher.definition) &&
    @host.client_request_identity_relation(self.request, publisher.request)
    is @host.SameRequest else {
    return Err(Journal(ForeignRun))
  }
  let max_wire = 65536
  let max_nodes = 8192
  let max_depth = 64
  capture
  .prepare_http_unknown_state_construction(max_wire, max_nodes, max_depth)
  .bind(_ => {
    capture.with_current_adoption_material_in_original_read((
      host,
      _material,
      operations,
    ) => {
      let authority = match
        native_local_policy_authority_for(
          host,
          capture.crypto,
          self.principal,
          connection,
          self.request,
          ReadRunMaterials,
          capture=Some(capture),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
      let journal = host.journal
      let current_read = () => {
        authority.current_for(journal, self.request) &&
        self.closed_http_unknown_observed()
      }
      match
        journal.lookup_submitted_intent_with_operations(
          host.epoch,
          reference,
          authority.scope,
          current_read(),
          now,
          operations=Some(operations),
        ) {
        Ok(Submitted(_)) => ()
        Ok(_) => return Err(Journal(CustodyLost))
        Err(issue) => return Err(Journal(issue))
      }
      journal
      .transaction_with_reads(
        () => {
          let current = () => {
            current_read() && publisher.current_in_owned_transaction()
          }
          if !current() {
            return Err(AuthorizationDenied)
          }
          let (original, run) = match
            journal.saved_run_state_locked(
              reference,
              self.request,
              reads=Some(operations.reads),
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          if !self.matches_model_call_journal_run(run) ||
            run.run_observation_originals is None ||
            run.publication_binding != Some(publisher.store_binding) ||
            original.run_state_original is Some(_) ||
            original.run_state_observation != Some((0L, None)) {
            return Err(CustodyLost)
          }
          let publication = match
            install_native_client_cancellation_publication(
              publisher.store,
              publisher.namespace_id,
              max_wire,
              max_nodes,
              max_depth,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          if publication.binding != run.publication_binding {
            return Err(CustodyLost)
          }
          match (publication.observe)(run) {
            Ok(false) => ()
            Ok(true) => return Err(CustodyLost)
            Err(issue) => return Err(issue)
          }
          match journal.recheck_model_run_cut(self.request, operations.reads) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
          let run_id = match
            @publication.run_definition_run_id(run.definition) {
            Ok(value) => value
            Err(_) => return Err(CustodyLost)
          }
          let wire = match
            @publication.issue_effect_free_unpublished_run_state_wire(
              run_id,
              observed_at,
              @host.client_compiled_run_result_names(self.compiled),
              run.dispatch_reserved,
              false,
              max_wire,
              max_nodes,
              max_depth,
              execution_unknown=true,
            ) {
            Ok(value) => value
            Err(_) => return Err(CustodyLost)
          }
          match
            journal.retain_run_state_locked(
              original,
              run,
              wire,
              None,
              current,
              operations=Some(operations),
            ) {
            Ok(_) if current() => Ok(())
            Ok(_) => Err(AuthorizationDenied)
            Err(issue) => Err(issue)
          }
        },
        reads=Some(operations.reads),
      )
      .map_err(issue => Journal(issue))
    })
  })
}
