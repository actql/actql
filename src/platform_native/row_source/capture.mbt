///|
/// One explicitly selected read-only physical projection. These are DATA,
/// not a Source installation, Account decision, Run or permission to read.
/// The trusted Host retains and authorizes the selected declaration and path.
pub(all) struct NativeRelationFileSelection {
  directory : String
  name : String
  resource : String
  items_path : Array[String]
  key_path : Array[String]?
  primary_identity : String
}

///|
/// Selected physical decoder bounds. Independent diagnostics enforce their
/// finite component envelope; a managed caller funds its actual selected profile.
pub(all) struct NativeRelationFileLimits {
  page : @rows.RowPageLimits
  max_work : Int
  chunk_bytes : Int
  diagnostic_ceiling : Int
}

///|
pub(all) enum NativeRelationFileIssue {
  InvalidInput
  Unavailable
  ForeignOriginal
  Capacity
  FileLimit
  Filesystem(@files.NativeFilesystemIssue)
  Execution(@arena.InstalledArenaRetainedExecutionIssue)
  Resource(@resources.LedgerIssue)
  Row(@rows.RowHostIssue)
  Document(@rows.RowSourceIssue)
  Mapping(@rows.RowMappingIssue)
  ManagedRead(@local.ClientInstalledSourceReadIssue)
}

///|
priv enum NativeRelationFileAcquisition {
  FileQueryAcquisition(@rows.RowAcquisition)
  FileInputAcquisition(@rows.RowInputAcquisition)
  ManagedFileInputAcquisition(
    @rows.RowInputAcquisition,
    @local.ClientInstalledSourceRead,
    @local.ClientInstalledWholeSourceCapacity,
    @execution.ExecutionCapacity
  )
  ManagedFileListingAcquisition(
    @rows.RowInputAcquisition,
    @local.ClientInstalledSourceRead,
    @local.ClientInstalledWholeSourceCapacity,
    NativeRelationFileListingProvider
  )
}

///|
priv enum FileCapturePhase {
  Prepared
  Reading
  Received
  Listing
  Parsed
  Capturing
  Captured
  Failed
  Closing
  Closed
}

///|
/// All partial construction and cleanup stay with this same original. The
/// caller retains this object and its supplied physical domain until close
/// succeeds and all escaped capture aliases have been retired.
struct NativeRelationFileCapture {
  mut original : NativeRelationFileCapture?
  mut arena : @arena.InstalledArenaHost?
  mut execution : @arena.InstalledArenaRetainedExecution?
  mut ledger : @resources.Ledger?
  mut metadata : @resources.CapacityReservation?
  mut selection : NativeRelationFileSelection?
  limits : NativeRelationFileLimits
  mut declaration : @rows.RowDeclaration?
  mut acquisition : NativeRelationFileAcquisition?
  mut prepared_contract : @rows.RelationDocumentPreparedContract?
  mut run : @rows.RowRun?
  mut responses : @rows.RowRunResponseBorrow?
  mut root : @files.Root?
  mut rejected_root : @files.NativeRootOpenFailure?
  mut observation : @files.NativeFileObservation?
  mut reader : @files.Reader?
  mut rejected_reader : @files.NativeReaderOpenFailure?
  mut buffer : FixedArray[Byte]?
  mut bytes : Bytes?
  mut document : @rows.RelationDocument?
  mut target : @rows.RelationTargetDocument?
  mut charge : @rows.RowPageCharge?
  mut result : @rows.RowSourceCapture?
  mut offset : Int
  mut transport_complete : Bool
  mut transport_retired : Bool
  mut transient_retired : Bool
  mut phase : FileCapturePhase
  mut failure : NativeRelationFileFailure?
}

///|
/// The first issue is immutable. An acquired owner remains available only for
/// its original cleanup; returning this carrier never acknowledges retirement.
struct NativeRelationFileFailure {
  issue : NativeRelationFileIssue
  owner : NativeRelationFileCapture?
}

///|
pub fn NativeRelationFileFailure::issue(self : Self) -> NativeRelationFileIssue {
  self.issue
}

///|
pub fn NativeRelationFileFailure::retry_cleanup(
  self : Self,
) -> Result[Bool, NativeRelationFileIssue] {
  match self.owner {
    None => Ok(true)
    Some(owner) => owner.close()
  }
}

///|
priv suberror FileCaptureStop {
  FileCaptureStop(NativeRelationFileIssue)
}

