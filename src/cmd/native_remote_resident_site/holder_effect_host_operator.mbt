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
  current_site : () -> Bool,
  preparation? : HolderEffectPreparationCapacity? = None,
) -> HolderEffectHostOperatorInstallation? raise CommandStop {
  let selected = match
    holder_effect_host_root(matches.values.get("effect-host-account-root")) {
    Ok(value) => value
    Err(issue) => stop(issue)
  }
  guard selected is Some(root) else { return None }
  let configured = required_int64(matches, "max-file-bytes")
  if configured <= 0L {
    stop("Effect Host Account file limit invalid")
  }
  let file_limit = if configured < 1000000L { configured } else { 1000000L }
  let subject_limit = if file_limit < 512L { file_limit } else { 512L }
  let names = [
    "host-principal.txt", "host-account-id.txt", "host-configuration-cid.txt", "host-authorization-context-cid.txt",
    "host-read-connection.txt", "host-read-resource.txt", "host-publication-connection.txt",
    "host-publication-resource.txt", "workspace-id.txt", "installation.txt", "host-identity-expires-ms.txt",
  ]
  let snapshot = names.map(name => (name, load_text(root, name, subject_limit)))
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
    ) {
    Ok(Some(value)) => value
    _ => stop("Effect Host Account installation refused")
  }
  let current = () => {
    current_site() &&
    holder_effect_host_snapshot_current(snapshot, name => {
      match @bounded_files.read_bounded_text_file(root, name, subject_limit) {
        Ok(value) => Some(value)
        Err(_) => None
      }
    }) &&
    @bounded_files.read_bounded_text_file(root, "account.json", file_limit)
    is Ok(_) &&
    @env.now().reinterpret_as_int64() >= 0L &&
    @env.now().reinterpret_as_int64() < expires_ms
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
  Some({
    account,
    original_identity: identity,
    installation_current: current,
    preparation,
  })
}
