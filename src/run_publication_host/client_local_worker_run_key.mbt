///|
/// Read-only coordinates of an already retained Run operation in its original
/// adopted Store. This is neither a worker ticket nor a launch/stop permit.
/// The physical caller keeps its original transaction, current fence and loans.
pub struct ClientLocalWorkerRunJournalKey[Store, E] {
  material : ClientLocalAdoptedHostMaterial[Store, E]
  store : Store
  request : ClientRequestIdentity
  definition_cid : String
  principal : String
  connection : String
  key : String
}

///|
pub(all) enum ClientLocalWorkerRunKeyIssue[E] {
  Current(ClientLocalAdoptedCurrentIssue[E])
  ForeignRun
  InvalidOriginal
}

///|
fn worker_run_key_matches(
  request : ClientRequestIdentity,
  definition_cid : String,
  retained : ClientRetainedRunJournalRow,
) -> Bool {
  client_request_identity_relation(request, retained.original.request) ==
  SameRequest &&
  retained.row.key == client_request_scope_cid(request) &&
  retained.row.revision >= 0L &&
  @publication.publication_contract_name(retained.original.definition) ==
  "run_definition" &&
  @publication.publication_contract_identity(retained.original.definition) ==
  definition_cid
}

///|
/// Select the existing Run lookup identity, not a DATA CID, PID, FD number or
/// counter tuple. The opaque retained row comes from the existing full Run
/// validator in this same Store snapshot. Pre-Run provisioning is not issued
/// here. Current Account authorization remains a separate mandatory Host gate.
pub fn[Store, E] bind_client_local_worker_run_journal_key(
  material : ClientLocalAdoptedHostMaterial[Store, E],
  store : Store,
  request : ClientRequestIdentity,
  retained : ClientRetainedRunJournalRow,
  principal : String,
  connection : String,
) -> Result[
  ClientLocalWorkerRunJournalKey[Store, E],
  ClientLocalWorkerRunKeyIssue[E],
] {
  let definition_cid = @publication.publication_contract_identity(
    retained.original.definition,
  )
  if !worker_run_key_matches(request, definition_cid, retained) {
    return Err(ForeignRun)
  }
  let scope_body = match
    client_local_adopted_authority_scope_body(
      material, store, principal, connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Current(issue))
  }
  if client_request_authority_scope_cid(request) !=
    "sha256:" + @sha.hex(scope_body) {
    return Err(ForeignRun)
  }
  // The adoption body binds the original journal's physical generation. The
  // operation part is the existing request Owner's lookup key. Payload changes
  // cannot select another key or turn an unknown write into a fresh operation.
  let key = "sha256:" +
    @sha.hex(material.adoption.body) +
    "/" +
    client_request_scope_cid(request)
  Ok({ material, store, request, definition_cid, principal, connection, key, })
}

///|
/// Recheck the same adopted/current Store and a fresh, fully validated retained
/// Run before returning coordinates to its existing journal transaction. These
/// coordinates convey no acceptance, COMMIT ACK, absence or retry permission.
pub fn[Store, E] client_local_worker_run_journal_coordinates(
  original : ClientLocalWorkerRunJournalKey[Store, E],
  store : Store,
  retained : ClientRetainedRunJournalRow,
) -> Result[(String, String), ClientLocalWorkerRunKeyIssue[E]] {
  if !physical_equal(original.store, store) {
    return Err(Current(ForeignStore))
  }
  if !worker_run_key_matches(
      original.request,
      original.definition_cid,
      retained,
    ) {
    return Err(ForeignRun)
  }
  let scope_body = match
    client_local_adopted_authority_scope_body(
      original.material,
      store,
      original.principal,
      original.connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Current(issue))
  }
  if client_request_authority_scope_cid(original.request) !=
    "sha256:" + @sha.hex(scope_body) {
    return Err(ForeignRun)
  }
  Ok(("client_worker_originals", original.key))
}
