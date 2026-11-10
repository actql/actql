///|
// A closed installer candidate for static command preparation. These finite
// facilities are selected before their actual FD/mapping/context acquisitions;
// they do not estimate all-input demand or grant a business Run any capacity.
// Ordinary runtime values use the trusted platform allocator. Explicit native
// domains retain their own actual backing, currentness and cleanup duties.
fn local_command_installed_profile(
  source : String,
  manifest : String,
) -> LocalCommandPreparationProfile raise ClientStop {
  let mib = 1048576L
  let read_ceiling = 96L * mib
  let sqlite_ceiling = 48L * mib
  let sqlite_heap = 32L * mib
  let read_budget : @initial_arena.InstalledArenaOriginalReadBudget = {
    bootstrap_retained: mib,
    bootstrap_execution: mib,
    workspace_execution: 8L * mib,
    read_retained: 7L * mib,
    read_execution: read_ceiling,
  }
  // Keep every existing read/workspace claim and facility ceiling. The
  // enclosing ledger sums those actual simultaneous claims, not unused
  // capacity from a larger allocation.
  let read_retained = native_storage_sum([
    read_budget.bootstrap_retained,
    read_budget.read_retained,
  ]).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
  let read_execution = native_storage_sum([
    read_budget.bootstrap_execution,
    read_budget.workspace_execution,
    read_budget.read_execution,
  ]).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
  let read_payload = native_storage_sum([read_retained, read_execution]).unwrap_or_else(() => {
      stop("LocalCommandPreparationLayoutUnavailable")
    },
  )
  // Use actual provider control/context geometry for each complete domain.
  // SQLite's existing occupied-page facility includes its contained heap;
  // adding that heap again would quote the same bytes twice.
  let read_domain = local_command_domain_bytes(read_payload).unwrap_or_else(() => {
    stop("LocalCommandPreparationLayoutUnavailable")
  })
  let sqlite_domain = local_command_domain_bytes(sqlite_ceiling).unwrap_or_else(() => {
      stop("LocalCommandPreparationLayoutUnavailable")
    },
  )
  let domains = native_storage_sum([read_domain, sqlite_domain]).unwrap_or_else(() => {
      stop("LocalCommandPreparationLayoutUnavailable")
    },
  )
  let (arena, control) = local_command_backing_layout(domains).unwrap_or_else(() => {
    stop("LocalCommandPreparationLayoutUnavailable")
  })
  let sqlite_minimum = @local_sqlite.command_domain_necessary_bytes(
    sqlite_domain, sqlite_heap,
  ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
  if sqlite_minimum <= 0L || sqlite_minimum > sqlite_ceiling {
    stop("LocalCommandPreparationLayoutUnavailable")
  }
  let recipe = initial_crypto_hex_recipe(manifest) catch {
    ClientStop(_) => stop("PackagedLocalRuntimeInvalid")
  }
  {
    source,
    recipe,
    arena_bytes: arena,
    control_bytes: control,
    host_limits: {
      planning_work: 1024,
      // One shared-capacity attempt and one provisioning attempt for EACH
      // unchanged child attempt declaration. No child return refills them.
      attempts: 1 + 1 + 64 + 1 + 32,
      holdings: 64,
      transfer_bytes: 16L * mib,
      retained_bytes: 0L,
      execution_bytes: arena,
    },
    read_domain_bytes: read_domain,
    read_domain_limits: {
      planning_work: 512,
      attempts: 64,
      holdings: 32,
      transfer_bytes: 8L * mib,
      retained_bytes: read_retained,
      execution_bytes: read_execution,
    },
    sqlite_domain_bytes: sqlite_domain,
    sqlite_domain_limits: {
      planning_work: 256,
      attempts: 32,
      holdings: 16,
      transfer_bytes: 8L * mib,
      retained_bytes: 0L,
      execution_bytes: sqlite_ceiling,
    },
    read_budget,
    consumer_retained_bytes: mib,
    consumer_execution_bytes: read_ceiling,
    sqlite_heap_bytes: sqlite_heap,
    crypto_heap_bytes: 2L * mib,
    diagnostic_ceiling: 4096,
    native_storage: {
      source,
      max_snapshot_bytes: 8L * mib,
      max_records: 32,
      read_selection: CommandReadFiniteFacility(read_ceiling),
      platform_selection: CommandPlatformInitialOsFacility,
      sqlite_domain_selection: CommandSqliteDomainFiniteFacility(sqlite_ceiling),
      loader_platform_execution_bytes: None,
      sqlite_heap_selection: Some(SqliteFiniteFacility),
      sqlite_external_execution_bytes: None,
      shared_control_bytes: Some(control),
    },
  }
}

///|
// Select static preparation, explicit adoption and the admitted public Run
// scope. This choice performs no IO and creates no physical original.
fn local_command_preparation_selected(
  matches : @argparse.Matches,
) -> Bool raise ClientStop {
  if !(matches.subcommand is Some(("check", _)) ||
    (
      matches.subcommand is Some((operation, child)) &&
      local_quick_query_requested(operation, child)
    ) ||
    matches.subcommand is Some(("explain", _)) ||
    matches.subcommand is Some(("run", _)) ||
    matches.subcommand is Some(("new-submission", _)) ||
    matches.subcommand is Some(("lookup-submission", _)) ||
    matches.subcommand is Some(("lookup-request", _)) ||
    matches.subcommand is Some(("cancel", _)) ||
    matches.subcommand is Some(("lookup-cancellation", _)) ||
    local_checkpoint_action_selected(matches, "approve") ||
    local_checkpoint_action_selected(matches, "reject") ||
    (
      matches.subcommand is Some(("result", child)) &&
      optional(child, "run") is Some(_)
    ) ||
    (
      matches.subcommand is Some(("status", child)) &&
      (
        optional(child, "run") is Some(_) ||
        optional(child, "run-id") is Some(_)
      )
    ) ||
    matches.subcommand is Some(("adopt", _))) {
    return false
  }
  required(matches, "mode") == "local" ||
  local_project_default_local_candidate(matches)
}

///|
// Selection only. Result retains the bounded command Read/SQLite facilities;
// a new computation still selects its separate complete business candidate.
fn local_command_profile_selection(
  static_profile : LocalCommandPreparationProfile,
  matches : @argparse.Matches,
) -> (LocalCommandPreparationProfile, LocalCommandBusinessProfile?) raise ClientStop {
  if matches.subcommand is Some(("run", _)) ||
    matches.subcommand is Some(("check", _)) ||
    (
      matches.subcommand is Some(("explain", child)) &&
      optional(child, "run") is None
    ) ||
    (
      matches.subcommand is Some((operation, child)) &&
      local_quick_query_requested(operation, child)
    ) {
    let (profile, business) = local_command_source_free_business_profile(
      static_profile,
    )
    (profile, Some(business))
  } else if matches.subcommand is Some(("approve", _)) ||
    matches.subcommand is Some(("reject", _)) {
    let (profile, business) = local_command_backed_business_profile(
      static_profile,
      SavedEffectApply,
    )
    (profile, Some(business))
  } else if matches.subcommand is Some(("result", _)) {
    (static_profile, Some(local_command_saved_result_read_profile()))
  } else {
    (static_profile, None)
  }
}

///|
// Successful parse precedes this call. The exact initial launcher context and
// compiled source are retained by the same early entry. Store the same carrier
// BEFORE its first backing/Host/Root/Reader acquisition, including failures.
fn prepare_native_command_invocation(
  matches : @argparse.Matches,
) -> Unit raise ClientStop {
  native_timing_begin(8)
  defer native_timing_end(8)
  if !local_command_preparation_selected(matches) {
    return
  }
  let explicit_operational = (
      matches.subcommand is Some(("run", _)) ||
      (
        matches.subcommand is Some((operation, child)) &&
        local_quick_query_requested(operation, child)
      ) ||
      matches.subcommand is Some(("status", _)) ||
      matches.subcommand is Some(("new-submission", _)) ||
      matches.subcommand is Some(("lookup-submission", _)) ||
      matches.subcommand is Some(("lookup-request", _)) ||
      matches.subcommand is Some(("cancel", _)) ||
      matches.subcommand is Some(("lookup-cancellation", _)) ||
      (
        matches.subcommand is Some(("explain", child)) &&
        optional(child, "run") is Some(_)
      ) ||
      matches.subcommand is Some(("result", _))
    ) &&
    matches.sources.get("config-file") is Some(@argparse.Argv)
  let context = match command_preargument_retained_context() {
    Ok(Some(value)) => value
    Ok(None) if explicit_operational =>
      stop("ExplicitLocalConfigurationRequiresOriginalSupplier")
    Ok(None) => return // Separate unselected compatibility entrance only.
    Err(_) => stop("LocalCommandPreparationUnavailable")
  }
  if command_preparation_invocation.val is Some(_) {
    stop("LocalCommandPreparationUnavailable")
  }
  if !(matches.sources.get("config-root") is Some(@argparse.Default)) &&
    !(matches.sources.get("config-file") is Some(@argparse.Argv)) {
    stop("ExplicitLocalRootRequiresConfiguration")
  }
  let (root, source, platform, manifest) = local_product_context(context)
  let actual_source = command_preparation_result(command_preargument_source())
  if source != actual_source || !command_compiled_platform_matches(platform) {
    stop("PackagedLocalRuntimeChanged")
  }
  let static_profile = local_command_installed_profile(actual_source, manifest)
  let (profile, business) = local_command_profile_selection(
    static_profile, matches,
  )
  let original = command_preparation_result(
    prepare_local_command_preparation_original(profile, business~),
    stage=Some("prepare"),
  )
  command_preparation_invocation.val = Some(original)
  command_preparation_result(
    original.acquire(root, source, platform, manifest),
    stage=Some("acquire"),
  )
  command_preparation_result(original.enter(), stage=Some("enter"))
}

///|
// Close the selected provider's outer-control layout around the complete
// simultaneous child domains. A larger business reservation changes this
// control requirement too; no fixed spare region or residual credit is used.
fn local_command_backing_layout(domains : Int64) -> (Int64, Int64)? {
  if domains <= 0L {
    return None
  }
  let mut bytes = match
    native_storage_page_round(domains, native_storage_page_bytes()) {
    Ok(value) => value
    Err(_) => return None
  }
  for _ in 0..<16 {
    guard @initial_bootstrap.command_backing_control_necessary_bytes(bytes)
      is Some(control) &&
      control > 0L &&
      control <= 9223372036854775807L - domains else {
      return None
    }
    let necessary = match
      native_storage_page_round(domains + control, native_storage_page_bytes()) {
      Ok(value) => value
      Err(_) => return None
    }
    if necessary <= bytes {
      return Some((bytes, control))
    }
    bytes = necessary
  }
  None
}
