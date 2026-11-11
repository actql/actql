///|
// An allocation-free correspondence guard, not permission or another receipt.
// Generic original acceptance establishes this cache in the same operation.
// Refuse absent/foreign/invalidated state rather than reseeding in business.
fn relation_file_prepared_binding_current(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  journal.operation_active &&
  !journal.fenced &&
  journal.operation_prepared_binding
  is Some((owner, run, cid, program, parameters)) &&
  physical_equal(owner, prepared) &&
  physical_equal(run, compiled) &&
  cid == @publication.publication_contract_identity(definition) &&
  program == @host.client_request_program_cid(request) &&
  parameters == @host.client_request_parameters_cid(request)
}

///|
/// Closed original-purpose projection. It retains no business Work or failure,
/// and its inert refusal carries no reference back to this entry or its token.
struct NativeClientRelationFileWorkEntry {
  mut access : NativeLocalRelationOriginalAccess?
  original : NativeLocalJournalOriginalResources
  arena : @arena.InstalledArenaNonModelWorkEntry
  mut payload : (
    @host.PreparedClientProgram,
    @host.ClientCompiledRun,
    @publication.PublicationContract,
  )?
  capacity : @execution.ExecutionCapacity
  selection : @row_file.NativeRelationFileSelection
  limits : @row_file.NativeRelationFileLimits
  unavailable : Result[
    NativeClientRelationFileWork,
    NativeClientRelationFileWorkFailure,
  ]
  unavailable_current : Result[Unit, NativeClientSourceWorkIssue]
  unavailable_export : Result[
    @host.PublicationOutputExport,
    NativeClientSourceWorkIssue,
  ]
  mut ready : Bool
  mut used : Bool
  mut closed : Bool
}

///|
// Same original Read/cache/Host correspondence for both fixed File purposes.
// Primitive observations only; no callback, allocation, recheck or grant.
fn NativeLocalHostConnection::relation_file_original_read_matches(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  let receiver = operation.receiver
  guard receiver.domain is StoreBusinessDomain(execution) &&
    receiver.ready &&
    !receiver.closed &&
    !receiver.closing &&
    receiver.primary is None &&
    receiver.capture.read_callback_active &&
    receiver.capture.read_facts_valid &&
    !receiver.capture.closing &&
    receiver.capture.read_operation_issue is None &&
    receiver.capture.opening is JournalAcquired(host) &&
    physical_equal(host, self) &&
    receiver.capture.original_resources is Some(original) &&
    receiver.original is Some(retained) &&
    physical_equal(retained, original) &&
    original.store_operation is None &&
    original.active_phase is Some(@arena.HostRead) &&
    !original.interrupted &&
    !receiver.borrowed_read &&
    !receiver.business_pending &&
    receiver.phase == StoreRouteIdle &&
    receiver.origin is None &&
    relation_file_prepared_binding_current(
      self.journal,
      request,
      prepared,
      compiled,
      definition,
    ) else {
    return false
  }
  original.host.matches_nonmodel_work_entry_read_scope(
    original.pair,
    original.read,
    execution,
  )
}

