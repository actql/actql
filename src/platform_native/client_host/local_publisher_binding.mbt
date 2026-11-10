///|
pub(all) enum NativeLocalPublisherBindingIssue {
  Adoption(NativeLocalAdoptionIssue)
  Journal(NativeClientRunJournalIssue)
  InvalidOriginal
  SelectionMismatch
  AuthorizationDenied
  OriginalOperation(
    NativeLocalPublisherBindingIssue?,
    NativeLocalStoreOperationIssue
  )
}

///|
// A private binding to the existing adopted Account and selected Store
// installation. It is neither a grant nor a replacement publication Owner.
struct NativeLocalPublisherBinding {
  authority : NativeLocalPolicyAuthority
  request : @host.ClientRequestIdentity
  definition : @publication.PublicationContract
  file : NativeLocalSelectedFile
  account_body : Bytes
  policy_cid : String
  namespace_id : String
  target_cid : String
  store : @publication_store.Store
  store_binding : String
  operation : NativeLocalStoreOperation?
  journal_operation : NativeLocalStoreOperation?
}

///|
// Inspect only the original installation's two publication selectors. The
// existing CLI installation reader admits its full execution configuration.
fn local_publisher_original_target(
  body : Bytes,
) -> Result[(String, String), NativeLocalPublisherBindingIssue] {
  let node = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  guard @decode.admit(node, {
      max_nodes: 8192,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    })
    is Ok(cursor) &&
    @decode.open_object(cursor) is Ok(root) &&
    @decode.required(root, "version") is Ok(version) &&
    @decode.text(version) is Ok("actql-config/0.1") &&
    @decode.required(root, "native") is Ok(native) &&
    @decode.open_object(native) is Ok(native) &&
    @decode.required(native, "run") is Ok(run) &&
    @decode.open_object(run) is Ok(run) &&
    @decode.required(run, "namespace_id") is Ok(namespace_id) &&
    @decode.text(namespace_id) is Ok(namespace_id) &&
    @decode.required(run, "store_authority_cid") is Ok(target) &&
    @decode.text(target) is Ok(target) else {
    return Err(InvalidOriginal)
  }
  if namespace_id.is_empty() ||
    namespace_id.length() > 128 ||
    !read_policy_cid(target) {
    return Err(InvalidOriginal)
  }
  Ok((namespace_id, target))
}

///|
/// Bind the real original Account policy and selected private Store. Submit
/// permission cannot install this publisher; the current Account must allow
/// the independent run/publish tuple. No Store is opened by installation.
pub fn NativeLocalHostConnection::bind_run_publisher(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  installation_file : String,
  store : @publication_store.Store,
) -> Result[NativeLocalPublisherBinding, NativeLocalPublisherBindingIssue] {
  self.bind_run_publisher_with_operations(
    crypto, principal, connection, request, definition, installation_file, store,
  )
}

