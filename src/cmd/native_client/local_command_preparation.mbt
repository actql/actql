///|
// Selected by the trusted installer before its first covered acquisition. The
// complete simultaneous candidate is separate from the Crypto-only selection;
// none of these declarations provides business execution or permission.
priv struct LocalCommandPreparationProfile {
  source : String
  recipe : Bytes
  arena_bytes : Int64
  control_bytes : Int64
  host_limits : @initial_resources.LedgerLimits
  read_domain_bytes : Int64
  read_domain_limits : @initial_resources.LedgerLimits
  sqlite_domain_bytes : Int64
  sqlite_domain_limits : @initial_resources.LedgerLimits
  read_budget : @initial_arena.InstalledArenaOriginalReadBudget
  consumer_retained_bytes : Int64
  consumer_execution_bytes : Int64
  sqlite_heap_bytes : Int64
  crypto_heap_bytes : Int64
  diagnostic_ceiling : Int
  native_storage : LocalCommandNativeStorageBounds
}

///|
priv enum LocalCommandPreparationIssue {
  CommandInvalidProfile
  CommandNativeStorage(LocalCommandNativeStorageIssue)
  CommandUnavailable
  CommandRequestPreparation(@local_values.ClientRequestPreparationIssue)
  CommandHost(@initial_bootstrap.NativeBootstrapIssue)
  CommandDomain(@initial_bootstrap.NativeBackedExecutionIssue)
  CommandRead(@initial_arena.InstalledArenaOriginalReadIssue)
  CommandRetainedExecution(@initial_arena.InstalledArenaRetainedExecutionIssue)
  CommandStoreOperation(@local_host.NativeLocalStoreOperationIssue)
  CommandSavedResolution(@local_host.NativeLocalSavedEffectResolutionIssue)
  CommandBusinessChildren
  CommandSavedFileResource(@initial_resources.LedgerIssue)
  CommandSavedFileEntry(@initial_arena.InstalledArenaNonModelWorkEntryIssue)
  CommandSavedFileResume(@local_host.NativeLocalInitialHostAttestationIssue)
  CommandSavedEffectPublication(
    @local_host.NativeLocalSavedEffectPublicationIssue
  )
  CommandSavedEffectOutput(@local_publication.NativePublicationOutputIssue)
  CommandSavedEffectCompletion(LocalSavedEffectCompletionIssue)
  CommandBusinessSource(@row_file.NativeRelationFileIssue)
  CommandBusinessSourceIdentity(LocalNativeMockSourceIdentityIssue)
  CommandBusinessModel(@local_host.NativeClientMockModelIssue)
  CommandBusinessModelGraph(@local_values.ClientRequestProgramPlanIssue)
  CommandBusinessEffectProposals(LocalNativeMockEffectProposalIssue)
  CommandBusinessEffectAcceptance(
    @local_host.NativeClientSubmittedEffectMaterialsIssue
  )
  CommandBusinessPublication
  CommandBusinessStore(@local_store.NativePublicationStoreIssue)
  CommandRunObservationPending
  CommandRunObservationStore(@local_store.NativePublicationStoreIssue)
  CommandBusinessResult(@local_result.NativeResultAccessIssue)
  CommandBusinessFileOutput(@local_host.NativeLocalReadBindingIssue)
  CommandSqlite(@initial_arena.InstalledArenaSqliteIssue)
  CommandPair(@initial_arena.InstalledArenaLocalHostResourcesIssue)
  CommandRuntime(@local_host.NativeLocalPackagedRuntimeIssue)
  CommandComponent(@initial_arena.InstalledArenaCryptoIssue)
  CommandReadCrypto(@initial_arena.InstalledArenaLocalHostCryptoIssue)
  CommandSignature(@local_crypto.NativeSignatureIssue)
  CommandJournal(@local_host.NativeLocalJournalCaptureIssue)
  CommandAdoption(@local_host.NativeLocalAdoptionIssue)
  CommandCapture(@local_host.NativeLocalAdoptionCaptureIssue)
  CommandApplication(String)
  CommandProjectMock(LocalProjectMockModelIssue)
  CommandFilesystem(@files.NativeBoundedTextIssue)
  CommandFilesystemCleanup(@local_filesystem.NativeFilesystemIssue)
}

///|
priv suberror LocalCommandPreparationStop {
  LocalCommandPreparationStop(LocalCommandPreparationIssue)
}

///|
fn[T] command_preparation_value(
  result : Result[T, LocalCommandPreparationIssue],
) -> T raise LocalCommandPreparationStop {
  match result {
    Ok(value) => value
    Err(issue) => raise LocalCommandPreparationStop(issue)
  }
}

///|
// A caller retention record in the existing installer, not a replacement
// Host/Journal/Resource Owner. Publish this original before acquiring anything.
priv struct LocalCommandPreparationOriginal {
  profile : LocalCommandPreparationProfile
  native_storage : LocalCommandNativeStorageQuote
  business : LocalCommandBusinessOriginal?
  extent_diagnostics : Bool
  mut read_inventory_recorded : Bool
  mut business_inventory_recorded : Bool
  mut run_observation : LocalCommandRunObservationOriginal?
  mut project : LocalProjectConfiguration?
  cancellation_recovery : Ref[String?]
  mut host : @initial_arena.InstalledArenaHost?
  mut backing_scope : @initial_arena.InstalledArenaBackingBorrow?
  mut backing_entered : Bool
  mut read_domain : @initial_arena.InstalledArenaDomain?
  mut sqlite_domain : @initial_arena.InstalledArenaDomain?
  mut read : @initial_arena.InstalledArenaOriginalRead?
  // Retain the original joined Read consumer until its existing cleanup ACK.
  mut _retained_consumer : @initial_arena.InstalledArenaOriginalReadConsumer?
  mut sqlite : @initial_arena.InstalledArenaSqliteLibrary?
  mut pair : @initial_arena.InstalledArenaLocalHostResources?
  mut runtime : @local_host.NativeLocalPackagedRuntime?
  mut crypto_path : String
  mut crypto_member : @local_filesystem.NativeObservedComponentMember?
  mut component : @initial_arena.InstalledArenaCryptoComponent?
  mut outer_library : @local_crypto.Library?
  mut inner_library : @local_crypto.Library?
  mut operator_host : @local_host.NativeLocalOperatorHostCapture?
  mut operator_host_wire : String?
  mut product : @local_host.NativeLocalProductConfigurationCapture?
  mut initial_product_selected : Bool
  mut adoption : @local_host.NativeLocalAdoptionCapture?
  mut product_parent : @local_filesystem.Root?
  mut product_parent_failure : @local_filesystem.NativeRootOpenFailure?
  mut selected_root : @local_filesystem.Root?
  mut selected_root_failure : @local_filesystem.NativeRootOpenFailure?
  mut journal : @local_host.NativeLocalJournalCapture?
  mut journal_read_open : Bool
  mut reply_outcome : Result[String, String]?
  mut read_failure : @files.NativeBoundedTextFailure?
  mut phase_open : Bool
  mut standalone_cleanup_open : Bool
  mut primary : LocalCommandPreparationIssue?
  mut closing : Bool
  mut closed : Bool
  mut cleanup_stage : String
}