///|
/// Prepare only under this capture's already-current original Read callback.
/// The installed coordinator includes the named Read constructor inventory in
/// its consumer before admission. No business Ledger or caller Allow is taken.
pub fn NativeLocalHostConnection::prepare_original_relation_file_work_entry(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @rows.RowAcquisition,
  selection : @row_file.NativeRelationFileSelection,
  limits : @row_file.NativeRelationFileLimits,
) -> Result[
  NativeClientRelationFileWorkEntry,
  NativeClientRelationFileWorkFailure,
]? {
  if !self.relation_file_original_read_matches(
      operation, request, prepared, compiled, definition,
    ) {
    return None
  }
  let receiver = operation.receiver
  guard receiver.domain is StoreBusinessDomain(execution) &&
    receiver.original is Some(original) else {
    return None
  }
  let capacity = match
    native_relation_file_work_control_capacity(selection, limits) {
    Some(value) => value
    None => return Some(Err(relation_file_work_failure(Configuration)))
  }
  let acquired_entry = match
    original.host.prepare_domain_nonmodel_work_entry(
      original.pair,
      original.read,
      execution,
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    ) {
    None => return None
    Some(Err(_)) => return Some(Err(relation_file_work_failure(Configuration)))
    Some(Ok(value)) => value
  }
  let arena = match acquired_entry {
    @arena.ReadyNonModelWorkEntry(value)
    | @arena.PendingNonModelWorkEntry(value) => value
  }
  let ready = acquired_entry is @arena.ReadyNonModelWorkEntry(_) &&
    receiver.ready &&
    !receiver.closed &&
    !receiver.closing &&
    receiver.capture.read_callback_active &&
    receiver.capture.read_facts_valid &&
    receiver.primary is None &&
    receiver.capture.read_operation_issue is None &&
    !receiver.borrowed_read &&
    !receiver.business_pending &&
    receiver.phase == StoreRouteIdle &&
    receiver.origin is None &&
    !original.interrupted &&
    original.store_operation is None &&
    original.active_phase is Some(@arena.HostRead) &&
    receiver.original is Some(retained) &&
    physical_equal(retained, original) &&
    receiver.capture.original_resources is Some(retained) &&
    physical_equal(retained, original)
  let access : NativeLocalRelationOriginalAccess = {
    base: {
      operation,
      host: self,
      principal,
      connection,
      request,
      primary: None,
    },
    source: RelationFile(declaration, requirement, acquisition),
  }
  // Validate in the quote before making this private DATA snapshot. Strings
  // and immutable limits are borrowed; path arrays are owned copies so later
  // changes to the caller's selection cannot replace the funded input.
  let selected : @row_file.NativeRelationFileSelection = {
    ..selection,
    items_path: selection.items_path.copy(),
    key_path: selection.key_path.map(path => path.copy()),
  }
  let unavailable = Err(relation_file_work_failure(Configuration))
  let entry : NativeClientRelationFileWorkEntry = {
    access: Some(access),
    original,
    arena,
    payload: Some((prepared, compiled, definition)),
    capacity,
    selection: selected,
    limits,
    unavailable,
    unavailable_current: Err(OriginalRunNotCurrent),
    unavailable_export: Err(OriginalRunNotCurrent),
    ready,
    used: false,
    closed: false,
  }
  if ready {
    Some(Ok(entry))
  } else {
    Some(Err(relation_file_work_failure(Configuration, entry=Some(entry))))
  }
}