///|
fn[T] file_require(
  value : Result[T, NativeRelationFileIssue],
) -> T raise FileCaptureStop {
  match value {
    Ok(value) => value
    Err(issue) => raise FileCaptureStop(issue)
  }
}

///|
fn NativeRelationFileCapture::fail(
  self : Self,
  issue : NativeRelationFileIssue,
) -> NativeRelationFileFailure {
  match self.failure {
    Some(failure) => failure
    None => {
      let failure = { issue, owner: Some(self), }
      self.failure = Some(failure)
      self.phase = Failed
      failure
    }
  }
}

///|
fn NativeRelationFileCapture::same(self : Self) -> Bool {
  self.original is Some(original) && physical_equal(original, self)
}

///|
fn NativeRelationFileCapture::current(self : Self) -> Bool {
  guard self.same() &&
    self.failure is None &&
    !(self.phase is Closing) &&
    !(self.phase is Closed) &&
    self.arena is Some(arena) &&
    self.execution is Some(execution) &&
    self.ledger is Some(ledger) else {
    return false
  }
  guard arena.borrow_domain_retained_execution_ledger(execution) is Ok(original) &&
    physical_equal(original, ledger) else {
    return false
  }
  if self.acquisition
    is Some(ManagedFileInputAcquisition(acquisition, read, selected, provider)) {
    guard @local.check_installed_source_read_ledger(read, ledger) is Ok(_) else {
      return false
    }
    // Parent currentness can synchronously retire the Native holder. This
    // final fence observes retained references only, without another callback.
    return self.same() &&
      self.failure is None &&
      !(self.phase is Closing) &&
      !(self.phase is Closed) &&
      self.ledger is Some(retained) &&
      physical_equal(retained, ledger) &&
      self.acquisition
      is Some(
        ManagedFileInputAcquisition(
          actual,
          original_read,
          original_capacity,
          original_provider
        )
      ) &&
      physical_equal(actual, acquisition) &&
      physical_equal(original_read, read) &&
      physical_equal(original_capacity, selected) &&
      physical_equal(original_provider, provider) &&
      @local.installed_whole_source_read_capacity_matches(
        read, selected, acquisition, provider,
      )
  }
  if self.acquisition
    is Some(
      ManagedFileListingAcquisition(acquisition, read, selected, provider)
    ) {
    guard @local.check_installed_source_read_ledger(read, ledger) is Ok(_) else {
      return false
    }
    return self.same() &&
      self.failure is None &&
      !(self.phase is Closing) &&
      !(self.phase is Closed) &&
      self.ledger is Some(retained) &&
      physical_equal(retained, ledger) &&
      self.acquisition
      is Some(
        ManagedFileListingAcquisition(
          actual,
          original_read,
          original_capacity,
          original_provider
        )
      ) &&
      physical_equal(actual, acquisition) &&
      physical_equal(original_read, read) &&
      physical_equal(original_capacity, selected) &&
      physical_equal(original_provider, provider) &&
      @local.installed_whole_source_read_capacity_matches(
        read,
        selected,
        acquisition,
        provider.capacity,
      )
  }
  true
}

///|
fn NativeRelationFileCapture::cleanup_entered(self : Self) -> Bool {
  guard self.same() &&
    self.arena is Some(arena) &&
    self.execution is Some(execution) else {
    return false
  }
  arena.observe_domain_retained_execution_scope(execution)
  is Ok(@bootstrap.BackedReadEntered) ||
  arena.observe_domain_retained_execution_cleanup_scope(execution)
  is Ok(@bootstrap.BackedReadEntered)
}

///|
/// Only the actual transport's completion and the same original attempt are
/// observed here. This verifier supplies no Account or journal authorization.
fn NativeRelationFileCapture::verify(
  self : Self,
  attempt : @rows.RowAttempt,
) -> Bool {
  self.current() &&
  self.transport_complete &&
  self.transport_retired &&
  self.run is Some(run) &&
  physical_equal(@rows.row_run_attempt(run), attempt)
}

///|
fn file_capture_text(value : String, maximum : Int) -> Bool {
  !value.is_empty() && value.length() <= maximum && !value.contains("\u{0000}")
}

