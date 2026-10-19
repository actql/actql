///|
// A closed installer candidate for static command preparation. These finite
// facilities are selected before their actual FD/mapping/context acquisitions;
// they do not estimate all-input demand or grant a business Run any capacity.
// The process retains its separate initial managed/OS originals throughout.
fn local_command_installed_profile(
  source : String,
  manifest : String,
) -> LocalCommandPreparationProfile raise ClientStop {
  let mib = 1048576L
  let arena = 208L * mib
  let read_domain = 128L * mib
  let sqlite_domain = 64L * mib
  let read_ceiling = 96L * mib
  let sqlite_ceiling = 48L * mib
  let sqlite_heap = 32L * mib
  // Use the actual selected provider layout before acquisition. Neither an
  // outer control envelope nor unused mapping space can fill a missing query.
  let control = @initial_bootstrap.command_backing_control_necessary_bytes(
    arena,
  ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
  if control <= 0L || control > arena - read_domain - sqlite_domain {
    stop("LocalCommandPreparationLayoutUnavailable")
  }
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
      retained_bytes: 8L * mib,
      execution_bytes: 120L * mib,
    },
    sqlite_domain_bytes: sqlite_domain,
    sqlite_domain_limits: {
      planning_work: 256,
      attempts: 32,
      holdings: 16,
      transfer_bytes: 8L * mib,
      retained_bytes: 0L,
      execution_bytes: 56L * mib,
    },
    read_budget: {
      bootstrap_retained: mib,
      bootstrap_execution: mib,
      workspace_execution: 8L * mib,
      read_retained: 7L * mib,
      read_execution: read_ceiling,
    },
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
      managed_read_execution_bytes: None,
      loader_platform_execution_bytes: None,
      native_read_execution_bytes: None,
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
    matches.subcommand is Some(("explain", _)) ||
    matches.subcommand is Some(("run", _)) ||
    matches.subcommand is Some(("adopt", _))) {
    return false
  }
  required(matches, "mode") == "local" ||
  local_project_default_local_candidate(matches)
}

///|
// Successful parse precedes this call. The exact initial launcher context and
// compiled source are retained by the same early entry. Store the same carrier
// BEFORE its first backing/Host/Root/Reader acquisition, including failures.
fn prepare_native_command_invocation(
  matches : @argparse.Matches,
) -> Unit raise ClientStop {
  if !local_command_preparation_selected(matches) {
    return
  }
  if matches.subcommand is Some(("run", _)) &&
    matches.sources.get("config-file") is Some(@argparse.Argv) {
    // The selected Run uses the original packaged installation. An explicit
    // legacy configuration has no corresponding operational supplier here;
    // it must not fall through to raw Library loading after this selection.
    stop("ExplicitLocalConfigurationRequiresOriginalSupplier")
  }
  let context = match command_preargument_retained_context() {
    Ok(None) => return // Separate unselected compatibility entrance only.
    Ok(Some(value)) => value
    Err(_) => stop("LocalCommandPreparationUnavailable")
  }
  if command_preparation_invocation.val is Some(_) {
    stop("LocalCommandPreparationUnavailable")
  }
  if !(matches.sources.get("config-root") is Some(@argparse.Default)) {
    stop("ExplicitLocalRootRequiresConfiguration")
  }
  let (root, source, platform, manifest) = local_product_context(context)
  let actual_source = command_preparation_result(command_preargument_source())
  if source != actual_source || platform != "darwin-arm64" {
    stop("PackagedLocalRuntimeChanged")
  }
  let static_profile = local_command_installed_profile(actual_source, manifest)
  // The full business candidate exists before backing/domain/Root acquisition,
  // not after epoch issuance, Program admission or first-start claims.
  let (profile, business) = if matches.subcommand is Some(("run", _)) {
    let (profile, business) = local_command_source_free_business_profile(
      static_profile,
    )
    (profile, Some(business))
  } else {
    (static_profile, None)
  }
  let original = command_preparation_result(
    prepare_local_command_preparation_original(profile, business~),
  )
  command_preparation_invocation.val = Some(original)
  command_preparation_result(original.acquire(root, source, platform, manifest))
  command_preparation_result(original.enter())
}
