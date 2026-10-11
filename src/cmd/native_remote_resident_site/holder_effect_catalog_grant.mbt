///|
/// Installation configuration is selected by the operator, independently of
/// grant wire, Source permission and Reviewer authority. Original invocation
/// and consumer routing are supplied by the retained preparation Owners.
priv struct HolderEffectCatalogScope {
  workspace : String
  principal : String
  environment : String
  registration : String
  revision : String
  origin : String
}

///|
/// Projection is not signature verification. The installation calls the
/// existing credential verifier before this exact original-scope comparison.
fn holder_effect_catalog_grant_scope(
  fields : Array[String],
  configured : HolderEffectCatalogScope,
  invocation_cid : String,
  execution : Array[String],
  route : Array[String],
  dispatch_cid : String,
) -> @effect_resource.NativeCredentialScope? {
  guard fields.length() == 17 &&
    execution.length() >= 3 &&
    route.length() >= 7 &&
    fields[2] == configured.principal &&
    fields[3] == configured.workspace &&
    fields[4] == configured.environment &&
    fields[5] == execution[0] &&
    fields[6] == execution[1] &&
    fields[7] == execution[2] &&
    fields[8] == configured.registration &&
    fields[9] == configured.revision &&
    fields[10] == configured.origin &&
    fields[11] == "salesforce:catalog:describe" &&
    fields[12] == invocation_cid &&
    fields[13] == route[6] &&
    fields[14] == dispatch_cid else {
    return None
  }
  let generation : Int = @string.from_str(execution[1]) catch {
    _ => return None
  }
  let attempt : Int = @string.from_str(route[6]) catch { _ => return None }
  guard generation >= 0 && attempt >= 0 else { return None }
  Some({
    principal: configured.principal,
    namespace_id: configured.workspace,
    environment: configured.environment,
    site_key: execution[0],
    site_generation: generation,
    runtime_bundle_cid: execution[2],
    connector_registration: configured.registration,
    connector_revision: configured.revision,
    resource_origin: configured.origin,
    operation: "salesforce:catalog:describe",
    run_invocation_cid: invocation_cid,
    task_attempt: attempt,
    dispatch_request_cid: dispatch_cid,
  })
}

///|
/// This borrows the existing physical credential Owners. The caller retains
/// the installation and every read/save failure until its own cleanup is
/// confirmed. Closing these handles is not Catalog custody or task release.
priv struct HolderEffectCatalogInstallation {
  database : @sqlite.Database
  client : @http.Client
  service : @effect_resource.NativeCredentialResourceService
  grant : @effect_credential.RemoteCredentialGrant
  scope : @effect_resource.NativeCredentialScope
  binding : @effect_catalog.CatalogObservationBinding
  use_id : String
  resource : String
  api_version : String
  current : () -> Bool
  mut client_closed : Bool
  mut database_closed : Bool
}