///|
/// Same Request/Plan Whole Source entry. The original prepared body funds its
/// complete fixed Work envelope; this cannot admit a second Run or Root.
pub fn NativeLocalHostConnection::prepare_original_whole_relation_file_work_entry(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  declaration : @rows.RowDeclaration,
  managed : @local.ClientInstalledManagedRun,
  selected_source : @local.ClientInstalledWholeSourceCapacity,
  provider : @row_file.NativeRelationFilePreparedProvider,
  selection : @row_file.NativeRelationFileSelection,
  limits : @row_file.NativeRelationFileLimits,
) -> Result[
  NativeClientRelationFileWorkEntry,
  NativeClientRelationFileWorkFailure,
]? {
  if !self.relation_file_original_read_matches(
      operation, request, prepared, compiled, definition,
    ) {
    return None
  }
  let receiver = operation.receiver
  guard receiver.domain is StoreBusinessDomain(execution) &&
    receiver.original is Some(original) else {
    return None
  }
  let source = @local.installed_whole_source_original(selected_source)
  let acquisition = @local.installed_whole_source_acquisition(selected_source)
  if !@host.client_source_acquisition_matches_program(prepared, 0, 0, source) ||
    !@local.check_installed_whole_source_capacity(
      selected_source,
      acquisition,
      provider.capacity(),
    ) ||
    !(@rows.check_row_input_acquisition_original(
      acquisition, declaration, source,
    )
    is Ok(_)) {
    return Some(Err(relation_file_work_failure(Configuration)))
  }
  guard @local.installed_managed_preparation_admission_original(
      managed, prepared, request,
    )
    is Some(admission) else {
    return Some(Err(relation_file_work_failure(OriginalRunNotCurrent)))
  }
  guard @local.installed_managed_capture_publication_geometry_original(
      managed, prepared, request,
    )
    is Some((physical_graph, _, _, _)) else {
    return Some(Err(relation_file_work_failure(OriginalRunNotCurrent)))
  }
  let capacity = match
    native_relation_whole_file_work_control_capacity(
      selection, limits, provider, physical_graph,
    ) {
    Some(value) => value
    None => return Some(Err(relation_file_work_failure(Configuration)))
  }
  let acquired_entry = match
    original.host.prepare_domain_nonmodel_prepared_work_entry(
      original.pair,
      original.read,
      execution,
      admission,
      prepared,
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    ) {
    None => return None
    Some(Err(_)) => return Some(Err(relation_file_work_failure(Configuration)))
    Some(Ok(value)) => value
  }
  let arena = match acquired_entry {
    @arena.ReadyNonModelWorkEntry(value)
    | @arena.PendingNonModelWorkEntry(value) => value
  }
  let ready = acquired_entry is @arena.ReadyNonModelWorkEntry(_) &&
    receiver.ready &&
    !receiver.closed &&
    !receiver.closing &&
    receiver.capture.read_callback_active &&
    receiver.capture.read_facts_valid &&
    receiver.primary is None &&
    receiver.capture.read_operation_issue is None &&
    !receiver.borrowed_read &&
    !receiver.business_pending &&
    receiver.phase == StoreRouteIdle &&
    receiver.origin is None &&
    !original.interrupted &&
    original.store_operation is None &&
    original.active_phase is Some(@arena.HostRead) &&
    receiver.original is Some(retained) &&
    physical_equal(retained, original) &&
    receiver.capture.original_resources is Some(retained) &&
    physical_equal(retained, original)
  let access : NativeLocalRelationOriginalAccess = {
    base: {
      operation,
      host: self,
      principal,
      connection,
      request,
      primary: None,
    },
    source: WholeRelationFile(
      declaration, source, acquisition, managed, selected_source, provider,
    ),
  }
  // Validate in the quote before making this private DATA snapshot. Strings
  // and immutable limits are borrowed; path arrays are owned copies so later
  // changes to the caller's selection cannot replace the funded input.
  let selected : @row_file.NativeRelationFileSelection = {
    ..selection,
    items_path: selection.items_path.copy(),
    key_path: selection.key_path.map(path => path.copy()),
  }
  let unavailable = Err(relation_file_work_failure(Configuration))
  let entry : NativeClientRelationFileWorkEntry = {
    access: Some(access),
    original,
    arena,
    payload: Some((prepared, compiled, definition)),
    capacity,
    selection: selected,
    limits,
    unavailable,
    unavailable_current: Err(OriginalRunNotCurrent),
    unavailable_export: Err(OriginalRunNotCurrent),
    ready,
    used: false,
    closed: false,
  }
  if ready {
    Some(Ok(entry))
  } else {
    Some(Err(relation_file_work_failure(Configuration, entry=Some(entry))))
  }
}

