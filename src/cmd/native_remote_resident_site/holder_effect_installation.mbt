///|
/// Optional local operator installation. These private files contain Provider
/// grant/public verification configuration, never Reviewer approval. Only the
/// existing credential Owner may consume a grant or send its configured request.
priv struct HolderEffectResumeInstallation {
  database : @sqlite.Database
  client : @http.Client
  configuration : @effect_review.NativeResidentEffectCloudResumeInstallation
  scope : @effect_resource.NativeCredentialScope
  current : () -> Bool
  mut client_closed : Bool
  mut database_closed : Bool
}

///|
/// A signed Provider grant is not a Reviewer identity or permission. Projection
/// is used only after the existing issuer verifier, and must match independently
/// configured Site, runtime, workspace and Connector before service installation.
fn holder_effect_provider_scope(
  fields : Array[String],
  workspace : String,
  site_key : String,
  site_generation : Int,
  runtime : String,
  registration : String,
  revision : String,
) -> @effect_resource.NativeCredentialScope? {
  guard fields.length() == 17 &&
    fields[3] == workspace &&
    fields[5] == site_key &&
    fields[6] == site_generation.to_string() &&
    fields[7] == runtime &&
    fields[8] == registration &&
    fields[9] == revision &&
    fields[11] == "salesforce:record:create" else {
    return None
  }
  let attempt : Int = @string.from_str(fields[13]) catch { _ => return None }
  if attempt < 0 {
    return None
  }
  Some({
    principal: fields[2],
    namespace_id: workspace,
    environment: fields[4],
    site_key,
    site_generation,
    runtime_bundle_cid: runtime,
    connector_registration: registration,
    connector_revision: revision,
    resource_origin: fields[10],
    operation: fields[11],
    run_invocation_cid: fields[12],
    task_attempt: attempt,
    dispatch_request_cid: fields[14],
  })
}

///|
/// Open only before a Source start claim. Fixed bounded filenames are selected
/// by the operator; neither Program nor dispatch can choose a key, database,
/// endpoint, secret path or grant. Absent configuration keeps the old no-send
/// path; malformed present configuration refuses rather than silently disabling.
fn open_holder_effect_resume_installation(
  matches : @argparse.Matches,
  sqlite_library : @sqlite.Library,
  resources : HolderOutputResources,
) -> HolderEffectResumeInstallation? raise CommandStop {
  guard optional(matches, "effect-resume-root") is Some(root) else {
    return None
  }
  let configured_limit = required_int64(matches, "max-file-bytes")
  let file_limit = if configured_limit < 65536L {
    configured_limit
  } else {
    65536L
  }
  let names = [
    "workspace-id.txt", "installation.txt", "host-key-id.txt", "host-public-key.pem",
    "credential-issuer.txt", "credential-key-id.txt", "credential-public-key.pem",
    "write-grant-cid.txt", "write-grant.json", "write-grant-signature.txt", "write-path.txt",
    "write-use-id.txt", "credential-org-id.txt", "provider-token-path.txt", "provider-ca-path.txt",
    "credential-db-path.txt", "effect-connector-registration.txt", "effect-connector-revision.txt",
  ]
  let snapshot = names.map(name => (name, load_text(root, name, file_limit)))
  for (_, body) in snapshot {
    if body.is_empty() {
      stop("Effect Resume installation contains an empty field")
    }
  }
  let read = (index : Int) => snapshot[index].1
  let crypto = match
    @signature.load_library(required(matches, "crypto-library")) {
    Ok(value) => value
    Err(_) => stop("Effect Resume signature library unavailable")
  }
  let envelope = match
    @effect_credential.admit_credential_signature_envelope(
      "actql-remote-credential-grant-signature/0.1",
      read(5),
      read(7),
      read(8),
      read(9),
    ) {
    Ok(value) => value
    Err(_) => stop("Effect Resume credential envelope refused")
  }
  let grant = match
    @effect_resource.admit_signed_native_credential_grant(crypto, envelope, [
      {
        issuer_authority: read(4),
        key_id: read(5),
        public_key_pem: read(6),
        admit_new_grants: true,
      },
    ]) {
    Ok(value) => value
    Err(_) => stop("Effect Resume credential signature refused")
  }
  let scope = match
    holder_effect_provider_scope(
      @effect_credential.credential_grant_projection(grant),
      read(0),
      resources.site_key,
      resources.site_generation,
      required(matches, "runtime-bundle-cid"),
      // Effect Provider registration is independently installed. The physical
      // Source Connector's delegation must not become an Effect permission.
      read(16),
      read(17),
    ) {
    Some(value) => value
    None => stop("Effect Resume credential scope refused")
  }
  let current = () => {
    // Rotation/removal never backfills the retained installation. This checks
    // configuration continuity only. Current Reviewer rights come from the
    // separate Cloud read; grant expiry/revocation remain credential-owned.
    snapshot.all(entry => {
      match @bounded_files.read_bounded_text_file(root, entry.0, file_limit) {
        Ok(value) => value == entry.1
        Err(_) => false
      }
    })
  }
  let http = match @http.load_library(required(matches, "http-library")) {
    Ok(value) => value
    Err(_) => stop("Effect Resume HTTP library unavailable")
  }
  let max_response = required_int64(matches, "max-response-bytes")
  let connect_timeout = required_int(matches, "connect-timeout-ms")
  let total_timeout = required_int(matches, "total-timeout-ms")
  let max_record = required_int64(matches, "max-record-bytes")
  let client = match
    http.create_client(
      read(14),
      "",
      "",
      max_response,
      connect_timeout,
      total_timeout,
    ) {
    Ok(value) => value
    Err(_) => stop("Effect Resume Provider client unavailable")
  }
  let database = match sqlite_library.open_database(read(15), max_record) {
    Ok(value) => value
    Err(_) => {
      close_holder_effect_installation_setup(client, None)
      stop("Effect Resume credential database unavailable")
    }
  }
  let service = match
    @effect_resource.install_native_credential_resource_service(
      database,
      client,
      [
        {
          resource_origin: scope.resource_origin,
          operation: "salesforce:record:create",
          path: read(10),
          secret_path: read(13),
          verb: @http.Post,
          max_request_bytes: 65536,
        },
      ],
      authorization => {
        current() &&
        authorization.grant_cid ==
        @effect_credential.credential_grant_cid(grant) &&
        // The existing service validates every grant/scope field before this
        // callback. This independently retains the configured dispatch only.
        authorization.scope.dispatch_request_cid == scope.dispatch_request_cid
      },
    ) {
    Ok(value) => value
    Err(_) => {
      close_holder_effect_installation_setup(client, Some(database))
      stop("Effect Resume credential service refused")
    }
  }
  let configuration : @effect_review.NativeResidentEffectCloudResumeInstallation = {
    crypto,
    scope: {
      site_key: resources.site_key,
      site_generation: resources.site_generation.to_int64(),
      workspace_id: read(0),
      authority_scope_cid: resources.coordinator_authority,
      installation: read(1),
    },
    keys: [{ key_id: read(2), public_key_pem: read(3), }],
    current_authority: current,
    now: () => start_timestamp(matches),
    limits: {
      ledger: resident_checkpoint_report_limits(),
      response: {
        max_bytes: 65536,
        max_nodes: 4096,
        max_depth: 32,
        max_rows: 1,
      },
    },
    access: request => {
      if !current() ||
        @effect_catalog.single_write_request_grant_operation(request) !=
        scope.operation ||
        @effect_catalog.single_write_request_method(request) != "POST" ||
        @effect_catalog.single_write_request_path(request) != read(10) {
        return Err(
          @effect_review.NativeResidentEffectWriteIssue::AuthorityDenied,
        )
      }
      // The row Owner still matches this exact Run/attempt/dispatch, org,
      // Catalog and canonical body, and obtains its durable Ledger claim.
      Ok({
        service,
        grant,
        use_id: read(11),
        scope,
        credential_org_id: read(12),
      })
    },
  }
  Some({
    database,
    client,
    configuration,
    scope,
    current,
    client_closed: false,
    database_closed: false,
  })
}

