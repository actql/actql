///|
/// Only an explicit operator option selects this private installation. An
/// empty/repeated selected option is invalid, never the unselected None path.
fn holder_effect_host_root(values : Array[String]?) -> Result[String?, String] {
  match values {
    None => Ok(None)
    Some([root]) if !root.is_empty() && root.length() <= 4096 => Ok(Some(root))
    _ => Err("Effect Host Account root selection invalid")
  }
}

///|
fn holder_effect_host_snapshot_current(
  snapshot : Array[(String, String)],
  read : (String) -> String?,
) -> Bool {
  snapshot.all(entry => read(entry.0) == Some(entry.1))
}

///|
/// Original installed control strings retained beyond setup. Count occurrences
/// conservatively; a shared immutable reference can extend its holding period.
/// Calculate the existing URL derivation's length without allocating its body.
/// This is representation arithmetic, not a URL permission or a numeric profile.
fn holder_effect_host_control_text_extent(
  profile : HolderEffectHostSetupProfile,
  observation_url : String,
  site_key : String,
  coordinator_authority : String,
  runtime_bundle_cid : String,
) -> Int64? {
  let suffix = "/outbound/observations"
  guard observation_url.has_prefix("https://") &&
    observation_url.has_suffix(suffix) else {
    return None
  }
  // The Site key occurs in both the original binding and Cloud identity scope.
  let mut bytes = 0L
  for
    length in [
      observation_url.length().to_int64() -
      suffix.length().to_int64() +
      "/outbound/effect-host-identity-current".length().to_int64(),
      site_key.length().to_int64(),
      site_key.length().to_int64(),
      coordinator_authority.length().to_int64(),
      runtime_bundle_cid.length().to_int64(),
    ] {
    guard holder_effect_host_extent_product(profile.utf16_unit_bytes, length)
      is Some(units) &&
      holder_effect_host_extent_add(profile.string_bytes, units) is Some(text) &&
      holder_effect_host_extent_add(bytes, text) is Some(total) else {
      return None
    }
    bytes = total
  }
  Some(bytes)
}

///|
fn holder_effect_host_control_representation_ready(
  profile : HolderEffectHostSetupProfile,
  observation_url : String,
  site_key : String,
  coordinator_authority : String,
  runtime_bundle_cid : String,
) -> Int64? {
  guard holder_effect_host_control_text_extent(
      profile, observation_url, site_key, coordinator_authority, runtime_bundle_cid,
    )
    is Some(text_bytes) &&
    holder_effect_host_extent_add(profile.retained_controls_bytes, text_bytes)
    is Some(control_bytes) &&
    holder_effect_host_extent_add(control_bytes, profile.caller_retained_bytes)
    is Some(partition) &&
    partition <= profile.setup_retained_bytes else {
    return None
  }
  Some(text_bytes)
}