///|
/// Bound only trusted selection DATA; this issues no original or permission.
pub fn native_relation_file_input_valid(
  value : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Bool {
  // The independent component keeps its original finite fixture envelope.
  // An admitted managed Source instead funds its selected profile below.
  file_capture_selected_input_valid(value, limits) &&
  limits.page.max_bytes <= 65536
}

///|
// Same physical implementation shape. A managed original must quote/fund the
// actual supplied byte ceiling before allocation; component maxima are not a
// second normal Source policy. All other implemented protocol bounds remain.
fn file_capture_selected_input_valid(
  value : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Bool {
  file_capture_text(value.directory, 4096) &&
  file_capture_text(value.name, 64) &&
  !value.name.contains("/") &&
  !value.name.contains("\\") &&
  value.name != "." &&
  value.name != ".." &&
  file_capture_text(value.resource, 4096) &&
  file_capture_text(value.primary_identity, 4096) &&
  value.items_path.length() > 0 &&
  value.items_path.length() <= 16 &&
  value.items_path.all(item => file_capture_text(item, 4096)) &&
  (match value.key_path {
    None => true
    Some(path) =>
      path.length() > 0 &&
      path.length() <= 16 &&
      path.all(item => file_capture_text(item, 4096))
  }) &&
  limits.page.max_bytes > 0 &&
  limits.page.max_nodes > 0 &&
  limits.page.max_nodes <= 8192 &&
  limits.page.max_depth > 0 &&
  limits.page.max_depth <= 32 &&
  limits.page.max_rows > 0 &&
  limits.page.max_rows <= 100 &&
  limits.max_work > 0 &&
  limits.max_work <= 20000000 &&
  limits.chunk_bytes > 0 &&
  limits.chunk_bytes <= 65536 &&
  limits.diagnostic_ceiling > 0 &&
  limits.diagnostic_ceiling <= 4096
}

///|
/// Trusted caller assembly only. The checked inputs and physical execution
/// were already retained and funded by their Owners. This adapter takes no
/// caller Ledger, permission callback or Node admission. It reserves its
/// complete next constructor before opening a Root or receiving file bytes.
pub fn prepare_native_relation_file_capture(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @rows.RowAcquisition,
  nonce : String,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Result[NativeRelationFileCapture, NativeRelationFileFailure] {
  if !file_capture_text(nonce, 128) ||
    !native_relation_file_input_valid(selection, limits) ||
    @rows.row_acquisition_is_listing(acquisition) {
    return Err({ issue: InvalidInput, owner: None, })
  }
  match
    @rows.check_row_acquisition_original(acquisition, declaration, requirement) {
    Err(issue) => return Err({ issue: Row(issue), owner: None, })
    Ok(_) => ()
  }
  prepare_native_relation_file_capture_original(
    arena,
    execution,
    declaration,
    @planning.query_requirement_source(requirement).0,
    FileQueryAcquisition(acquisition),
    nonce,
    selection,
    limits,
  )
}

///|
/// Open the original whole-Source acquisition on the SAME entered Native
/// execution/Ledger. Its owner retains every partial file/response through ACK.
/// The caller still supplies its actual checked Plan and current read authority.
pub fn prepare_native_relation_file_input_capture(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  acquisition : @rows.RowInputAcquisition,
  nonce : String,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Result[NativeRelationFileCapture, NativeRelationFileFailure] {
  if !file_capture_text(nonce, 128) ||
    !native_relation_file_input_valid(selection, limits) ||
    @rows.row_input_acquisition_is_listing(acquisition) {
    return Err({ issue: InvalidInput, owner: None, })
  }
  match
    @rows.check_row_input_acquisition_declaration(acquisition, declaration) {
    Err(issue) => return Err({ issue: Row(issue), owner: None, })
    Ok(_) => ()
  }
  prepare_native_relation_file_capture_original(
    arena,
    execution,
    declaration,
    @rows.row_input_acquisition_facts(acquisition).source_ref,
    FileInputAcquisition(acquisition),
    nonce,
    selection,
    limits,
  )
}

///|
/// Consume the SAME Plan-selected read/acquisition/provider and the Native
/// execution's original Ledger. No read, Run, Root or accounting view is issued.
/// The caller retains the read with its managed Run before calling this entry.
pub fn prepare_native_managed_relation_file_input_capture(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  read : @local.ClientInstalledSourceRead,
  selected : @local.ClientInstalledWholeSourceCapacity,
  provider : @execution.ExecutionCapacity,
  nonce : String,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
  prepared_provider? : NativeRelationFilePreparedProvider? = None,
) -> Result[NativeRelationFileCapture, NativeRelationFileFailure] {
  if prepared_provider is Some(original) &&
    (
      !physical_equal(original.declaration, declaration) ||
      !physical_equal(original.capacity, provider) ||
      !file_capture_provider_matches(original, selection, limits)
    ) {
    return Err({ issue: ForeignOriginal, owner: None, })
  }
  let acquisition = @local.installed_whole_source_acquisition(selected)
  if !file_capture_text(nonce, 128) ||
    !file_capture_selected_input_valid(selection, limits) ||
    @rows.row_input_acquisition_is_listing(acquisition) {
    return Err({ issue: InvalidInput, owner: None, })
  }
  if !@local.installed_whole_source_read_capacity_matches(
      read, selected, acquisition, provider,
    ) {
    return Err({ issue: ForeignOriginal, owner: None, })
  }
  match
    @rows.check_row_input_acquisition_declaration(acquisition, declaration) {
    Err(issue) => return Err({ issue: Row(issue), owner: None, })
    Ok(_) => ()
  }
  prepare_native_relation_file_capture_original(
    arena,
    execution,
    declaration,
    @rows.row_input_acquisition_facts(acquisition).source_ref,
    ManagedFileInputAcquisition(acquisition, read, selected, provider),
    nonce,
    selection,
    limits,
    prepared_provider~,
  )
}

///|
/// Consume the SAME checked listing read and Plan provider. The Source's
/// issuer is retained by its installation owner, not manufactured from rows.
/// Use advance_listing with the actual elapsed time from the original Host
/// monotonic clock; the ordinary untimed advance cannot execute this branch.
pub fn prepare_native_managed_relation_file_listing_capture(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  read : @local.ClientInstalledSourceRead,
  selected : @local.ClientInstalledWholeSourceCapacity,
  provider : NativeRelationFileListingProvider,
  nonce : String,
) -> Result[NativeRelationFileCapture, NativeRelationFileFailure] {
  let acquisition = @local.installed_whole_source_acquisition(selected)
  if !file_capture_text(nonce, 128) ||
    !@rows.row_input_acquisition_is_listing(acquisition) {
    return Err({ issue: InvalidInput, owner: None, })
  }
  if !@local.installed_whole_source_read_capacity_matches(
      read,
      selected,
      acquisition,
      provider.capacity,
    ) {
    return Err({ issue: ForeignOriginal, owner: None, })
  }
  match
    @rows.check_row_input_acquisition_declaration(
      acquisition,
      provider.declaration,
    ) {
    Err(issue) => return Err({ issue: Row(issue), owner: None, })
    Ok(_) => ()
  }
  prepare_native_relation_file_capture_original(
    arena,
    execution,
    provider.declaration,
    @rows.row_input_acquisition_facts(acquisition).source_ref,
    ManagedFileListingAcquisition(acquisition, read, selected, provider),
    nonce,
    provider.physical.selection,
    provider.physical.limits,
    prepared_provider=Some(provider.physical),
  )
}

///|
fn prepare_native_relation_file_capture_original(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  source_ref : String,
  original : NativeRelationFileAcquisition,
  nonce : String,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
  prepared_provider? : NativeRelationFilePreparedProvider? = None,
) -> Result[NativeRelationFileCapture, NativeRelationFileFailure] {
  let ledger = match arena.borrow_domain_retained_execution_ledger(execution) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Execution(issue), owner: None, })
  }
  let listing = original is ManagedFileListingAcquisition(_, _, _, _)
  let metadata_bytes = match
    file_capture_metadata_capacity(
      selection,
      limits,
      prepared_provider~,
      listing~,
    ) {
    Some(value) => value
    None => return Err({ issue: Capacity, owner: None, })
  }
  let metadata = match
    @resources.reserve_capacity(ledger, metadata_bytes, metadata_bytes) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Resource(issue), owner: None, })
  }
  let selected = {
    ..selection,
    items_path: selection.items_path.copy(),
    key_path: selection.key_path.map(path => path.copy()),
  }
  let owner : NativeRelationFileCapture = {
    original: None,
    arena: Some(arena),
    execution: Some(execution),
    ledger: Some(ledger),
    metadata: Some(metadata),
    selection: Some(selected),
    limits,
    declaration: Some(declaration),
    acquisition: Some(original),
    prepared_contract: prepared_provider.map(original => {
      original.prepared_contract
    }),
    run: None,
    responses: None,
    root: None,
    rejected_root: None,
    observation: None,
    reader: None,
    rejected_reader: None,
    buffer: None,
    bytes: None,
    document: None,
    target: None,
    charge: None,
    result: None,
    offset: 0,
    transport_complete: false,
    transport_retired: false,
    transient_retired: false,
    phase: Prepared,
    failure: None,
  }
  owner.original = Some(owner)
  try {
    let public_resource = match original {
      ManagedFileListingAcquisition(_, _, _, listing) => listing.resource
      _ => selected.resource
    }
    guard @rows.row_declaration_view(declaration, source_ref) is Some(view) &&
      view.resource == public_resource else {
      raise FileCaptureStop(ForeignOriginal)
    }
    let capacity = match original {
      ManagedFileListingAcquisition(_, _, _, listing) => listing.capacity
      _ =>
        match prepared_provider {
          Some(original) => original.capacity
          None => {
            let contract = file_require(
              @rows.relation_document_projection_contract(
                declaration,
                selected.resource,
                selected.primary_identity,
                limits.page,
              ).map_err(issue => Mapping(issue)),
            )
            let capacity = file_capture_provider_capacity(
              selected, limits, contract,
            ).unwrap_or_else(() => raise FileCaptureStop(Capacity))
            capacity
          }
        }
    }
    let run = match original {
      FileQueryAcquisition(acquisition) =>
        file_require(
          @rows.start_accounted_provider_row_acquisition(
            acquisition,
            Some(capacity),
            nonce,
            attempt => owner.verify(attempt),
            ledger,
            limits.page.max_bytes.to_int64(),
            limits.page.max_bytes.to_int64(),
          ).map_err(issue => Row(issue)),
        )
      FileInputAcquisition(acquisition) =>
        file_require(
          @rows.start_accounted_row_input_acquisition(
            acquisition,
            Some(capacity),
            nonce,
            attempt => owner.verify(attempt),
            ledger,
            limits.page.max_bytes.to_int64(),
            limits.page.max_bytes.to_int64(),
          ).map_err(issue => Row(issue)),
        )
      ManagedFileInputAcquisition(acquisition, read, selected, provider) => {
        if !@local.installed_whole_source_read_capacity_matches(
            read, selected, acquisition, provider,
          ) ||
          @execution.execution_capacity_retained_bytes(provider) <
          @execution.execution_capacity_retained_bytes(capacity) ||
          @execution.execution_capacity_execution_bytes(provider) <
          @execution.execution_capacity_execution_bytes(capacity) {
          raise FileCaptureStop(ForeignOriginal)
        }
        file_require(
          @local.start_installed_whole_source_read_rows(
            read,
            acquisition,
            nonce,
            attempt => owner.verify(attempt),
            limits.page.max_bytes.to_int64(),
            limits.page.max_bytes.to_int64(),
            expected_ledger=Some(ledger),
          ).map_err(issue => ManagedRead(issue)),
        )
      }
      ManagedFileListingAcquisition(acquisition, read, _, _) =>
        file_require(
          @local.start_installed_whole_source_read_rows(
            read,
            acquisition,
            nonce,
            attempt => owner.verify(attempt),
            limits.page.max_bytes.to_int64(),
            limits.page.max_bytes.to_int64(),
            expected_ledger=Some(ledger),
          ).map_err(issue => ManagedRead(issue)),
        )
    }
    owner.run = Some(run)
    file_require(
      @rows.begin_row_run_with_page_limits(
        run,
        limits.page,
        limits.page.max_rows,
        reference_issuer=match original {
          ManagedFileListingAcquisition(_, _, _, listing) =>
            Some(listing.issuer)
          _ => None
        },
      ).map_err(issue => Row(issue)),
    )
    let borrowed = match original {
      FileQueryAcquisition(acquisition) =>
        @rows.borrow_row_run_responses(run, acquisition)
      FileInputAcquisition(acquisition)
      | ManagedFileInputAcquisition(acquisition, _, _, _)
      | ManagedFileListingAcquisition(acquisition, _, _, _) =>
        @rows.borrow_row_input_run_responses(run, acquisition)
    }
    let responses = file_require(borrowed.map_err(issue => Row(issue)))
    owner.responses = Some(responses)
    file_require(
      @rows.bind_row_run_response_borrow_cleanup(responses, () => {
        owner.transport_retired && owner.transient_retired
      }).map_err(issue => Row(issue)),
    )
    if listing {
      file_require(
        @rows.begin_row_run_listing_request(run, None, 0L).map_err(issue => {
          Row(issue)
        }),
      )
    }
    Ok(owner)
  } catch {
    FileCaptureStop(issue) => Err(owner.fail(issue))
  }
}

