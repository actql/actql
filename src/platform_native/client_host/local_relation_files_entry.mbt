///|
/// Immutable Host locator/provider DATA for one actual checked Query slot.
/// The original Plan/acquisition and current Account remain the authorities.
pub(all) struct NativeRelationFileQuerySource {
  declaration : @rows.RowDeclaration
  acquisition : @rows.RowAcquisition
  provider : @row_file.NativeRelationFilePreparedProvider
  selection : @row_file.NativeRelationFileSelection
  limits : @row_file.NativeRelationFileLimits
}

///|
fn managed_relation_file_sources_match(
  managed : @local.ClientInstalledManagedRun,
  prepared : @host.PreparedClientProgram,
  request : @host.ClientRequestIdentity,
  sources : Array[NativeRelationFileQuerySource],
) -> Bool {
  guard @local.installed_managed_capture_plan(managed, prepared, request)
    is Ok(plan) &&
    !sources.is_empty() &&
    sources.length() ==
    @strategy.graph_captured_prefix(@host.prepared_client_graph(prepared)) else {
    return false
  }
  for index in 0..<sources.length() {
    let input = sources[index]
    guard @local.prepared_installed_managed_capture_acquisition(plan, index)
      is Some(acquisition) &&
      physical_equal(acquisition, input.acquisition) &&
      @rows.check_row_acquisition_original(
        acquisition,
        input.declaration,
        @rows.row_acquisition_requirement(acquisition),
      )
      is Ok(_) else {
      return false
    }
  }
  true
}

///|
// Caller-owned path arrays must not cross an imported current callback. This
// constructor is called only on the finite prefix already quoted on Read.
fn snapshot_managed_relation_file_sources(
  inputs : Array[NativeRelationFileQuerySource],
) -> Array[NativeRelationFileQuerySource] {
  inputs.map(input => NativeRelationFileQuerySource::{
    declaration: input.declaration,
    acquisition: input.acquisition,
    provider: input.provider,
    selection: {
      ..input.selection,
      items_path: input.selection.items_path.copy(),
      key_path: input.selection.key_path.map(path => path.copy()),
    },
    limits: input.limits,
  })
}

///|
/// One prepared Work entry for the SAME finite captured prefix. Input paths
/// are snapshotted only after its already-quoted original Read/Work frontier.
pub fn NativeLocalHostConnection::prepare_original_managed_relation_files_work_entry(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  managed : @local.ClientInstalledManagedRun,
  inputs : Array[NativeRelationFileQuerySource],
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
  if !managed_relation_file_sources_match(managed, prepared, request, inputs) {
    return Some(Err(relation_file_work_failure(FileWorkSourceBinding)))
  }
  guard @local.installed_managed_preparation_admission_original(
      managed, prepared, request,
    )
    is Some(admission) &&
    native_relation_files_work_control_capacity(
      inputs,
      @host.prepared_client_graph(prepared),
    )
    is Some(capacity) else {
    return Some(Err(relation_file_work_failure(FileWorkControlQuote)))
  }
  // The enclosing original Read already backs this exact finite snapshot.
  // Copy every path before canonical admission can invoke original current:
  // the callback may mutate the caller's vector, including its cardinality.
  // No subsequent constructor/quote/retention reads that mutable vector.
  let sources = snapshot_managed_relation_file_sources(inputs)
  let first = sources[0]
  let acquired = match
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
    Some(Err(issue)) =>
      return Some(Err(relation_file_work_failure(FileWorkEntry(issue))))
    Some(Ok(value)) => value
  }
  let arena = match acquired {
    @arena.ReadyNonModelWorkEntry(value)
    | @arena.PendingNonModelWorkEntry(value) => value
  }
  // The admission's current callback may revoke the original Read or Plan.
  // Recheck that SAME snapshot, not later caller replacements or path growth.
  let ready = acquired is @arena.ReadyNonModelWorkEntry(_) &&
    self.relation_file_original_read_matches(
      operation, request, prepared, compiled, definition,
    ) &&
    managed_relation_file_sources_match(managed, prepared, request, sources)
  let access : NativeLocalRelationOriginalAccess = {
    base: {
      operation,
      host: self,
      principal,
      connection,
      request,
      primary: None,
    },
    source: ManagedRelationFiles(managed, sources),
  }
  let entry : NativeClientRelationFileWorkEntry = {
    access: Some(access),
    original,
    arena,
    payload: Some((prepared, compiled, definition)),
    capacity,
    // Legacy single-entry metadata only; this purpose never uses these fields
    // for reading, quoting, evidence or publication. The complete ordered
    // snapshot above is the sole managed-prefix input inventory.
    selection: first.selection,
    limits: first.limits,
    unavailable: Err(relation_file_work_failure(Configuration)),
    unavailable_current: Err(OriginalRunNotCurrent),
    unavailable_export: Err(OriginalRunNotCurrent),
    ready,
    used: false,
    closed: false,
  }
  if ready {
    Some(Ok(entry))
  } else {
    Some(
      Err(
        relation_file_work_failure(
          match arena.prepared_capacity_failure() {
            Some(issue) => FileWorkPreparedCapacity(issue)
            None => OriginalRunNotCurrent
          },
          entry=Some(entry),
        ),
      ),
    )
  }
}
