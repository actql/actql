///|
/// Original complete input plus immutable physical locator/provider DATA.
/// Capacity is the checked Whole-family object, never a Query substitute.
pub(all) struct NativeRelationFileWholeSource {
  declaration : @rows.RowDeclaration
  capacity : @local.ClientInstalledWholeSourceCapacity
  provider : @row_file.NativeRelationFilePreparedProvider
  selection : @row_file.NativeRelationFileSelection
  limits : @row_file.NativeRelationFileLimits
  listing : @row_file.NativeRelationFileListingProvider?
}

///|
fn NativeRelationFileWholeSource::provider_capacity(
  self : Self,
) -> @execution.ExecutionCapacity {
  match self.listing {
    Some(provider) => provider.capacity()
    None => self.provider.capacity()
  }
}

///|
fn NativeRelationFileWholeSource::matches_provider(
  self : Self,
  acquisition : @rows.RowInputAcquisition,
) -> Bool {
  let listing = @rows.row_input_acquisition_is_listing(acquisition)
  match self.listing {
    Some(provider) =>
      listing &&
      provider.matches_original(
        self.declaration,
        @rows.row_input_acquisition_target_resource(acquisition),
        self.provider,
      )
    None => !listing
  }
}

///|
fn managed_relation_file_originals_match(
  original : NativeLocalWorkSourceOriginal,
  prepared : @host.PreparedClientProgram,
  request : @host.ClientRequestIdentity,
) -> Bool {
  match original {
    ManagedRelationFiles(owner, inputs) =>
      managed_relation_file_sources_match(owner, prepared, request, inputs)
    ManagedWholeRelationFiles(owner, inputs) =>
      managed_whole_relation_file_sources_match(
        owner, prepared, request, inputs,
      )
    _ => false
  }
}

///|
fn managed_whole_relation_file_sources_match(
  managed : @local.ClientInstalledManagedRun,
  prepared : @host.PreparedClientProgram,
  request : @host.ClientRequestIdentity,
  sources : Array[NativeRelationFileWholeSource],
) -> Bool {
  if sources.is_empty() {
    return false
  }
  let plan = match
    @local.installed_managed_capture_plan(managed, prepared, request) {
    Ok(value) => value
    Err(_) => return false
  }
  if @local.prepared_installed_managed_whole_source_capacity(
      plan,
      sources.length(),
    )
    is Some(_) {
    return false
  }
  for index in 0..<sources.length() {
    let input = sources[index]
    let original = @local.installed_whole_source_original(input.capacity)
    let acquisition = @local.installed_whole_source_acquisition(input.capacity)
    guard @local.prepared_installed_managed_whole_source_capacity(plan, index)
      is Some(stored) &&
      physical_equal(stored, input.capacity) &&
      input.matches_provider(acquisition) &&
      @local.check_installed_whole_source_capacity(
        input.capacity,
        acquisition,
        input.provider_capacity(),
      ) &&
      @rows.check_row_input_acquisition_original(
        acquisition,
        input.declaration,
        original,
      )
      is Ok(_) else {
      return false
    }
  }
  @local.installed_managed_preparation_admission_original(
    managed, prepared, request,
  )
  is Some(_)
}

///|
fn snapshot_managed_whole_relation_file_sources(
  inputs : Array[NativeRelationFileWholeSource],
) -> Array[NativeRelationFileWholeSource] {
  inputs.map(input => NativeRelationFileWholeSource::{
    declaration: input.declaration,
    capacity: input.capacity,
    provider: input.provider,
    selection: {
      ..input.selection,
      items_path: input.selection.items_path.copy(),
      key_path: input.selection.key_path.map(path => path.copy()),
    },
    limits: input.limits,
    listing: input.listing,
  })
}

///|
/// One prepared Work entry for the SAME finite complete-input inventory. Input paths
/// are snapshotted only after its already-quoted original Read/Work frontier.
pub fn NativeLocalHostConnection::prepare_original_managed_whole_relation_files_work_entry(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  managed : @local.ClientInstalledManagedRun,
  inputs : Array[NativeRelationFileWholeSource],
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
  if !managed_whole_relation_file_sources_match(
      managed, prepared, request, inputs,
    ) {
    return Some(Err(relation_file_work_failure(FileWorkSourceBinding)))
  }
  guard @local.installed_managed_preparation_admission_original(
      managed, prepared, request,
    )
    is Some(admission) else {
    return Some(Err(relation_file_work_failure(OriginalRunNotCurrent)))
  }
  // The original logical graph still has captured Source roots. Quote the
  // SAME Whole Plan's supplied-input physical graph, as the CLI preback and
  // existing single-Whole entry already do. This is no graph reconstruction.
  guard @local.installed_managed_capture_publication_geometry_original(
      managed, prepared, request,
    )
    is Some((physical_graph, _, _, _)) else {
    return Some(Err(relation_file_work_failure(OriginalRunNotCurrent)))
  }
  guard native_relation_whole_files_work_control_capacity(
      inputs, physical_graph,
    )
    is Some(capacity) else {
    return Some(Err(relation_file_work_failure(FileWorkControlQuote)))
  }
  // The enclosing original Read already backs this exact finite snapshot.
  // Copy every path before canonical admission can invoke original current:
  // the callback may mutate the caller's vector, including its cardinality.
  // No subsequent constructor/quote/retention reads that mutable vector.
  let sources = snapshot_managed_whole_relation_file_sources(inputs)
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
    managed_whole_relation_file_sources_match(
      managed, prepared, request, sources,
    )
  let access : NativeLocalRelationOriginalAccess = {
    base: {
      operation,
      host: self,
      principal,
      connection,
      request,
      primary: None,
    },
    source: ManagedWholeRelationFiles(managed, sources),
  }
  let entry : NativeClientRelationFileWorkEntry = {
    access: Some(access),
    original,
    arena,
    payload: Some((prepared, compiled, definition)),
    capacity,
    // Legacy single-entry metadata only; this purpose never uses these fields
    // for reading, quoting, evidence or publication. The complete ordered
    // snapshot above is the sole complete-input inventory.
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