///|
fn NativeRelationFileCapture::open_file(
  self : Self,
) -> Unit raise FileCaptureStop {
  let selection = self.selection.unwrap()
  file_require(
    @rows.begin_row_run_response_attempt(self.responses.unwrap()).map_err(issue => {
      Row(issue)
    }),
  )
  let root = match
    @files.open_root_in_current_read_context_with_custody(
      selection.directory,
      self.limits.diagnostic_ceiling,
    ) {
    Ok(root) => {
      self.root = Some(root)
      root
    }
    Err(failure) => {
      self.rejected_root = Some(failure)
      raise FileCaptureStop(Filesystem(failure.issue()))
    }
  }
  let observation = file_require(
    root.observe_file(selection.name).map_err(issue => Filesystem(issue)),
  )
  self.observation = Some(observation)
  let generation = file_require(
    observation.generation().map_err(issue => Filesystem(issue)),
  )
  if generation.size < 0L ||
    generation.size > self.limits.page.max_bytes.to_int64() {
    raise FileCaptureStop(FileLimit)
  }
  let reader = match observation.open_reader_with_custody() {
    Ok(reader) => {
      self.reader = Some(reader)
      reader
    }
    Err(failure) => {
      self.rejected_reader = Some(failure)
      raise FileCaptureStop(Filesystem(failure.issue()))
    }
  }
  ignore(reader)
  self.buffer = Some(FixedArray::make(generation.size.to_int(), 0))
  self.phase = Reading
}

