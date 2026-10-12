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
/// Real operator input entry, before the Source start claim. It opens no
/// Provider/credential/Store Owner. The existing bounded reader and Account
/// installer own file admission; no poll/candidate chooses a path or subject.
fn load_holder_effect_host_operator(
  matches : @argparse.Matches,
  resources : HolderOutputResources,
  environment : SiteEnvironment,
  current_site : () -> Bool,
  preparation? : HolderEffectPreparationCapacity? = None,
) -> HolderEffectHostOperatorInstallation? raise CommandStop {
  let selected = match
    holder_effect_host_root(matches.values.get("effect-host-account-root")) {
    Ok(value) => value
    Err(issue) => stop(issue)
  }
  guard selected is Some(root) else { return None }
  // No selected I/O without reviewed setup quantity and real Site capacity.
  // Project immutable binding facts before creating the closure. Capturing the
  // resources object here would retain its Ref[scope] back through the scope's
  // current predicate. Runtime/slot verifiers remain the existing Owners.
  let bundles = environment.bundles
  let active_runtime = environment.active_runtime
  let binding = holder_effect_host_setup_binding(
    environment.site,
    resources.site_key,
    resources.site_generation,
    environment.runtime_bundle_cid,
    current_site,
    () => bundles.verify_active_component_binding(active_runtime) is Ok(_),
  )
  guard begin_holder_effect_host_setup_scope(
      environment.site,
      // A production profile and a receiver for the original pending cleanup
      // carrier are both uninstalled. Refuse before reservation or physical I/O.
      None,
      binding,
    )
    is Some(scope) else {
    stop("Effect Host setup capacity unavailable")
  }
  resources.effect_host_setup.val = Some(scope)
  let installed = prepare_holder_effect_host_operator(
    root,
    matches,
    resources,
    scope,
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
  match
    @bounded_files.read_bounded_text_file_with_custody(
      root,
      name,
      limit,
      trim_newline~,
    ) {
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
  preparation? : HolderEffectPreparationCapacity? = None,
) -> HolderEffectHostOperatorInstallation raise CommandStop {
  let configured = required_int64(matches, "max-file-bytes")
  if configured <= 0L {
    stop("Effect Host Account file limit invalid")
  }
  let ceiling = scope.profile.read_ceiling.to_int64()
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
  guard retain_holder_effect_host_snapshot(scope, root, snapshot) else {
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