///|
/// Setup failures keep their primary reason while retrying the same acquired
/// physical handles. No Source/Compute claim has occurred at this boundary.
fn close_holder_effect_installation_setup(
  client : @http.Client,
  database : @sqlite.Database?,
) -> Unit {
  let mut client_closed = false
  let mut database_closed = database is None
  let mut wait_ms = 50
  while !client_closed || !database_closed {
    if !client_closed {
      client_closed = client.close()
    }
    if !database_closed && database is Some(value) {
      database_closed = value.close_checked() is Ok(_)
    }
    if !client_closed || !database_closed {
      report("cleanup-pending", [("step", "effect-resume-installation-setup")])
      @slot.native_wait_milliseconds(wait_ms)
      wait_ms = holder_effect_installation_backoff(wait_ms)
    }
  }
}

///|
fn holder_effect_installation_backoff(current : Int) -> Int {
  if current >= 2500 {
    5000
  } else {
    current * 2
  }
}

///|
fn HolderEffectResumeInstallation::for_dispatch(
  self : HolderEffectResumeInstallation,
  dispatch : @remote.DispatchRequest,
) -> @effect_review.NativeResidentEffectCloudResumeInstallation? {
  let execution = @remote.dispatch_request_execution_scope(dispatch)
  let route = @remote.dispatch_request_journal_key(dispatch)
  if !(self.current)() ||
    self.client_closed ||
    self.database_closed ||
    self.scope.site_key != execution[0] ||
    self.scope.site_generation.to_string() != execution[1] ||
    self.scope.runtime_bundle_cid != execution[2] ||
    self.scope.task_attempt.to_string() != route[6] ||
    self.scope.dispatch_request_cid !=
    @remote.dispatch_request_identity(dispatch) {
    return None
  }
  Some(self.configuration)
}

///|
/// Retain these exact existing physical Owners until each close succeeds.
/// Closing this installation is not Effect outcome or dispatch release.
fn HolderEffectResumeInstallation::close(
  self : HolderEffectResumeInstallation,
) -> Bool {
  if !self.client_closed {
    self.client_closed = self.client.close()
  }
  if !self.database_closed {
    self.database_closed = self.database.close_checked() is Ok(_)
  }
  self.client_closed && self.database_closed
}