///|
fn NativeRelationFileCapture::read_chunk(
  self : Self,
) -> Unit raise FileCaptureStop {
  let reader = self.reader.unwrap()
  let buffer = self.buffer.unwrap()
  let run = self.run.unwrap()
  let chunk = file_require(
    reader.next(self.limits.chunk_bytes).map_err(issue => Filesystem(issue)),
  )
  // Received bytes remain spent even if the next extent/generation check,
  // actual close, or caller cancellation prevents document admission. The
  // same Reader and original buffer retain the complete ordered prefix; a
  // chunk ticket alone is neither that correspondence nor Source authority.
  match self.charge {
    Some(charge) =>
      file_require(
        @rows.extend_row_run_page_charge(run, charge, chunk.bytes).map_err(issue => {
          Row(issue)
        }),
      )
    None =>
      self.charge = Some(
        file_require(
          @rows.charge_row_run_page(run, chunk.bytes).map_err(issue => {
            Row(issue)
          }),
        ),
      )
  }
  file_require(
    @rows.check_row_run_response_borrow_current(self.responses.unwrap()).map_err(issue => {
        Row(issue)
      },
    ),
  )
  if chunk.bytes.length() > buffer.length() - self.offset ||
    (chunk.bytes.is_empty() && !chunk.eof) {
    raise FileCaptureStop(FileLimit)
  }
  buffer.blit_from_bytes(self.offset, chunk.bytes, 0, chunk.bytes.length())
  self.offset += chunk.bytes.length()
  if chunk.eof {
    if self.offset != buffer.length() {
      raise FileCaptureStop(FileLimit)
    }
    file_require(
      self.observation
      .unwrap()
      .check_reader(reader)
      .map_err(issue => Filesystem(issue)),
    )
    file_require(reader.finish().map_err(issue => Filesystem(issue)))
    file_require(reader.close().map_err(issue => Filesystem(issue)))
    self.reader = None
    file_require(self.root.unwrap().close().map_err(issue => Filesystem(issue)))
    self.root = None
    self.observation = None
    self.bytes = Some(Bytes::from_array(buffer))
    self.buffer = None
    self.transport_complete = true
    self.transport_retired = true
    self.phase = Received
  }
}

