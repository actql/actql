///|
// Both Source and Values assembly pass original facts to the same journal
// cancellation/publication fence. No path defines its own cancellation terminal.
priv enum NativeClientWorkPublicationServiceIssue[E] {
  Work(E)
  Journal(NativeClientRunJournalIssue)
  Service(@native_publication.NativeRunPublicationIssue)
}

///|
fn[E] install_native_client_work_publication_service(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  current_authorization : () -> Bool,
  require_current : () -> Result[Unit, E],
  store : @publication_store.Store,
  namespace_id : String,
  authorize : (@native_publication.NativeRunPublicationAuthorization) -> Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @native_publication.NativeRunPublicationService,
  NativeClientWorkPublicationServiceIssue[E],
] {
  match require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  let observation = match
    install_native_client_cancellation_publication(
      store, namespace_id, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let binding = observation.binding.unwrap()
  match journal.bind_publication(request, binding, current_authorization) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  let authority = @native_publication.install_native_run_publication_authority(fact => {
    if fact.namespace_id != namespace_id ||
      fact.authority_scope_cid !=
      @host.client_request_authority_scope_cid(request) ||
      fact.run_definition_cid !=
      @publication.publication_contract_identity(definition) ||
      require_current() is Err(_) {
      false
    } else {
      authorize(fact) && require_current() is Ok(_)
    }
  })
  @native_publication.install_native_run_publication_service(
    store,
    authority,
    max_wire_bytes,
    max_nodes,
    max_depth,
    commit_guard=commit => {
      journal.fence_publication(
        request, definition, binding, current_authorization, commit,
      )
    },
  ).map_err(issue => Service(issue))
}