///|
/// A future Review-policy caller selects this fixed root only after obtaining
/// genuine original producer custody. No Source/Compute execution, credential
/// use, Provider I/O or write occurs during installation. Candidate Catalog
/// bytes never select expected Run/dispatch/generation or grant scope.
fn open_holder_effect_catalog_installation(
  root : String,
  matches : @argparse.Matches,
  sqlite_library : @sqlite.Library,
  resources : HolderOutputResources,
  original : HolderEffectOriginalPolicyContext,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> HolderEffectCatalogInstallation? raise CommandStop {
  guard original.invocation(max_bytes, max_nodes, max_depth)
    is Some((_, invocation)) else {
    return None
  }
  let configured_limit = required_int64(matches, "max-file-bytes")
  let file_limit = if configured_limit < 65536L {
    configured_limit
  } else {
    65536L
  }
  let names = [
    "workspace-id.txt", "provider-principal.txt", "environment.txt", "effect-connector-registration.txt",
    "effect-connector-revision.txt", "provider-origin.txt", "connection-revision.txt",
    "credential-org-id.txt", "catalog-occurrence.txt", "catalog-resource.txt", "catalog-api-version.txt",
    "catalog-use-id.txt", "credential-issuer.txt", "credential-key-id.txt", "credential-public-key.pem",
    "catalog-grant-cid.txt", "catalog-grant.json", "catalog-grant-signature.txt",
    "provider-token-path.txt", "provider-ca-path.txt", "credential-db-path.txt",
  ]
  let snapshot = names.map(name => (name, load_text(root, name, file_limit)))
  for (_, body) in snapshot {
    if body.is_empty() {
      stop("Effect Catalog installation contains an empty field")
    }
  }
  let read = (index : Int) => snapshot[index].1
  let crypto = match
    @signature.load_library(required(matches, "crypto-library")) {
    Ok(value) => value
    Err(_) => stop("Effect Catalog signature library unavailable")
  }
  let envelope = match
    @effect_credential.admit_credential_signature_envelope(
      "actql-remote-credential-grant-signature/0.1",
      read(13),
      read(15),
      read(16),
      read(17),
    ) {
    Ok(value) => value
    Err(_) => stop("Effect Catalog credential envelope refused")
  }
  let grant = match
    @effect_resource.admit_signed_native_credential_grant(crypto, envelope, [
      {
        issuer_authority: read(12),
        key_id: read(13),
        public_key_pem: read(14),
        admit_new_grants: true,
      },
    ]) {
    Ok(value) => value
    Err(_) => stop("Effect Catalog credential signature refused")
  }
  let execution = @remote.dispatch_request_execution_scope(
    original.task.request,
  )
  let route = @remote.dispatch_request_journal_key(original.task.request)
  let scope = match
    holder_effect_catalog_grant_scope(
      @effect_credential.credential_grant_projection(grant),
      {
        workspace: read(0),
        principal: read(1),
        environment: read(2),
        registration: read(3),
        revision: read(4),
        origin: read(5),
      },
      @publication.publication_contract_identity(invocation),
      execution,
      route,
      @remote.dispatch_request_identity(original.task.request),
    ) {
    Some(value) => value
    None => stop("Effect Catalog original credential scope refused")
  }
  if scope.site_key != resources.site_key ||
    scope.site_generation != resources.site_generation {
    stop("Effect Catalog holder Site refused")
  }
  let binding : @effect_catalog.CatalogObservationBinding = {
    namespace_id: scope.namespace_id,
    principal: scope.principal,
    environment: scope.environment,
    connection_revision: read(6),
    org_id: read(7),
    site_key: scope.site_key,
    site_generation: scope.site_generation,
    connector_registration: scope.connector_registration,
    connector_revision: scope.connector_revision,
    resource_origin: scope.resource_origin,
    run_invocation_cid: scope.run_invocation_cid,
    dispatch_request_cid: scope.dispatch_request_cid,
    sync_occurrence: read(8),
  }
  let current = () => {
    original.current() &&
    snapshot.all(entry => {
      match @bounded_files.read_bounded_text_file(root, entry.0, file_limit) {
        Ok(value) => value == entry.1
        Err(_) => false
      }
    })
  }
  // Do not open a physical service after the last original/configuration read
  // has invalidated custody. Expiry and revocation remain credential-owned.
  if !current() {
    return None
  }
  let http = match @http.load_library(required(matches, "http-library")) {
    Ok(value) => value
    Err(_) => stop("Effect Catalog HTTP library unavailable")
  }
  let client = match
    http.create_client(
      read(19),
      "",
      "",
      required_int64(matches, "max-response-bytes"),
      required_int(matches, "connect-timeout-ms"),
      required_int(matches, "total-timeout-ms"),
    ) {
    Ok(value) => value
    Err(_) => stop("Effect Catalog Provider client unavailable")
  }
  let database = match
    sqlite_library.open_database(
      read(20),
      required_int64(matches, "max-record-bytes"),
    ) {
    Ok(value) => value
    Err(_) => {
      close_holder_effect_installation_setup(client, None)
      stop("Effect Catalog credential database unavailable")
    }
  }
  let service = match
    @effect_resource.install_native_credential_resource_service(
      database,
      client,
      [
        {
          resource_origin: scope.resource_origin,
          operation: scope.operation,
          path: "/services/data/" +
          read(10) +
          "/sobjects/" +
          read(9) +
          "/describe",
          secret_path: read(18),
          verb: @http.Get,
          max_request_bytes: 65536,
        },
      ],
      authorization => {
        current() &&
        authorization.grant_cid ==
        @effect_credential.credential_grant_cid(grant) &&
        authorization.scope.dispatch_request_cid == scope.dispatch_request_cid
      },
    ) {
    Ok(value) => value
    Err(_) => {
      close_holder_effect_installation_setup(client, Some(database))
      stop("Effect Catalog credential service refused")
    }
  }
  Some({
    database,
    client,
    service,
    grant,
    scope,
    binding,
    use_id: read(11),
    resource: read(9),
    api_version: read(10),
    current,
    client_closed: false,
    database_closed: false,
  })
}

///|
/// Close only the acquired service handles, retaining a failed handle for
/// retry. The caller separately owns Catalog response/Store custody cleanup.
fn HolderEffectCatalogInstallation::close(
  self : HolderEffectCatalogInstallation,
) -> Bool {
  if !self.client_closed {
    self.client_closed = self.client.close()
  }
  if !self.database_closed {
    self.database_closed = self.database.close_checked() is Ok(_)
  }
  self.client_closed && self.database_closed
}

///|
/// The policy caller retains the returned raw-response/pending-Store failure.
/// This performs one existing credential use and exact save/readback; it never
/// retries a Provider read. Subsequent retries must use the returned Store
/// custody through retry_native_salesforce_catalog_custody instead.
fn HolderEffectCatalogInstallation::observe(
  self : HolderEffectCatalogInstallation,
  resources : HolderOutputResources,
  limits : @effect_catalog.DescribeLimits,
  max_observation_bytes : Int,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[
  (
    @publication_store.EffectCatalogCustody,
    @publication_store.NativeEffectCatalogResponse,
  ),
  @effect_review.NativeSalesforceCatalogCustodyFailure,
] {
  @effect_review.observe_and_retain_native_salesforce_named_catalog(
    self.service,
    self.grant,
    self.use_id,
    self.scope,
    self.binding,
    self.binding.org_id,
    self.api_version,
    self.resource,
    limits,
    max_observation_bytes,
    resources.store,
    crypto,
    key,
    () => !self.client_closed && !self.database_closed && (self.current)(),
  )
}