///|
fn prepare_local_command_preparation_original(
  profile : LocalCommandPreparationProfile,
  business? : LocalCommandBusinessProfile? = None,
) -> Result[LocalCommandPreparationOriginal, LocalCommandPreparationIssue] {
  if profile.source.length() != 40 ||
    profile.recipe.length() != 32 ||
    profile.arena_bytes <= 0L ||
    profile.control_bytes <= 0L ||
    profile.read_domain_bytes <= 0L ||
    profile.sqlite_domain_bytes <= 0L ||
    profile.read_domain_bytes > profile.arena_bytes ||
    profile.sqlite_domain_bytes >
    profile.arena_bytes - profile.read_domain_bytes ||
    profile.host_limits.execution_bytes != profile.arena_bytes ||
    profile.read_domain_limits.execution_bytes > profile.read_domain_bytes ||
    profile.sqlite_domain_limits.execution_bytes > profile.sqlite_domain_bytes ||
    profile.consumer_retained_bytes <= 0L ||
    profile.consumer_execution_bytes <= 0L ||
    profile.crypto_heap_bytes <= 0L ||
    profile.sqlite_heap_bytes <= 0L ||
    profile.diagnostic_ceiling <= 0 ||
    profile.diagnostic_ceiling > 4096 {
    return Err(CommandInvalidProfile)
  }
  if business is Some(candidate) {
    match candidate.kind {
      SourceFreeCompute | SavedEffectApply =>
        if candidate.domain_bytes <= 0L ||
          candidate.payload_facility_bytes <= 0L ||
          profile.control_bytes >
          profile.arena_bytes -
          profile.read_domain_bytes -
          profile.sqlite_domain_bytes ||
          candidate.domain_bytes >
          profile.arena_bytes -
          profile.read_domain_bytes -
          profile.sqlite_domain_bytes -
          profile.control_bytes ||
          candidate.limits.retained_bytes < 0L ||
          candidate.limits.execution_bytes < 0L ||
          candidate.limits.retained_bytes > candidate.payload_facility_bytes ||
          candidate.limits.execution_bytes >
          candidate.payload_facility_bytes - candidate.limits.retained_bytes {
          return Err(CommandInvalidProfile)
        }
      SavedResultRead =>
        if candidate.domain_bytes != 0L ||
          candidate.payload_facility_bytes != 0L ||
          candidate.limits.planning_work != 0 ||
          candidate.limits.attempts != 0 ||
          candidate.limits.holdings != 0 ||
          candidate.limits.transfer_bytes != 0L ||
          candidate.limits.retained_bytes != 0L ||
          candidate.limits.execution_bytes != 0L {
          return Err(CommandInvalidProfile)
        }
    }
  }
  let native_storage = match quote_local_command_native_storage(profile) {
    Err(issue) => return Err(CommandNativeStorage(issue))
    Ok(value) => value
  }
  match require_native_command_platform_original() {
    Err(issue) => return Err(CommandNativeStorage(issue))
    Ok(_) => ()
  }
  Ok({
    profile,
    native_storage,
    extent_diagnostics: @env.get_env_var("ACTQL_NATIVE_TIMINGS") == Some("1"),
    read_inventory_recorded: false,
    business_inventory_recorded: false,
    run_observation: None,
    project: None,
    cancellation_recovery: Ref(None),
    business: business.map(candidate => {
      profile: candidate,
      selected_profile: None,
      initial_window_bytes: None,
      initial_domain_bytes: None,
      domain: None,
      execution: None,
      operation: None,
      request_input: None,
      request_intent: None,
      request_intake_units: 0L,
      request_read_failure: None,
      request_initial: None,
      request_parent: None,
      request_body: None,
      request_run: None,
      request_retiring: false,
      model_work: [],
      effect_model: None,
      saved_effect_rows: [],
      saved_effect_files: None,
      values_work: None,
      values_failure: None,
      store: None,
      store_failure: None,
      store_parent: None,
      store_parent_failure: None,
      store_root: None,
      store_root_failure: None,
      store_root_operation: None,
      publication_publisher: None,
      _retained_publication_service: None,
      publication_results: None,
      publication_pending: None,
      publication_failure: None,
      _retained_publication_commit_failure: None,
      _retained_publication_cleanup_failure: None,
      publication_attempted: false,
      publication_result: None,
      run_receipt_original: None,
      publication_retired: false,
      result_binding: None,
      result_service: None,
      result_session: None,
      result_material: None,
      result_sink: None,
      result_refusal: None,
      result_cleanup_issue: None,
      active: false,
    }),
    host: None,
    backing_scope: None,
    backing_entered: false,
    read_domain: None,
    sqlite_domain: None,
    read: None,
    _retained_consumer: None,
    sqlite: None,
    pair: None,
    runtime: None,
    crypto_path: "",
    crypto_member: None,
    component: None,
    outer_library: None,
    inner_library: None,
    operator_host: None,
    operator_host_wire: None,
    product: None,
    initial_product_selected: false,
    adoption: None,
    product_parent: None,
    product_parent_failure: None,
    selected_root: None,
    selected_root_failure: None,
    journal: None,
    journal_read_open: false,
    reply_outcome: None,
    read_failure: None,
    phase_open: false,
    standalone_cleanup_open: false,
    primary: None,
    closing: false,
    closed: false,
    cleanup_stage: "not-started",
  })
}