///|
fn NativeLocalHostConnection::bind_run_publisher_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  installation_file : String,
  store : @publication_store.Store,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
  operation? : NativeLocalStoreOperation? = None,
  journal_operation? : NativeLocalStoreOperation? = None,
) -> Result[NativeLocalPublisherBinding, NativeLocalPublisherBindingIssue] {
  let reads = operations.map(value => value.reads)
  let current = match capture {
    None => self.check_binding()
    Some(original) => original.check_current_in_original_read()
  }
  match current {
    Ok(_) => ()
    Err(issue) => return Err(Adoption(issue))
  }
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      PublishRun,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard self.session.settings.files
    .iter()
    .find_first(file => file.name == installation_file)
    is Some(file) else {
    return Err(SelectionMismatch)
  }
  let (namespace_id, target_cid) = match
    local_publisher_original_target(file.body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (actual_target, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  if actual_target != target_cid {
    return Err(SelectionMismatch)
  }
  let store_binding = match
    installed_publication_binding(namespace_id, actual_target, device, inode) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let record = match
    self.journal.lookup_with_reads(
      request,
      authority.current_for(self.journal, request),
      reads~,
    ) {
    Ok(Retained(value)) => value
    Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
  }
  if @publication.publication_contract_identity(record.definition) !=
    @publication.publication_contract_identity(definition) {
    return Err(SelectionMismatch)
  }
  match record.publication_binding {
    None => return Err(Journal(CustodyLost))
    Some(original) =>
      if original != store_binding {
        return Err(SelectionMismatch)
      }
  }
  let binding : NativeLocalPublisherBinding = {
    authority,
    request,
    definition,
    file,
    account_body: self.session.source_body,
    policy_cid: self.session.configuration.configuration_cid(),
    namespace_id,
    target_cid,
    store,
    store_binding,
    operation,
    journal_operation,
  }
  if !binding.current() {
    return Err(AuthorizationDenied)
  }
  Ok(binding)
}

///|
/// Recheck originals and the current Account without execution or grant issue.
pub fn NativeLocalPublisherBinding::current(
  self : NativeLocalPublisherBinding,
) -> Bool {
  self.current_checked_in_mode(false)
}

///|
// Metadata CAS already owns this same Journal transaction. Joining it is
// private and cannot turn a supplied Bool into permission.
fn NativeLocalPublisherBinding::current_in_owned_transaction(
  self : NativeLocalPublisherBinding,
) -> Bool {
  if !self.authority.host.journal.transaction_active {
    return false
  }
  self.current_checked_in_mode(true)
}

///|
// A publication callback already owns the original Journal transaction. Join
// that explicit read fence; attempting another BEGIN would reject the same
// current publisher. The closed command's read-only predicates consume its
// existing operation; unscoped callers acquire their own bounded snapshot.
fn NativeClientRunJournal::publisher_current_snapshot(
  self : NativeClientRunJournal,
  current : () -> Bool,
  reads? : NativeClientJournalReadAccess? = None,
) -> Bool {
  if self.publication_read_locked {
    if !self.transaction_active ||
      self.fenced ||
      client_journal_transaction_fenced(self.database, reads) {
      return false
    }
    return current()
  }
  if self.operation_active && !self.transaction_active {
    if self.fenced || client_journal_transaction_fenced(self.database, reads) {
      return false
    }
    return current()
  }
  self.transaction_with_reads(() => Ok(current()), reads~) is Ok(true)
}

///|
fn NativeLocalPublisherBinding::current_in_mode(
  self : NativeLocalPublisherBinding,
  join_owned_transaction : Bool,
  reads? : NativeClientJournalReadAccess? = None,
) -> Bool {
  let journal = self.authority.host.journal
  if !join_owned_transaction &&
    self.authority.capture is Some(_) &&
    self.operation is Some(_) {
    // Scope, Account and selected Run belong to one private synchronous
    // predicate. Keep one existing SQLite snapshot around all of them rather
    // than opening a new target transaction after each material getter.
    return journal.publisher_current_snapshot(
      () => self.current_in_mode(true, reads~),
      reads~,
    )
  }
  if join_owned_transaction &&
    (
      (!journal.transaction_active && !journal.operation_active) ||
      journal.fenced ||
      client_journal_transaction_fenced(journal.database, reads)
    ) {
    return false
  }
  let host = self.authority.host
  // One synchronous predicate admits this exact tuple once. The retained
  // material is local; the post-read fence observes current originals again
  // without evaluating the unchanged Account tuple a second time.
  guard self.authority.current_material_for(host.journal, self.request)
    is Some(material) else {
    return false
  }
  let selected = fn() -> Result[Bytes, NativeLocalAdoptionIssue] {
    if self.authority.capture is Some(_) &&
      self.operation is Some(_) &&
      (journal.transaction_active || journal.operation_active) {
      // The current material above admits these same immutable settings in
      // this snapshot. No callback or physical dispatch separates the reads.
      for file in host.session.settings.files {
        if file.name == self.file.name {
          return Ok(file.body)
        }
      }
      Err(InvalidInput)
    } else {
      self.selected_original()
    }
  }
  if !self.authority.current_with_material_for(
      host.journal,
      self.request,
      material,
    ) ||
    host.session.source_body != self.account_body ||
    host.session.configuration.configuration_cid() != self.policy_cid ||
    !(selected() is Ok(body) && body == self.file.body) {
    return false
  }
  guard self.store.custody_location() is Ok((target, device, inode)) &&
    installed_publication_binding(self.namespace_id, target, device, inode)
    is Ok(binding) &&
    binding == self.store_binding else {
    return false
  }
  // Read only this original Run. The transaction/target reader retain their
  // physical fence and selected record custody, without a history inventory.
  let retained = if join_owned_transaction {
    host.journal.retained(self.request, reads~)
  } else {
    host.journal
    .lookup_with_reads(self.request, true, reads~)
    .map(value => {
      match value {
        Retained(value) => Some(value)
        UnresolvedHistory => None
      }
    })
  }
  guard retained is Ok(Some(record)) &&
    record.publication_binding == Some(self.store_binding) &&
    @publication.publication_contract_identity(record.definition) ==
    @publication.publication_contract_identity(self.definition) else {
    return false
  }
  @host.client_local_adopted_current_account(material, host.database) is Ok(_)
}

///|
/// Original policy reference for the existing publication request preimage.
pub fn NativeLocalPublisherBinding::publication_policy_cid(
  self : NativeLocalPublisherBinding,
) -> String {
  self.policy_cid
}

///|
/// The Native publication Owner projects the actual opaque request and index.
/// This synchronous projection contains no callback or dispatch. Its entry
/// checks the current original tuple; the following comparisons are pure.
pub fn NativeLocalPublisherBinding::authorize_request(
  self : NativeLocalPublisherBinding,
  context : @publication.PublicationRequestContext,
  facts : @native_publication.NativeRunPublicationAuthorization,
) -> Bool {
  native_timing_count(24)
  if !self.current() {
    return false
  }
  let matches = context.namespace_id == self.namespace_id &&
    context.authority_scope_cid == self.authority.scope &&
    context.run_definition_cid ==
    @publication.publication_contract_identity(self.definition) &&
    context.publication_policy_cid == self.policy_cid &&
    context.publication_target_cid == self.target_cid &&
    facts.namespace_id == context.namespace_id &&
    facts.authority_scope_cid == context.authority_scope_cid &&
    facts.run_definition_cid == context.run_definition_cid &&
    facts.publication_request_cid == context.publication_request_cid &&
    (match (facts.stage, facts.public_index_entry_cid) {
      ("request", None) | ("commit" | "return_committed", Some(_)) => true
      _ => false
    })
  matches
}