///|
fn NativeRelationFileCapture::admit_response(
  self : Self,
  elapsed_ms : Int64?,
) -> Unit raise FileCaptureStop {
  let run = self.run.unwrap()
  let bytes = self.bytes.unwrap()
  file_require(
    @rows.check_row_run_response_borrow_current(self.responses.unwrap()).map_err(issue => {
        Row(issue)
      },
    ),
  )
  // Every Reader chunk extended this same original ticket. Its complete byte
  // count must match the completed document; admission never charges it again.
  guard self.charge is Some(_) else { raise FileCaptureStop(Unavailable) }
  let document = file_require(
    @rows.admit_relation_document(bytes, self.limits.page, self.limits.max_work).map_err(issue => {
        Document(issue)
      },
    ),
  )
  self.document = Some(document)
  if self.acquisition is Some(ManagedFileListingAcquisition(_, _, _, listing)) {
    guard elapsed_ms is Some(elapsed) else {
      raise FileCaptureStop(InvalidInput)
    }
    let body = file_require(
      project_native_relation_file_listing_page(
        listing.physical,
        document,
        listing.fields,
        identity => {
          let issued = (listing.issue_resource)(identity)
          // No normal work follows an issuer refusal. Keep that first Result;
          // a later current failure must not replace or rebox the original.
          if issued is Err(_) {
            return issued
          }
          if !self.current() {
            return Err(Unavailable)
          }
          issued
        },
      ),
    )
    if !self.current() {
      raise FileCaptureStop(Unavailable)
    }
    file_require(
      @rows.begin_charged_row_run_listing_page(
        run,
        self.charge.unwrap(),
        body,
        elapsed,
      ).map_err(issue => Row(issue)),
    )
    self.charge = None
    self.bytes = Some(body)
    self.phase = Listing
    return
  }
  let selected = self.selection.unwrap()
  let target = file_require(
    @rows.project_relation_target_document(
      self.document.unwrap(),
      self.declaration.unwrap(),
      selected.resource,
      selected.items_path,
      selected.key_path,
      selected.primary_identity,
      [],
      prepared_contract=self.prepared_contract,
    ).map_err(issue => Document(issue)),
  )
  self.target = Some(target)
  let accepted = match self.acquisition.unwrap() {
    FileQueryAcquisition(acquisition) =>
      @rows.accept_charged_relation_document(
        run,
        self.charge.unwrap(),
        acquisition,
        self.target.unwrap(),
        self.limits.max_work,
      )
    FileInputAcquisition(acquisition)
    | ManagedFileInputAcquisition(acquisition, _, _, _) =>
      @rows.accept_charged_relation_input_document(
        run,
        self.charge.unwrap(),
        acquisition,
        self.target.unwrap(),
        self.limits.max_work,
      )
    ManagedFileListingAcquisition(_, _, _, _) =>
      raise FileCaptureStop(InvalidInput)
  }
  file_require(accepted.map_err(issue => Row(issue))) |> ignore
  self.charge = None
  file_require(@rows.finish_row_run(run).map_err(issue => Row(issue)))
  // Only this adapter's private construction originals are discarded. The
  // admitted input owns its typed values; these marks are neither transport
  // cleanup nor acknowledgements that the physical Read has retired.
  if !@rows.discard_relation_target_document_original(self.target.unwrap()) {
    raise FileCaptureStop(ForeignOriginal)
  }
  self.target = None
  if !@rows.discard_relation_document_original(self.document.unwrap()) {
    raise FileCaptureStop(ForeignOriginal)
  }
  self.document = None
  self.bytes = None
  // The next call, after these local aliases have returned, observes retirement.
  self.phase = Parsed
}