///|
/// Real operator input entry, before the Source start claim. It opens no
/// Provider/credential/Store Owner. The existing bounded reader and Account
/// installer own file admission; no poll/candidate chooses a path or subject.
fn load_holder_effect_host_operator(
  matches : @argparse.Matches,
  resources : HolderOutputResources,
  environment : SiteEnvironment,
  slot : @slot.NativeExecutorSlot,
  // Optional explicit mapped-Read selection. The ordinary trusted Host instead
  // acquires bounded platform resources at its documented entry.
  setup_profile? : HolderEffectHostSetupProfile? = None,
  preparation? : HolderEffectPreparationCapacity? = None,
  read_installation? : HolderEffectHostReadInstallation? = None,
  read_parent? : HolderEffectHostReadParentInstallation? = None,
) -> HolderEffectHostOperatorInstallation? raise CommandStop {
  let selected = match
    holder_effect_host_root(matches.values.get("effect-host-account-root")) {
    Ok(value) => value
    Err(issue) => stop(issue)
  }
  guard selected is Some(root) else { return None }
  // Keep the same Site reservation in the existing output resources before
  // constructing Slot/runtime callback contexts. Selection proves neither
  // Account permission nor an installed Host baseline.
  let selected_scope = if setup_profile is None &&
    read_installation is None &&
    read_parent is None {
    prepare_holder_effect_host_ordinary_scope(
      environment.site,
      required_int64(matches, "max-file-bytes"),
      environment.runtime_catalog_record_bytes,
    )
  } else {
    reserve_holder_effect_host_setup_scope(
      environment.site,
      setup_profile,
      environment.runtime_catalog_record_bytes,
    )
  }
  guard selected_scope is Some(scope) else {
    stop("Effect Host setup capacity unavailable")
  }
  resources.effect_host_setup.val = Some(scope)
  // Capture immutable facts and the original verifier handles, not resources:
  // capturing its Ref[scope] would create a scope/current-predicate cycle.
  let bundles = environment.bundles
  let active_runtime = environment.active_runtime
  // Use the same immutable selection admitted before reservation, and enforce
  // it at the physical Store read on every current check, never just in a quote.
  let (selected_catalog_limit, catalog_json_limits) = holder_effect_host_scope_catalog_limits(
    scope,
  )
  let catalog_read_limit = if selected_catalog_limit <
    environment.runtime_catalog_record_bytes {
    selected_catalog_limit
  } else {
    environment.runtime_catalog_record_bytes
  }
  let catalog_diagnostic_ceiling = holder_effect_host_scope_diagnostic_ceiling(
    scope,
  )
  let scoped_profile = scope.profile
  let site = environment.site
  let site_key = resources.site_key
  let site_generation = resources.site_generation
  let runtime_bundle_cid = environment.runtime_bundle_cid
  scope.preparation_binding = Some(() => {
    holder_effect_host_setup_selection_current(
      site,
      site_key,
      site_generation,
      runtime_bundle_cid,
      () => slot.verify_current_hold() == Ok(()),
    )
  })
  if !holder_effect_host_read_scope_prepared(scope) {
    ignore(leave_holder_effect_host_read_scope(scope))
    stop("Effect Host setup original selection unavailable")
  }
  let read_installation = match (read_installation, read_parent) {
    (Some(_), Some(_)) => {
      ignore(leave_holder_effect_host_read_scope(scope))
      stop("Effect Host original Native read installation ambiguous")
    }
    (None, Some(selected)) =>
      prepare_holder_effect_host_read_parent(scope, slot, selected)
    (value, None) => value
  }
  if scope.ordinary is None &&
    !install_holder_effect_host_read_domain(scope, slot, read_installation) {
    ignore(leave_holder_effect_host_read_scope(scope))
    stop("Effect Host original Native read installation unavailable")
  }
  // Only the entered original domain may perform the first bounded Store
  // revalidation. Its refusal may read that Store, but opens no Account/Provider.
  if !install_holder_effect_host_store_current(
      scope,
      holder_effect_host_setup_binding(
        site,
        site_key,
        site_generation,
        runtime_bundle_cid,
        () => slot.verify_current_hold() == Ok(()),
        () => {
          (match scoped_profile {
            Some(profile) =>
              bundles.current_sqlite_component_matches_heap(
                profile.catalog_sqlite_heap_bytes,
              )
            None => true
          }) &&
          bundles.diagnostics_bounded_by(catalog_diagnostic_ceiling) &&
          bundles.verify_active_component_binding_with_body_limit(
            active_runtime,
            catalog_read_limit,
            json_limits=Some(catalog_json_limits),
          )
          is Ok(_) &&
          (match scoped_profile {
            Some(profile) =>
              bundles.current_sqlite_component_matches_heap(
                profile.catalog_sqlite_heap_bytes,
              )
            None => true
          })
        },
      ),
    ) {
    ignore(leave_holder_effect_host_read_scope(scope))
    stop("Effect Host setup current binding unavailable")
  }
  let installed = prepare_holder_effect_host_operator(
    root,
    matches,
    resources,
    scope,
    environment.runtime_bundle_cid,
    preparation~,
  ) catch {
    CommandStop(issue) => {
      ignore(leave_holder_effect_host_read_scope(scope))
      stop(issue)
    }
  }
  resources.effect_host_installation.val = Some(installed)
  guard leave_holder_effect_host_read_scope(scope) else {
    stop("Effect Host setup current binding unavailable")
  }
  Some(installed)
}

///|
fn read_holder_effect_host_text(
  scope : HolderEffectHostSetupScope,
  root : String,
  name : String,
  limit : Int64,
  trim_newline? : Bool = false,
) -> String? {
  guard holder_effect_host_read_scope_current(scope) else { return None }
  let result = if scope.ordinary is Some(_) {
    @bounded_files.read_bounded_text_file_with_custody(
      root,
      name,
      limit,
      diagnostic_ceiling=Some(
        holder_effect_host_scope_diagnostic_ceiling(scope),
      ),
      trim_newline~,
    )
  } else {
    // An explicitly selected native Read cannot fall back to ordinary I/O.
    @bounded_files.read_bounded_text_file_in_current_read_context_with_custody(
      root,
      name,
      limit,
      holder_effect_host_scope_diagnostic_ceiling(scope),
      trim_newline~,
    )
  }
  match result {
    Ok(text) =>
      if holder_effect_host_read_scope_current(scope) {
        Some(text)
      } else {
        None
      }
    Err(failure) => {
      observe_holder_effect_host_read_failure(scope, failure)
      None
    }
  }
}