///|
fn LocalCommandPreparationOriginal::retain_primary(
  self : LocalCommandPreparationOriginal,
  issue : LocalCommandPreparationIssue,
) -> Unit {
  if self.primary is None {
    self.primary = Some(issue)
  }
}

///|
// Only the one physical constructor is attempted. Every partial domain/read/
// Library is retained before the next call; a failure does not select a retry.
fn LocalCommandPreparationOriginal::acquire(
  self : LocalCommandPreparationOriginal,
  root : String,
  source : String,
  platform : String,
  manifest_digest : String,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.host is Some(_) ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) ||
    source != self.profile.source {
    return Err(CommandUnavailable)
  }
  let result = match self.acquire_physical_read() {
    Err(issue) => Err(issue)
    Ok(_) => self.acquire_runtime(root, source, platform, manifest_digest)
  }
  if result is Err(issue) {
    self.retain_primary(issue)
  }
  result
}

///|
// Called only after the bounded original Command parse returns successfully.
// Help, version and parse failure must never construct this physical original.
fn LocalCommandPreparationOriginal::acquire_physical_read(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  native_timing_begin(9)
  defer native_timing_end(9)
  if self.host is Some(_) ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) {
    return Err(CommandUnavailable)
  }
  try {
    let profile = self.profile
    // Preserve the immutable maximum profile. The initial Read funds only
    // the existing first processing block and its actually coheld originals.
    let read_budget = self.initial_read_budget()
    let initial_pool = command_preparation_value(
      native_storage_sum([
        read_budget.bootstrap_retained,
        read_budget.bootstrap_execution,
        read_budget.workspace_execution,
        read_budget.read_retained,
        read_budget.read_execution,
      ]).map_err(issue => CommandNativeStorage(issue)),
    )
    let read_domain_bytes = command_preparation_option(
      local_command_domain_bytes(initial_pool),
    )
    let initial_domains = command_preparation_value(
      native_storage_sum([read_domain_bytes, profile.sqlite_domain_bytes]).map_err(issue => {
          CommandNativeStorage(issue)
        },
      ),
    )
    let (arena_bytes, _) = command_preparation_option(
      local_command_backing_layout(initial_domains),
    )
    if read_domain_bytes > profile.read_domain_bytes ||
      arena_bytes > profile.arena_bytes {
      return Err(CommandInvalidProfile)
    }
    let host = command_preparation_value(
      @initial_arena.prepare_installed_arena_host(
        profile.source,
        profile.recipe,
        1L,
        arena_bytes,
        profile.host_limits,
        profile.control_bytes,
      ).map_err(issue => CommandHost(issue)),
    )
    // Retain the actual original before its one anonymous mapping attempt.
    // Failure stays with this Host; it cannot select another backing backend.
    self.host = Some(host)
    command_preparation_value(
      host.acquire().map_err(issue => CommandHost(issue)),
    )
    let scope = command_preparation_value(
      host.borrow_backing().map_err(issue => CommandHost(issue)),
    )
    self.backing_scope = Some(scope)
    command_preparation_value(
      host
      .enter_backing_borrow_scope(scope)
      .map_err(issue => CommandHost(issue)),
    )
    self.backing_entered = true
    let domain_work_before = self.observe_extent_work(host, scope)
    let acquired = command_preparation_value(
      host
      .prepare_domain_in_process(
        scope,
        read_domain_bytes,
        profile.read_domain_limits,
        initial_window=Some(initial_pool),
      )
      .map_err(issue => CommandDomain(issue)),
    )
    let read_domain = match acquired {
      PreparedDomain(value) => value
      PendingDomain(value, issue) => {
        self.read_domain = Some(value)
        return Err(CommandDomain(issue))
      }
    }
    self.read_domain = Some(read_domain)
    command_preparation_value(
      host.transfer_domain(read_domain).map_err(issue => CommandDomain(issue)),
    )
    let acquired = command_preparation_value(
      host
      .prepare_domain_in_process(
        scope,
        profile.sqlite_domain_bytes,
        profile.sqlite_domain_limits,
      )
      .map_err(issue => CommandDomain(issue)),
    )
    let sqlite_domain = match acquired {
      PreparedDomain(value) => value
      PendingDomain(value, issue) => {
        self.sqlite_domain = Some(value)
        return Err(CommandDomain(issue))
      }
    }
    self.sqlite_domain = Some(sqlite_domain)
    command_preparation_value(
      host.transfer_domain(sqlite_domain).map_err(issue => CommandDomain(issue)),
    )
    record_command_extent_work(
      domain_work_before,
      self.observe_extent_work(host, scope),
      49,
    )
    command_preparation_value(
      host
      .leave_backing_borrow_scope(scope)
      .map_err(issue => CommandHost(issue)),
    )
    self.backing_entered = false
    command_preparation_value(
      host.return_backing_borrow(scope).map_err(issue => CommandHost(issue)),
    )
    self.backing_scope = None
    // The facility ceiling belongs to this same original lease BEFORE its
    // first context/control allocation. It cannot be installed at a later
    // consuming phase or inferred from the domain's remaining allowance.
    let read_preparation = match self.native_storage.read_facility_ceiling {
      Some(ceiling) =>
        host.prepare_domain_read(read_domain, execution_ceiling=ceiling)
      None => host.prepare_domain_read(read_domain)
    }
    command_preparation_value(
      read_preparation.map_err(issue => CommandDomain(issue)),
    )
    let sqlite_preparation = match
      self.native_storage.sqlite_domain_facility_ceiling {
      Some(ceiling) =>
        host.prepare_domain_read(sqlite_domain, execution_ceiling=ceiling)
      None => host.prepare_domain_read(sqlite_domain)
    }
    command_preparation_value(
      sqlite_preparation.map_err(issue => CommandDomain(issue)),
    )
    let acquired = command_preparation_value(
      host
      .prepare_domain_original_read(read_domain, read_budget)
      .map_err(issue => CommandRead(issue)),
    )
    let read = match acquired {
      ReadyOriginalRead(value) => value
      PendingOriginalRead(value, issue) => {
        self.read = Some(value)
        return Err(CommandRead(issue))
      }
    }
    self.read = Some(read)
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// The same already acquired Read admits the full original Runtime. Its
// allocations remain in that same domain when the one consumer pair is bound;
// no second backing, Host, Read claim, or refill is constructed here.
fn LocalCommandPreparationOriginal::acquire_runtime(
  self : LocalCommandPreparationOriginal,
  root : String,
  source : String,
  platform : String,
  manifest_digest : String,
) -> Result[Unit, LocalCommandPreparationIssue] {
  native_timing_begin(10)
  defer native_timing_end(10)
  if self.closing ||
    self.closed ||
    self.primary is Some(_) ||
    self.runtime is Some(_) ||
    self.pair is Some(_) ||
    source != self.profile.source ||
    self.native_storage.source != source {
    return Err(CommandUnavailable)
  }
  guard self.host is Some(host) &&
    self.read is Some(read) &&
    self.sqlite_domain is Some(sqlite_domain) else {
    return Err(CommandUnavailable)
  }
  let profile = self.profile
  try {
    let runtime = match
      @local_host.open_native_local_packaged_runtime_in_original_read(
        Some((host, read)),
        root,
        source,
        platform,
        manifest_digest,
        profile.diagnostic_ceiling,
        command_preparation=true,
      ) {
      Ok(value) => value
      Err(Pending(value, issue)) => {
        self.runtime = Some(value)
        return Err(CommandRuntime(issue))
      }
      Err(Refused(issue)) => return Err(CommandRuntime(issue))
    }
    self.runtime = Some(runtime)
    let (sqlite_path, crypto_path) = command_preparation_value(
      runtime.library_paths().map_err(issue => CommandRuntime(issue)),
    )
    let (sqlite_member, crypto_member) = command_preparation_value(
      runtime.command_library_members().map_err(issue => CommandRuntime(issue)),
    )
    self.crypto_path = crypto_path
    self.crypto_member = Some(crypto_member)
    let acquired = command_preparation_value(
      host
      .prepare_sqlite_library(
        sqlite_domain,
        sqlite_path,
        profile.sqlite_heap_bytes,
        profile.diagnostic_ceiling,
        command_member=Some(sqlite_member),
      )
      .map_err(issue => CommandSqlite(issue)),
    )
    let sqlite = match acquired {
      ReadySqlite(value) => value
      PendingSqlite(value, issue) => {
        self.sqlite = Some(value)
        return Err(CommandSqlite(issue))
      }
    }
    self.sqlite = Some(sqlite)
    let pair = command_preparation_value(
      host
      .bind_local_host_resources(read, sqlite)
      .map_err(issue => CommandPair(issue)),
    )
    self.pair = Some(pair)
    // H remains the physical maximum, independent of this first finite
    // consuming block. Later constructors acquire backing before Read resize.
    let consumer_execution = Int64::min(
      profile.consumer_execution_bytes,
      self.initial_read_budget().read_execution,
    )
    let consumer = command_preparation_value(
      host
      .prepare_local_host_read_consumer(
        pair,
        profile.consumer_retained_bytes,
        consumer_execution,
      )
      .map_err(issue => CommandPair(issue)),
    )
    self._retained_consumer = Some(consumer)
    // This fixed registration belongs to the selected outer control lifetime,
    // before any entry of the one consuming phase. It is not another Read quote.
    self.component = Some(
      command_preparation_value(
        host
        .prepare_local_host_read_crypto_control(pair, read)
        .map_err(issue => CommandReadCrypto(issue)),
      ),
    )
    command_preparation_value(
      runtime
      .bind_original_host_resources(pair)
      .map_err(issue => CommandRuntime(issue)),
    )
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => Err(issue)
  }
}

///|
fn LocalCommandPreparationOriginal::enter(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.closing || self.closed || self.primary is Some(_) || self.phase_open {
    return Err(CommandUnavailable)
  }
  guard self.host is Some(host) && self.pair is Some(pair) else {
    return Err(CommandUnavailable)
  }
  guard self.runtime is Some(_) else { return Err(CommandUnavailable) }
  // Both closed callers follow trusted internal acquisition/projection work.
  // Exchanging this same Read phase changes no package fact; protected Runtime
  // observation and actual pair/Library lifetime remain with their owners.
  match host.enter_local_host_phase(pair, @initial_arena.HostRead) {
    Err(issue) => Err(CommandPair(issue))
    Ok(_) => {
      self.phase_open = true
      Ok(())
    }
  }
}

///|
fn LocalCommandPreparationOriginal::leave(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if !self.phase_open {
    return Ok(())
  }
  guard self.host is Some(host) && self.pair is Some(pair) else {
    return Err(CommandUnavailable)
  }
  match host.leave_local_host_phase(pair) {
    Err(issue) => Err(CommandPair(issue))
    Ok(_) => {
      self.phase_open = false
      Ok(())
    }
  }
}

///|
// Only inside this original Read phase. The real typed component enforces
// constructor thread/current context and keeps every partial Library receiver.
fn LocalCommandPreparationOriginal::library(
  self : LocalCommandPreparationOriginal,
  inner : Bool,
) -> Result[@local_crypto.Library, LocalCommandPreparationIssue] {
  if (!self.phase_open && !self.journal_read_open) ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) {
    return Err(CommandUnavailable)
  }
  let retained = if inner { self.inner_library } else { self.outer_library }
  if retained is Some(library) {
    return Ok(library)
  }
  guard self.host is Some(host) &&
    self.pair is Some(pair) &&
    self.read is Some(read) &&
    self.runtime is Some(_) else {
    return Err(CommandUnavailable)
  }
  try {
    if self.outer_library is None && self.inner_library is None {
      // Read only the already captured path. Runtime current owns its own phase
      // and must have been checked before entry; nested Runtime calls refuse.
      let path = self.crypto_path
      guard self.crypto_member is Some(crypto_member) else {
        return Err(CommandUnavailable)
      }
      let acquired = command_preparation_value(
        host
        .prepare_local_host_read_crypto(
          pair,
          read,
          path,
          self.profile.crypto_heap_bytes,
          self.profile.diagnostic_ceiling,
          command_member=Some(crypto_member),
        )
        .map_err(issue => CommandReadCrypto(issue)),
      )
      match acquired {
        ReadyCrypto(value) => self.component = Some(value)
        PendingCrypto(value, issue) => {
          self.component = Some(value)
          self.retain_primary(CommandComponent(issue))
          return Err(CommandComponent(issue))
        }
      }
    }
    let component = command_preparation_value(
      host
      .current_crypto_component(self.component.unwrap())
      .map_err(issue => CommandComponent(issue)),
    )
    let acquired = command_preparation_value(
      component.new_library().map_err(issue => CommandSignature(issue)),
    )
    let (library, issue) = match acquired {
      ReadyCryptoLibrary(value) => (value, None)
      PendingCryptoLibrary(value, issue) =>
        (value, Some(CommandSignature(issue)))
    }
    if inner {
      self.inner_library = Some(library)
    } else {
      self.outer_library = Some(library)
    }
    match issue {
      None => Ok(library)
      Some(issue) => {
        self.retain_primary(issue)
        Err(issue)
      }
    }
  } catch {
    LocalCommandPreparationStop(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// The same Reader keeps its partial Root/failure. A returned String is still a
// managed material alias and must retire before this command's Read can close.
fn LocalCommandPreparationOriginal::text_file(
  self : LocalCommandPreparationOriginal,
  root : String,
  name : String,
  maximum : Int64,
  ordinary_name? : Bool = false,
) -> Result[String, LocalCommandPreparationIssue] {
  if (!self.phase_open && !self.journal_read_open) ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) {
    return Err(CommandUnavailable)
  }
  let result = if ordinary_name {
    @files.read_bounded_ordinary_text_file_in_current_read_context_with_custody(
      root,
      name,
      maximum,
      self.profile.diagnostic_ceiling,
    )
  } else {
    @files.read_bounded_text_file_in_current_read_context_with_custody(
      root,
      name,
      maximum,
      self.profile.diagnostic_ceiling,
    )
  }
  match result {
    Ok(text) => Ok(text)
    Err(failure) => {
      self.read_failure = Some(failure)
      let issue = CommandFilesystem(failure.issue())
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// Drop no original on cleanup failure. Runtime and Journal each own their own
// full scope brackets; Library/Reader aliases are released only inside the
// same original Read cleanup. A closed carrier is not a final physical ACK.
fn LocalCommandPreparationOriginal::close_checked(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.closed {
    return Ok(())
  }
  self.closing = true
  try {
    self.cleanup_stage = "leave-command-read"
    command_preparation_value(self.leave())
    if self.standalone_cleanup_open {
      guard self.host is Some(host) && self.read is Some(read) else {
        return Err(CommandUnavailable)
      }
      command_preparation_value(
        host
        .leave_domain_original_read(read)
        .map_err(issue => CommandRead(issue)),
      )
      self.standalone_cleanup_open = false
    }
    if self.journal_read_open {
      return Err(CommandUnavailable)
    }
    if self.journal is Some(journal) && journal.original_host() is None {
      // Inactive routing metadata can exist before the first Journal open.
      // A failed open may retain its own Read/SQL return; finish that original
      // flight before closing metadata allocated outside the entered domains.
      command_preparation_value(
        journal
        .finish_pending_original_scope()
        .map_err(issue => CommandAdoption(issue)),
      )
    }
    // A pending Saved publication still borrows its original review/current
    // scope. Settle its actual payload children before cutting those aliases.
    if self.business is Some(business) &&
      business.saved_effect_files is Some(work) {
      self.cleanup_stage = "saved-effect-publication"
      command_preparation_value(self.close_saved_effect_publication(work))
    }
    self.cleanup_stage = "run-observation"
    command_preparation_value(self.close_run_observation())
    self.cleanup_stage = "business-children"
    command_preparation_value(self.close_business_children())
    self.cleanup_stage = "business-operation"
    command_preparation_value(self.close_business_operation())
    self.cleanup_stage = "saved-effect-entry"
    command_preparation_value(self.close_saved_effect_entry_after_stores())
    if self.journal is Some(journal) {
      command_preparation_value(
        journal
        .finish_pending_original_scope()
        .map_err(issue => CommandAdoption(issue)),
      )
    }
    if self.host is Some(host) {
      // An incomplete physical domain acquisition can retain the original
      // backing borrow before any Read/Runtime/Library ever existed.
      if self.backing_scope is Some(scope) {
        if self.backing_entered {
          command_preparation_value(
            host
            .leave_backing_borrow_scope(scope)
            .map_err(issue => CommandHost(issue)),
          )
          self.backing_entered = false
        }
        command_preparation_value(
          host.return_backing_borrow(scope).map_err(issue => CommandHost(issue)),
        )
        self.backing_scope = None
      }
    }
    self.cleanup_stage = "business-execution"
    command_preparation_value(self.close_business_execution())
    if self.runtime is Some(runtime) {
      native_timing_begin(18)
      defer native_timing_end(18)
      self.cleanup_stage = "runtime"
      command_preparation_value(
        runtime.close().map_err(issue => CommandRuntime(issue)),
      )
    }
    if self.journal is Some(journal) {
      native_timing_begin(19)
      defer native_timing_end(19)
      self.cleanup_stage = "journal"
      let reply = journal.close()
      if reply.issue() is Some(issue) {
        return Err(CommandJournal(issue))
      }
    }
    if self.host is Some(host) {
      if self.read is Some(read) {
        if self.pair is Some(pair) {
          command_preparation_value(
            host
            .enter_local_host_cleanup(pair, @initial_arena.HostRead)
            .map_err(issue => CommandPair(issue)),
          )
          self.phase_open = true
        } else if !self.standalone_cleanup_open {
          command_preparation_value(
            host
            .enter_domain_original_read_cleanup(read)
            .map_err(issue => CommandRead(issue)),
          )
          self.standalone_cleanup_open = true
        }
        if self.read_failure is Some(failure) {
          command_preparation_value(
            failure
            .retry_cleanup()
            .map_err(issue => CommandFilesystemCleanup(issue)),
          )
          self.read_failure = None
        }
        if self.adoption is Some(adoption) {
          self.cleanup_stage = "adoption"
          let reply = adoption.close()
          if reply.issue() is Some(issue) {
            return Err(CommandCapture(issue))
          }
          if !adoption.descriptor_cleanup_acknowledged() {
            return Err(CommandUnavailable)
          }
        }
        if self.operator_host is Some(original) {
          self.cleanup_stage = "operator-host"
          command_preparation_value(
            original.close().map_err(issue => CommandAdoption(issue)),
          )
          self.operator_host = None
          self.operator_host_wire = None
        }
        if self.product_parent_failure is Some(failure) {
          self.cleanup_stage = "product-parent-partial"
          command_preparation_value(
            failure
            .retry_cleanup()
            .map_err(issue => CommandFilesystemCleanup(issue)),
          )
          self.product_parent_failure = None
        }
        if self.product_parent is Some(parent) {
          self.cleanup_stage = "product-parent"
          command_preparation_value(
            parent.close().map_err(issue => CommandFilesystemCleanup(issue)),
          )
          self.product_parent = None
        }
        if self.product is Some(product) {
          self.cleanup_stage = "product"
          command_preparation_value(
            product.close().map_err(issue => CommandAdoption(issue)),
          )
        }
        if self.selected_root_failure is Some(failure) {
          self.cleanup_stage = "configuration-root-partial"
          command_preparation_value(
            failure
            .retry_cleanup()
            .map_err(issue => CommandFilesystemCleanup(issue)),
          )
          self.selected_root_failure = None
        }
        if self.selected_root is Some(root) {
          self.cleanup_stage = "configuration-root"
          command_preparation_value(
            root.close().map_err(issue => CommandFilesystemCleanup(issue)),
          )
          self.selected_root = None
        }
        if self.inner_library is Some(library) {
          self.cleanup_stage = "inner-library"
          command_preparation_value(
            library.close_checked().map_err(issue => CommandSignature(issue)),
          )
          self.inner_library = None
        }
        if self.outer_library is Some(library) {
          self.cleanup_stage = "outer-library"
          command_preparation_value(
            library.close_checked().map_err(issue => CommandSignature(issue)),
          )
          self.outer_library = None
        }
        self.cleanup_stage = "project-originals"
        if self.project is Some(project) &&
          project.mock_declarations is Some(original) {
          match original.retire_originals() {
            Ok(true) => ()
            Ok(false) => return Err(CommandUnavailable)
            Err(issue) => return Err(CommandProjectMock(issue))
          }
        }
        self.project = None
        // These closed records still retain Read-managed aliases. Keep them
        // through their real close and then retire our own last references.
        // The closed Journal and Adoption still retain their actual SQLite DB.
        // Its final alias must retire in the same original SQLite frame below,
        // after these Read-side descriptor/Library acknowledgements.
        self.product = None
        self.reply_outcome = None
        self.runtime = None
        self.crypto_path = ""
        self.crypto_member = None
        if self.component is Some(component) {
          self.cleanup_stage = "crypto-component"
          guard self.pair is Some(pair) else { return Err(CommandUnavailable) }
          // This caller already owns the exact original cleanup frame. Do not
          // reenter the domain through the legacy owning close operation.
          command_preparation_value(
            host
            .close_local_host_read_crypto_component(pair, read, component)
            .map_err(issue => CommandReadCrypto(issue)),
          )
          self.component = None
        }
        if self.pair is Some(_) {
          command_preparation_value(self.leave())
        } else if self.standalone_cleanup_open {
          command_preparation_value(
            host
            .leave_domain_original_read(read)
            .map_err(issue => CommandRead(issue)),
          )
          self.standalone_cleanup_open = false
        }
      }
      if self.pair is Some(pair) {
        if self.journal is Some(_) || self.adoption is Some(_) {
          self.cleanup_stage = "closed-journal-aliases"
          command_preparation_value(
            host
            .enter_local_host_cleanup(pair, @initial_arena.HostSqlite)
            .map_err(issue => CommandPair(issue)),
          )
          self.phase_open = true
          // Physical DB/Session/Root close already acknowledged above. This
          // retires only our original managed aliases, while the DB finalizer
          // can observe its actual SQLite context. It is not a close receipt.
          self.journal = None
          self.adoption = None
          command_preparation_value(self.leave())
        }
        self.cleanup_stage = "read-sqlite-pair"
        command_preparation_value(
          host
          .close_local_host_resources(pair)
          .map_err(issue => CommandPair(issue)),
        )
        self.pair = None
        self._retained_consumer = None
        self.read = None
        self.sqlite = None
      } else {
        if self.sqlite is Some(sqlite) {
          command_preparation_value(
            host
            .close_sqlite_library(sqlite)
            .map_err(issue => CommandSqlite(issue)),
          )
          self.sqlite = None
        }
        if self.read is Some(read) {
          command_preparation_value(
            host
            .close_domain_original_read(read)
            .map_err(issue => CommandRead(issue)),
          )
          self.read = None
        }
      }
      if self.read_domain is Some(domain) {
        self.cleanup_stage = "read-domain"
        command_preparation_value(
          host
          .close_domain_after_owner_ack(domain)
          .map_err(issue => CommandDomain(issue)),
        )
        self.read_domain = None
      }
      if self.sqlite_domain is Some(domain) {
        self.cleanup_stage = "sqlite-domain"
        command_preparation_value(
          host
          .close_domain_after_owner_ack(domain)
          .map_err(issue => CommandDomain(issue)),
        )
        self.sqlite_domain = None
      }
      self.cleanup_stage = "host"
      command_preparation_value(
        host.try_close().map_err(issue => CommandHost(issue)),
      )
      self.host = None
    }
    self.closed = true
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => Err(issue)
  }
}

///|
// Publish the caller's original outcome before the Native Owner attempts its
// scope leave. A failed exchange keeps both that outcome and the original
// capture; neither presentation success nor an application error releases it.
fn LocalCommandPreparationOriginal::read_command(
  self : LocalCommandPreparationOriginal,
  operation : (
    @local_host.NativeLocalHostConnection,
    @local_host.NativeLocalJournalCapture,
  ) -> Result[String, String],
) -> Result[String, LocalCommandPreparationIssue] {
  native_timing_begin(27)
  defer native_timing_end(27)
  if self.closing ||
    self.closed ||
    self.phase_open ||
    self.journal_read_open ||
    self.primary is Some(_) ||
    self.reply_outcome is Some(_) {
    return Err(CommandUnavailable)
  }
  guard self.journal is Some(journal) else { return Err(CommandUnavailable) }
  let executed = journal.with_original_read(fn(host) {
    self.journal_read_open = true
    self.reply_outcome = Some(operation(host, journal))
    // The normal observer requires a live joined pair, not its later stopped
    // cleanup route. Use this existing returned Read frame without reentry.
    if self.host is Some(physical) &&
      self.read_domain is Some(domain) &&
      !self.read_inventory_recorded {
      self.read_inventory_recorded = self.record_domain_inventory(
        physical, domain, 4,
      )
    }
    self.journal_read_open = false
  })
  match executed {
    Err(issue) => {
      let primary = match journal.original_failure() {
        Some(original) =>
          CommandJournal(@local_host.JournalAdoption(original.issue()))
        None => CommandAdoption(issue)
      }
      self.retain_primary(primary)
      Err(command_preparation_read_return_issue(self.reply_outcome, primary))
    }
    Ok(_) =>
      match self.reply_outcome {
        Some(Ok(body)) => Ok(body)
        Some(Err(message)) => {
          // A retained application message must not keep this Read alive
          // after its reply alias retires. The original/copy overlap belongs
          // to the declared caller-control inventory, not Host.control_bytes.
          let primary_message = command_control_copy_text(message)
          self.retain_primary(CommandApplication(primary_message))
          Err(CommandApplication(primary_message))
        }
        None => Err(CommandUnavailable)
      }
  }
}

///|
// The callback outcome remains borrowed from this retained command until main
// reports it, before child cleanup. A failed physical return cannot replace an
// application failure with a generic supplier diagnostic, or publish a reply.
// The original return issue remains on the capture and primary cleanup record.
fn command_preparation_read_return_issue(
  outcome : Result[String, String]?,
  return_issue : LocalCommandPreparationIssue,
) -> LocalCommandPreparationIssue {
  match outcome {
    Some(Err(message)) => CommandApplication(message)
    None | Some(Ok(_)) => return_issue
  }
}

///|
// The trusted command snapshots selection inside its actual Read. The same
// captured Product originals are rechecked; this never synthesizes a missing
// installation marker, creates a replacement selection, or skips its claim.
fn LocalCommandPreparationOriginal::stage_product(
  self : LocalCommandPreparationOriginal,
  parent : String,
  name : String,
  originals : Array[(String, Bytes)]?,
) -> Result[Unit, LocalCommandPreparationIssue] {
  native_timing_begin(13)
  defer native_timing_end(13)
  if !self.phase_open || self.closing || self.closed || self.primary is Some(_) {
    return Err(CommandUnavailable)
  }
  try {
    let product = match self.product {
      Some(original) => original
      None => {
        let crypto = command_preparation_value(self.library(false))
        let original = command_preparation_value(
          @local_host.prepare_native_local_product_configuration_capture_in_current_read_context(
            parent,
            name,
            crypto,
            self.profile.diagnostic_ceiling,
            originals~,
          ).map_err(issue => CommandAdoption(issue)),
        )
        self.product = Some(original)
        original
      }
    }
    command_preparation_value(
      product.open().map_err(issue => CommandAdoption(issue)),
    )
    |> ignore
    // Restore already validates and stages the selected originals while
    // holding this same Product Lock. Only an explicit initial selection
    // reaches the constructor before its first staging attempt.
    if originals is Some(_) {
      command_preparation_value(
        product.stage_configuration().map_err(issue => CommandAdoption(issue)),
      )
    }
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// The explicit initializer observes only the original Product parent. This
// discovery capability is retained independently of the Product constructor's
// own Roots/Lock, and closes before that original Lock may acknowledge release.
fn LocalCommandPreparationOriginal::select_product_parent(
  self : LocalCommandPreparationOriginal,
  path : String,
) -> Result[@local_filesystem.Root, LocalCommandPreparationIssue] {
  if !self.phase_open ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) ||
    self.product_parent is Some(_) ||
    self.product_parent_failure is Some(_) {
    return Err(CommandUnavailable)
  }
  match
    @local_filesystem.open_root_in_current_read_context_with_custody(
      path,
      self.profile.diagnostic_ceiling,
    ) {
    Ok(parent) => {
      self.product_parent = Some(parent)
      Ok(parent)
    }
    Err(failure) => {
      self.product_parent_failure = Some(failure)
      let issue = CommandFilesystemCleanup(failure.issue())
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// Retain this independently opened discovery Root before inspecting ownership.
// A matching path, decoded configuration or another Root cannot close it.
fn LocalCommandPreparationOriginal::select_configuration_root(
  self : LocalCommandPreparationOriginal,
  path : String,
) -> Result[@local_filesystem.Root, LocalCommandPreparationIssue] {
  if !self.phase_open ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) ||
    self.selected_root is Some(_) ||
    self.selected_root_failure is Some(_) {
    return Err(CommandUnavailable)
  }
  match
    @local_filesystem.open_private_root_in_current_read_context_with_custody(
      path,
      self.profile.diagnostic_ceiling,
    ) {
    Ok(root) => {
      self.selected_root = Some(root)
      Ok(root)
    }
    Err(failure) => {
      self.selected_root_failure = Some(failure)
      let issue = CommandFilesystemCleanup(failure.issue())
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// The same original holder is published before acquiring Roots, Lock or key
// material. Only explicit initialization selects the original initial branch;
// existing-only commands never manufacture absent installation originals.
fn LocalCommandPreparationOriginal::prepare_adoption(
  self : LocalCommandPreparationOriginal,
  input : @local_host.NativeLocalExistingAdoptionInput,
  initialize : Bool,
) -> Result[
  @local_host.NativeLocalAdoptionSession,
  LocalCommandPreparationIssue,
] {
  native_timing_begin(14)
  defer native_timing_end(14)
  if !self.phase_open ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) ||
    self.adoption is Some(_) {
    return Err(CommandUnavailable)
  }
  try {
    let crypto = command_preparation_value(self.library(true))
    let selected = if initialize {
      @local_host.prepare_native_local_initial_adoption_capture_in_current_read_context(
        input,
        crypto,
        self.profile.diagnostic_ceiling,
      )
    } else {
      @local_host.prepare_native_local_existing_adoption_capture_in_current_read_context(
        input,
        crypto,
        self.profile.diagnostic_ceiling,
      )
    }
    let capture = command_preparation_value(
      selected.map_err(issue => CommandAdoption(issue)),
    )
    self.adoption = Some(capture)
    let operator_host = match self.operator_host {
      Some(original) =>
        Some(
          command_preparation_value(
            original.open().map_err(issue => CommandAdoption(issue)),
          ),
        )
      None => None
    }
    if capture.open(product=self.product, operator_host~).issue() is Some(issue) {
      self.retain_primary(CommandCapture(issue))
      return Err(CommandCapture(issue))
    }
    match capture.original_session() {
      Some(session) => Ok(session)
      None => Err(CommandUnavailable)
    }
  } catch {
    LocalCommandPreparationStop(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// Prepare the same Journal before its first Read/SQL exchange. Material is
// generated only by the same explicitly eligible original Session, never by
// restoring a path or reissuing a key after failure/Unknown.
fn LocalCommandPreparationOriginal::prepare_adopted_journal(
  self : LocalCommandPreparationOriginal,
  initialize_signing : Bool,
  options : LocalInitialSigningAdoptionOptions,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if !self.phase_open ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) ||
    self.journal is Some(_) {
    return Err(CommandUnavailable)
  }
  // Match the real parsed settings to the pre-acquisition original envelope,
  // before signing material, inspection, DB open or any Journal mutation.
  if !self.native_storage.covers_journal(
      self.profile.source,
      options.max_records,
      options.max_snapshot_bytes,
    ) {
    return Err(CommandNativeStorage(NativeStorageInsufficient))
  }
  guard self.adoption is Some(adoption) &&
    self.host is Some(host) &&
    self.pair is Some(pair) &&
    self.read is Some(read) else {
    return Err(CommandUnavailable)
  }
  try {
    let journal = if initialize_signing {
      let session = adoption.original_session().unwrap()
      let crypto = command_preparation_value(self.library(true))
      let material = command_preparation_value(
        session
        .create_initial_signing_material(
          crypto,
          host_signing_subject=options.initial_host_signing,
        )
        .map_err(original => CommandAdoption(original.issue())),
      )
      command_preparation_value(
        adoption
        .capture_initial_command_journal_with_original_resources(
          host,
          pair,
          read,
          material,
          @run_host.client_local_default_signing_bootstrap_policy(),
          options.ttl_ms,
          options.max_records,
          options.max_snapshot_bytes,
        )
        .map_err(issue => CommandCapture(issue)),
      )
    } else {
      command_preparation_value(
        adoption
        .capture_command_journal_with_original_resources(
          host,
          pair,
          read,
          options.ttl_ms,
          options.max_records,
          options.max_snapshot_bytes,
        )
        .map_err(issue => CommandCapture(issue)),
      )
    }
    self.journal = Some(journal)
    command_preparation_value(self.leave())
    // Routing preparation performs no activation, Store IO or Host admission.
    // Keep it outside the Read; read_command opens and enters the original
    // Journal in one closed call without a second configuration observation.
    if self.business is Some(business) &&
      business.profile.kind == SavedResultRead {
      command_preparation_value(self.prepare_business_operation())
    }
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
fn LocalCommandPreparationOriginal::initial_read_budget(
  self : LocalCommandPreparationOriginal,
) -> @initial_arena.InstalledArenaOriginalReadBudget {
  local_command_initial_read_budget(self.profile)
}

///|
fn[T] command_preparation_option(
  value : T?,
) -> T raise LocalCommandPreparationStop {
  match value {
    Some(value) => value
    None => raise LocalCommandPreparationStop(CommandInvalidProfile)
  }
}

///|
// The same selected initial Read basis is reused by its original command and
// Native component consumers. This projection issues no platform original.
fn local_command_initial_read_budget(
  profile : LocalCommandPreparationProfile,
) -> @initial_arena.InstalledArenaOriginalReadBudget {
  let budget = profile.read_budget
  {
    ..budget,
    read_execution: Int64::min(
      budget.read_execution,
      Int64::max(budget.bootstrap_execution, budget.workspace_execution),
    ),
  }
}
