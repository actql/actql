///|
// A finite explicitly selected installation original, not metadata evidence,
// a secret, an issuer decision or a permission inferred from a CLI flag.
priv struct NativeLocalSalesforcePreparationSelection {
  connection_revision : String
  connector_registration : String
  connector_revision : String
  environment : String
  namespace_id : String
  org_id : String
  resource_origin : String
}

///|
pub(all) enum NativeLocalSalesforcePreparationIssue {
  InvalidSelection
  ForeignInstallation
  AuthorizationDenied
  Adoption(NativeLocalAdoptionIssue)
  Original(NativeClientPreparationFenceIssue)
  Target(NativeClientLocalPreparationTargetIssue)
  Credential(@credential.RemoteCredentialIssue)
  Issuer(NativeLocalCredentialIssuerIssue)
  Journal(NativeClientRunJournalIssue)
}

///|
// Reuse the bounded value-preserving Local setting decoder. The public
// identity of this file never authorizes its installation or protected I/O.
fn admit_local_salesforce_preparation_selection(
  text : String,
) -> Result[
  NativeLocalSalesforcePreparationSelection,
  NativeLocalSalesforcePreparationIssue,
] {
  try {
    let node = match
      @source.parse_json_bytes_preserving(@utf8.encode(text), {
        max_input_bytes: 8192,
        max_nodes: 32,
        max_depth: 4,
      }) {
      Ok(value) => value
      Err(_) => return Err(InvalidSelection)
    }
    let cursor = local_issuer_decoded(
      @decode.admit(node, {
        max_nodes: 32,
        max_depth: 4,
        max_string_bytes: 2048,
        max_total_string_bytes: 4096,
      }),
    )
    let root = local_issuer_decoded(
      @decode.closed_object(cursor, ["version", "native"]),
    )
    if local_issuer_text(root, "version", 32) != "actql-config/0.1" {
      return Err(InvalidSelection)
    }
    let native = local_issuer_decoded(
      @decode.closed_object(local_issuer_field(root, "native"), ["salesforce"]),
    )
    let fields = local_issuer_decoded(
      @decode.closed_object(local_issuer_field(native, "salesforce"), [
        "connection_revision", "connector_registration", "connector_revision", "environment",
        "namespace_id", "org_id", "resource_origin",
      ]),
    )
    let selection : NativeLocalSalesforcePreparationSelection = {
      connection_revision: local_issuer_text(fields, "connection_revision", 512),
      connector_registration: local_issuer_text(
        fields, "connector_registration", 512,
      ),
      connector_revision: local_issuer_text(fields, "connector_revision", 512),
      environment: local_issuer_text(fields, "environment", 512),
      namespace_id: local_issuer_text(fields, "namespace_id", 512),
      org_id: local_issuer_text(fields, "org_id", 18),
      resource_origin: local_issuer_text(fields, "resource_origin", 2048),
    }
    if selection.connector_registration != "salesforce" ||
      @catalog.salesforce_implementation(selection.connector_revision) is None ||
      !selection.resource_origin.has_prefix("https://") ||
      selection.resource_origin.length() <= 8 ||
      selection.resource_origin[8:].contains("/") ||
      selection.resource_origin.contains("@") ||
      selection.resource_origin.contains(" ") ||
      selection.resource_origin.contains("\r") ||
      selection.resource_origin.contains("\n") ||
      selection.resource_origin.contains("\t") ||
      selection.resource_origin.contains("?") ||
      selection.resource_origin.contains("#") {
      return Err(InvalidSelection)
    }
    Ok(selection)
  } catch {
    LocalCredentialIssuerStop(_) => Err(InvalidSelection)
  }
}

///|
// Resolve only an initial explicitly selected file, with its current physical
// generation, content and journal custody. Re-reading an identical replacement
// or discovering another file cannot create a new installation selection.
fn NativeLocalHostConnection::selected_salesforce_preparation(
  self : NativeLocalHostConnection,
  file_name : String,
) -> Result[
  (NativeLocalSelectedFile, NativeLocalSalesforcePreparationSelection),
  NativeLocalSalesforcePreparationIssue,
] {
  guard self.session.settings.files
    .iter()
    .find_first(file => file.name == file_name)
    is Some(file) else {
    return Err(ForeignInstallation)
  }
  let selected = match self.selected_configuration(file_name) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if selected != file.body {
    return Err(ForeignInstallation)
  }
  let text = @utf8.decode(selected) catch { _ => return Err(InvalidSelection) }
  admit_local_salesforce_preparation_selection(text).map(selection => {
    (file, selection)
  })
}

///|
// Current Host binding and read authority for this original checked target.
// Mutation apply and credential issuance use separate Account decisions.
struct NativeLocalSalesforcePreparationBinding {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  file : NativeLocalSelectedFile
  selection : NativeLocalSalesforcePreparationSelection
  principal : String
  connection : String
  scope : String
  fence : NativeClientEffectPreparationFence
  resource : String
}