///|
fn prepare_holder_effect_host_operator(
  root : String,
  matches : @argparse.Matches,
  resources : HolderOutputResources,
  scope : HolderEffectHostSetupScope,
  runtime_bundle_cid : String,
  preparation? : HolderEffectPreparationCapacity? = None,
) -> HolderEffectHostOperatorInstallation raise CommandStop {
  // The same Site operation already funds setup. Refuse excessive retained
  // original metadata before any physical file read; no admission grants access.
  guard holder_effect_host_read_scope_current(scope) else {
    stop("Effect Host current binding unavailable")
  }
  let control_text_bytes = if scope.ordinary is Some(_) {
    guard [
      resources.observation_url,
      resources.site_key,
      resources.coordinator_authority,
      runtime_bundle_cid,
    ].all(text => !text.is_empty() && text.length() <= 4096) else {
      stop("Effect Host control input limit exceeded")
    }
    0L
  } else {
    guard holder_effect_host_control_representation_ready(
        scope.profile.unwrap(),
        resources.observation_url,
        resources.site_key,
        resources.coordinator_authority,
        runtime_bundle_cid,
      )
      is Some(control_text_bytes) else {
      stop("Effect Host control representation capacity unavailable")
    }
    control_text_bytes
  }
  let configured = required_int64(matches, "max-file-bytes")
  if configured <= 0L {
    stop("Effect Host Account file limit invalid")
  }
  let ceiling = holder_effect_host_scope_read_ceiling(scope).to_int64()
  let file_limit = if configured < ceiling { configured } else { ceiling }
  let subject_limit = if file_limit < 512L { file_limit } else { 512L }
  let names = [
    "host-principal.txt", "host-account-id.txt", "host-configuration-cid.txt", "host-authorization-context-cid.txt",
    "host-read-connection.txt", "host-read-resource.txt", "host-publication-connection.txt",
    "host-publication-resource.txt", "workspace-id.txt", "installation.txt", "host-identity-expires-ms.txt",
  ]
  let snapshot = names.map(name => {
    guard read_holder_effect_host_text(scope, root, name, subject_limit)
      is Some(text) else {
      stop("Effect Host input read unavailable")
    }
    (name, text)
  })
  if snapshot.any(entry => entry.1.is_empty()) {
    stop("Effect Host Account input missing")
  }
  let read = (index : Int) => snapshot[index].1
  let expires_ms : Int64 = @string.from_str(read(10)) catch {
    _ => stop("Effect Host identity expiry invalid")
  }
  let now_ms = @env.now().reinterpret_as_int64()
  if expires_ms <= now_ms || expires_ms > 9007199254740991L {
    stop("Effect Host identity expiry invalid")
  }
  let subject : @effect_review.NativeEffectHostAccountSubject = {
    principal: read(0),
    account_id: read(1),
    configuration_cid: read(2),
    authorization_context_cid: read(3),
    read_connection: read(4),
    read_resource: read(5),
    publication_connection: read(6),
    publication_resource: read(7),
  }
  let account = match
    @effect_review.install_native_effect_host_account(
      Some({ root, name: "account.json", subject, }),
      // Retain the same trusted operator ceiling for initial, current and final
      // physical reads. The clamped value fits Int; candidate wire cannot raise it.
      read_ceiling=file_limit.to_int(),
      diagnostic_ceiling=Some(
        holder_effect_host_scope_diagnostic_ceiling(scope),
      ),
      require_current_read_context=scope.ordinary is None,
      on_read_failure=Some(failure => {
        observe_holder_effect_host_read_failure(scope, failure)
      }),
      read_scope_current=Some(() => holder_effect_host_read_scope_current(scope)),
    ) {
    Ok(Some(value)) => value
    _ => stop("Effect Host Account installation refused")
  }
  let current = () => {
    with_holder_effect_host_read_scope(scope, () => {
      holder_effect_host_read_scope_current(scope) &&
      holder_effect_host_snapshot_current(snapshot, name => {
        read_holder_effect_host_text(scope, root, name, subject_limit)
      }) &&
      read_holder_effect_host_text(scope, root, "account.json", file_limit)
      is Some(_) &&
      @env.now().reinterpret_as_int64() >= 0L &&
      @env.now().reinterpret_as_int64() < expires_ms
    })
  }
  guard current() &&
    holder_effect_control_read_url(
      resources.observation_url,
      "effect-host-identity-current",
    )
    is Some(url) else {
    stop("Effect Host Account current installation unavailable")
  }
  let identity : @effect_review.NativeEffectCloudHostIdentityRead = {
    control: {
      client: resources.control,
      url,
      current_site: current,
      next_query_id: () => {
        // Fresh local challenge only, never a new execution identity. Failure
        // to obtain entropy produces an invalid label and closes the read.
        guard @env.rand(16) is Some(bytes) else { return "" }
        let builder = StringBuilder()
        builder.write_string("host-identity:")
        for byte in bytes {
          let part = byte.to_hex()
          if part.length() < 2 {
            builder.write_string("0")
          }
          builder.write_string(part)
        }
        builder.to_string()
      },
      now_ms: () => @env.now().reinterpret_as_int64(),
    },
    scope: {
      site_key: resources.site_key,
      site_generation: resources.site_generation.to_int64(),
      workspace_id: read(8),
      authority_scope_cid: resources.coordinator_authority,
      installation: read(9),
      expires_ms,
    },
    limits: { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 32, },
  }
  // CLI configuration selects no numeric profile yet. A future reviewed Host
  // supplier passes the same preparation to acceptance and evidence custody;
  // Account admission neither constructs nor authenticates those byte widths.
  guard retain_holder_effect_host_snapshot(
    scope,
    root,
    snapshot,
    control_text_bytes~,
  ) else {
    stop("Effect Host snapshot holding unavailable")
  }
  {
    payload: Some({
      account,
      original_identity: identity,
      installation_current: current,
      preparation,
    }),
    scope,
  }
}