///|
/// One bounded physical/semantic phase. Failure fences normal work permanently;
/// the returned original may only finish its child-first cleanup.
pub fn NativeRelationFileCapture::advance(
  self : Self,
  quantum : Int,
) -> Result[Bool, NativeRelationFileFailure] {
  self.advance_original(quantum, None)
}

///|
/// Actual elapsed milliseconds from the original Host monotonic observation.
/// This is protocol DATA, not currentness, permission or a replacement clock.
pub fn NativeRelationFileCapture::advance_listing(
  self : Self,
  quantum : Int,
  elapsed_ms : Int64,
) -> Result[Bool, NativeRelationFileFailure] {
  self.advance_original(quantum, Some(elapsed_ms))
}

///|
fn NativeRelationFileCapture::advance_original(
  self : Self,
  quantum : Int,
  elapsed_ms : Int64?,
) -> Result[Bool, NativeRelationFileFailure] {
  if !self.same() {
    return Err({ issue: ForeignOriginal, owner: None, })
  }
  if self.failure is Some(failure) {
    return Err(failure)
  }
  let listing = self.acquisition
    is Some(ManagedFileListingAcquisition(_, _, _, _))
  if listing != (elapsed_ms is Some(_)) ||
    (elapsed_ms is Some(elapsed) && elapsed < 0L) {
    return Err(self.fail(InvalidInput))
  }
  if quantum <= 0 || !self.current() {
    return Err(self.fail(Unavailable))
  }
  try {
    match self.phase {
      Prepared => self.open_file()
      Reading => self.read_chunk()
      Received => self.admit_response(elapsed_ms)
      Listing => {
        let poll = file_require(
          @rows.advance_row_run_listing_page(
            self.run.unwrap(),
            quantum,
            elapsed_ms.unwrap(),
          ).map_err(issue => Row(issue)),
        )
        match poll {
          @rows.ListingPageContinue(_) => ()
          @rows.ListingPageComplete(..) => {
            file_require(
              @rows.finish_row_run(self.run.unwrap()).map_err(issue => {
                Row(issue)
              }),
            )
            if !@rows.discard_relation_document_original(self.document.unwrap()) {
              raise FileCaptureStop(ForeignOriginal)
            }
            self.document = None
            self.bytes = None
            self.phase = Parsed
          }
        }
      }
      Parsed => {
        self.transient_retired = true
        file_require(
          @rows.begin_row_capture(self.run.unwrap()).map_err(issue => Row(issue)),
        )
        self.phase = Capturing
      }
      Capturing => {
        let (done, _) = file_require(
          @rows.advance_row_capture(self.run.unwrap(), quantum).map_err(issue => {
            Row(issue)
          }),
        )
        if done {
          let capture = file_require(
            @rows.capture_row_run(self.run.unwrap()).map_err(issue => Row(issue)),
          )
          self.result = Some(capture)
          self.phase = Captured
        }
      }
      Captured => ()
      Failed | Closing | Closed => raise FileCaptureStop(Unavailable)
    }
    Ok(self.phase is Captured)
  } catch {
    FileCaptureStop(issue) => Err(self.fail(issue))
  }
}