///|
fn native_local_preparation_read_authorized(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  scope : String,
  resource : String,
) -> Bool {
  host.authority_scope_cid(principal, connection, crypto) is Ok(current) &&
  current == scope &&
  host.authorize({
    principal,
    connection,
    resource: "run",
    operation: "submit",
  })
  is Ok(@authorization.Allow(_)) &&
  host.authorize({ principal, connection, resource, operation: "read", })
  is Ok(@authorization.Allow(_))
}

///|
fn NativeLocalSalesforcePreparationBinding::require_current(
  self : NativeLocalSalesforcePreparationBinding,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  if !physical_equal(self.host.journal, self.fence.work.journal) ||
    @host.client_request_authority_scope_cid(self.fence.work.request) !=
    self.scope {
    return Err(ForeignInstallation)
  }
  match self.fence.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  let (selected, _) = match
    self.host.selected_salesforce_preparation(self.file.name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if selected.body != self.file.body ||
    selected.content_cid != self.file.content_cid ||
    selected.generation != self.file.generation ||
    !native_local_preparation_read_authorized(
      self.host,
      self.crypto,
      self.principal,
      self.connection,
      self.scope,
      self.resource,
    ) {
    return Err(AuthorizationDenied)
  }
  guard @host.client_effect_member_descriptor(
      self.fence.work.materials.prepared,
      self.fence.stage,
      self.fence.effect_id,
      self.fence.max_work,
    )
    is Ok(descriptor) &&
    descriptor.0 == self.fence.member_index &&
    descriptor.2 == "update" &&
    descriptor.3 == self.resource else {
    return Err(ForeignInstallation)
  }
  // Account/adoption getters are observations, not a new physical start. Their
  // callbacks must not leave cancellation or capture closure unchecked.
  self.fence.require_current().map_err(issue => Original(issue))
}

///|
/// Bind only an explicitly adopted finite Provider setting to the same live
/// Work. Current read of its checked target is separate from submit/Source,
/// issuer issue, Reviewer approval and mutation apply. No secret is installed.
pub fn NativeLocalHostConnection::bind_salesforce_preparation(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  file_name : String,
  principal : String,
  connection : String,
  fence : NativeClientEffectPreparationFence,
) -> Result[
  NativeLocalSalesforcePreparationBinding,
  NativeLocalSalesforcePreparationIssue,
] {
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  let (file, selection) = match
    self.selected_salesforce_preparation(file_name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let descriptor = match
    @host.client_effect_member_descriptor(
      fence.work.materials.prepared,
      fence.stage,
      fence.effect_id,
      fence.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(Member(issue)))
  }
  let binding : NativeLocalSalesforcePreparationBinding = {
    host: self,
    crypto,
    file,
    selection,
    principal,
    connection,
    scope,
    fence,
    resource: descriptor.3,
  }
  binding.require_current().map(_ => binding)
}

///|
/// Derive Catalog identity from actual adoption/current Account, selected
/// Provider original and original Work. This does not perform metadata I/O.
pub fn NativeLocalSalesforcePreparationBinding::catalog_binding(
  self : NativeLocalSalesforcePreparationBinding,
  sync_occurrence : String,
) -> Result[
  @catalog.LocalCatalogObservationBinding,
  NativeLocalSalesforcePreparationIssue,
] {
  if sync_occurrence.is_empty() ||
    sync_occurrence.length() > 256 ||
    sync_occurrence.contains("\u{0}") {
    return Err(InvalidSelection)
  }
  self
  .require_current()
  .map(_ => {
    let fields = @credential.local_preparation_fence_fields(self.fence.identity)
    {
      account_configuration_cid: self.host.session.configuration.configuration_cid(),
      account_id: self.host.session.configuration.account_id(),
      authority_scope_cid: self.scope,
      client_request_intent_cid: fields.client_request_intent_cid,
      client_request_scope_cid: fields.client_request_scope_cid,
      connection_revision: self.selection.connection_revision,
      connector_registration: self.selection.connector_registration,
      connector_revision: self.selection.connector_revision,
      environment: self.selection.environment,
      host_adoption_cid: self.host.adoption_cid,
      namespace_id: self.selection.namespace_id,
      org_id: self.selection.org_id,
      principal: self.principal,
      resource_origin: self.selection.resource_origin,
      run_invocation_cid: fields.run_invocation_cid,
      sync_occurrence,
    }
  })
}

///|
fn NativeLocalSalesforcePreparationBinding::require_target(
  self : NativeLocalSalesforcePreparationBinding,
  target : NativeClientLocalPreparationTarget,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !physical_equal(self.fence, target.fence) {
    return Err(ForeignInstallation)
  }
  let actual = match self.catalog_binding(target.binding.sync_occurrence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if actual != target.binding {
    return Err(ForeignInstallation)
  }
  target.require_current().map_err(issue => Target(issue))
}