///|
// No callbacks or constructors before the pre-owned arena token/scope proves
// the domain for every later dynamic Result/current/failure constructor.
fn NativeClientRelationFileWorkEntry::take_entered_ledger(
  self : NativeClientRelationFileWorkEntry,
  host : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
) -> @resources.Ledger? {
  guard self.access is Some(access) &&
    self.payload is Some((prepared, compiled, definition)) else {
    return None
  }
  let original = self.original
  let receiver = operation.receiver
  if !physical_equal(operation, access.base.operation) ||
    !physical_equal(host, access.base.host) ||
    !(access.source is RelationFile(_, _, _) ||
    access.source is WholeRelationFile(_, _, _, _, _, _)) ||
    !relation_file_prepared_binding_current(
      host.journal,
      access.base.request,
      prepared,
      compiled,
      definition,
    ) ||
    !self.ready ||
    self.used ||
    self.closed ||
    !receiver.ready ||
    receiver.closed ||
    receiver.closing ||
    receiver.primary is Some(_) ||
    !receiver.borrowed_read ||
    receiver.business_pending ||
    !receiver.capture.read_callback_active ||
    receiver.capture.closing ||
    receiver.capture.read_operation_issue is Some(_) ||
    !(receiver.original is Some(retained) && physical_equal(retained, original)) ||
    !(receiver.capture.original_resources is Some(retained) &&
    physical_equal(retained, original)) ||
    !(receiver.capture.opening is JournalAcquired(retained) &&
    physical_equal(retained, host)) ||
    original.interrupted ||
    original.store_operation is Some(_) ||
    original.active_phase is Some(_) ||
    receiver.phase != StoreRouteIdle ||
    receiver.origin is Some(_) {
    return None
  }
  guard receiver.domain is StoreBusinessDomain(execution) else { return None }
  let view = self.arena.take_entered_ledger(
    execution,
    @execution.execution_capacity_retained_bytes(self.capacity),
    @execution.execution_capacity_execution_bytes(self.capacity),
  )
  if view is Some(_) {
    self.used = true
  }
  view
}

///|
/// A never-used entry has allocated only in Read and can be abandoned there.
pub fn NativeClientRelationFileWorkEntry::cancel_unclaimed_in_original_read(
  self : NativeClientRelationFileWorkEntry,
) -> Bool {
  if self.closed {
    return true
  }
  if self.used {
    return false
  }
  if !self.arena.cancel_unclaimed_in_original_read() {
    return false
  }
  self.ready = false
  self.payload = None
  self.access = None
  self.closed = true
  true
}

///|
// Release only this new projection after the existing routing owner has
// acknowledged its exact return and actual metadata close. Sticky legacy
// diagnostics remain on that owner and every escaped alias. Function return
// drops these validation temporaries before the arena tests physical retirement.
fn NativeClientRelationFileWorkEntry::retire_operation_projection(
  self : NativeClientRelationFileWorkEntry,
) -> Bool {
  guard self.access is Some(access) else { return true }
  if !self.arena.business_cleanup_complete() {
    return false
  }
  let operation = access.base.operation
  let receiver = operation.receiver
  if receiver.capture.read_callback_active ||
    receiver.borrowed_read ||
    receiver.business_pending ||
    receiver.phase != StoreRouteIdle ||
    receiver.origin is Some(_) ||
    self.original.store_operation is Some(_) ||
    self.original.active_phase is Some(_) ||
    !(receiver.original is Some(original) &&
    physical_equal(original, self.original)) {
    return false
  }
  // Already-closed metadata is accepted only through this same original close
  // method; no closed flag is a physical or scope acknowledgement by itself.
  if !receiver.closed && !(operation.pending_scope() is Ok(false)) {
    return false
  }
  match operation.close_checked() {
    Err(_) => false
    Ok(_) => {
      self.ready = false
      // This projection can outlive the original business C context while
      // its arena view waits for the parent's physical return. Drop heavy
      // Prepared/compiler/definition aliases before that retirement attempt.
      self.payload = None
      self.access = None
      true
    }
  }
}

///|
/// Existing outer cleanup only. Escaped Work/failure/operation/capture aliases
/// still retain their original diagnostics and force actual C BUSY. This entry
/// retains only its original arena authority after routing metadata retirement.
pub fn NativeClientRelationFileWorkEntry::close_after_original_return(
  self : NativeClientRelationFileWorkEntry,
) -> Bool {
  if self.closed {
    return true
  }
  if store_operation_control_clear_ffi() != 1 ||
    !self.retire_operation_projection() {
    return false
  }
  if !self.arena.close_after_original_return() {
    return false
  }
  self.closed = true
  true
}

///|
/// Read the same original Ledger snapshot without lending its mutable handle.
pub fn NativeClientRelationFileWorkEntry::usage(
  self : NativeClientRelationFileWorkEntry,
) -> @resources.LedgerUsage {
  self.arena.usage()
}