///|
/// Borrow the SAME completed capture. The caller cannot keep using it after
/// this owner closes; the Common captured source retains its original gate.
pub fn NativeRelationFileCapture::capture(
  self : Self,
) -> Result[@rows.RowSourceCapture, NativeRelationFileIssue] {
  guard self.current() && self.phase is Captured && self.result is Some(value) else {
    return Err(Unavailable)
  }
  Ok(value)
}

///|
/// Close the actual Reader/open-failure before its Root, then the original
/// accounted RowRun. No failed close, cancellation or process exit is an ACK.
pub fn NativeRelationFileCapture::close(
  self : Self,
) -> Result[Bool, NativeRelationFileIssue] {
  if self.phase is Closed {
    return Ok(true)
  }
  if !self.cleanup_entered() {
    return Err(Unavailable)
  }
  self.phase = Closing
  try {
    if self.reader is Some(reader) {
      file_require(reader.close().map_err(issue => Filesystem(issue)))
      self.reader = None
    }
    if self.rejected_reader is Some(failure) {
      file_require(failure.retry_cleanup().map_err(issue => Filesystem(issue)))
      self.rejected_reader = None
    }
    if self.root is Some(root) {
      file_require(root.close().map_err(issue => Filesystem(issue)))
      self.root = None
    }
    if self.rejected_root is Some(failure) {
      file_require(failure.retry_cleanup().map_err(issue => Filesystem(issue)))
      self.rejected_root = None
    }
    self.observation = None
    self.transport_retired = true
    if self.target is Some(target) {
      if !@rows.discard_relation_target_document_original(target) {
        raise FileCaptureStop(ForeignOriginal)
      }
    }
    self.target = None
    if self.document is Some(document) {
      if !@rows.discard_relation_document_original(document) {
        raise FileCaptureStop(ForeignOriginal)
      }
    }
    self.document = None
    self.bytes = None
    self.buffer = None
    self.transient_retired = true
    match self.acquisition {
      Some(ManagedFileInputAcquisition(_, read, _, _))
      | Some(ManagedFileListingAcquisition(_, read, _, _)) =>
        file_require(
          @local.retire_installed_source_read(read).map_err(issue => {
            ManagedRead(issue)
          }),
        )
      _ =>
        if self.run is Some(run) {
          file_require(
            @rows.close_accounted_row_run(run).map_err(issue => Row(issue)),
          )
        }
    }
    self.run = None
    self.result = None
    self.charge = None
    self.responses = None
    self.prepared_contract = None
    self.declaration = None
    self.acquisition = None
    self.selection = None
    if self.metadata is Some(token) {
      file_require(
        @resources.settle_capacity(self.ledger.unwrap(), token).map_err(issue => {
          Resource(issue)
        }),
      )
      self.metadata = None
    }
    self.ledger = None
    self.execution = None
    self.arena = None
    self.original = None
    self.failure = None
    self.phase = Closed
    Ok(true)
  } catch {
    FileCaptureStop(issue) => Err(issue)
  }
}
