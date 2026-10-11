///|
// This is an explicitly selected finite installation setting, not a grant or
// an authority obtained merely by parsing a caller's document.
struct NativeLocalCredentialIssuerSelection {
  enabled : Bool
  issuer_authority : String
  principal : String
  connection : String
  max_uses : Int
  expires_at : String
}

///|
pub(all) enum NativeLocalCredentialIssuerIssue {
  InvalidOriginal
  InvalidIssuerLimits
  SelectionMismatch
  Disabled
  Expired
  InvalidClock
  Adoption(NativeLocalAdoptionIssue)
  Authorization(@authorization.DispatchBindingIssue)
}

///|
priv suberror LocalCredentialIssuerStop {
  LocalCredentialIssuerStop(NativeLocalCredentialIssuerIssue)
}

///|
fn[T] local_issuer_decoded(
  value : Result[T, @decode.Issue],
) -> T raise LocalCredentialIssuerStop {
  match value {
    Ok(value) => value
    Err(_) => raise LocalCredentialIssuerStop(InvalidOriginal)
  }
}

///|
fn local_issuer_field(
  object : @decode.ObjectView,
  name : String,
) -> @decode.Cursor raise LocalCredentialIssuerStop {
  local_issuer_decoded(@decode.required(object, name))
}

///|
fn local_issuer_text(
  object : @decode.ObjectView,
  name : String,
  limit : Int,
) -> String raise LocalCredentialIssuerStop {
  let value = local_issuer_decoded(
    @decode.text(local_issuer_field(object, name)),
  )
  if value.is_empty() || value.length() > limit || value.contains("\u{0}") {
    raise LocalCredentialIssuerStop(InvalidOriginal)
  }
  value
}

///|
/// Syntax admission only, using the existing Local configuration version.
/// No secret is read, grant is issued, or Account permission is inferred.
pub fn admit_native_local_credential_issuer_selection(
  text : String,
) -> Result[
  NativeLocalCredentialIssuerSelection,
  NativeLocalCredentialIssuerIssue,
] {
  try {
    let node = match
      @source.parse_json_bytes_preserving(@utf8.encode(text), {
        max_input_bytes: 8192,
        max_nodes: 32,
        max_depth: 4,
      }) {
      Ok(value) => value
      Err(_) => return Err(InvalidOriginal)
    }
    let cursor = local_issuer_decoded(
      @decode.admit(node, {
        max_nodes: 32,
        max_depth: 4,
        max_string_bytes: 512,
        max_total_string_bytes: 2048,
      }),
    )
    let root = local_issuer_decoded(
      @decode.closed_object(cursor, ["version", "native"]),
    )
    if local_issuer_text(root, "version", 32) != "actql-config/0.1" {
      return Err(InvalidOriginal)
    }
    let native = local_issuer_decoded(
      @decode.closed_object(local_issuer_field(root, "native"), [
        "credential_issuer",
      ]),
    )
    let fields = local_issuer_decoded(
      @decode.closed_object(local_issuer_field(native, "credential_issuer"), [
        "enabled", "issuer_authority", "principal", "connection", "max_uses", "expires_at",
      ]),
    )
    let max_uses = local_issuer_decoded(
      @decode.safe_integer(local_issuer_field(fields, "max_uses")),
    )
    if max_uses < 1L || max_uses > 1024L {
      return Err(InvalidIssuerLimits)
    }
    let expires_at = local_issuer_text(fields, "expires_at", 24)
    if @values.timestamp_epoch_milliseconds(expires_at) is None {
      return Err(InvalidOriginal)
    }
    Ok({
      enabled: local_issuer_decoded(
        @decode.boolean(local_issuer_field(fields, "enabled")),
      ),
      issuer_authority: local_issuer_text(fields, "issuer_authority", 501),
      principal: local_issuer_text(fields, "principal", 512),
      connection: local_issuer_text(fields, "connection", 512),
      max_uses: max_uses.to_int(),
      expires_at,
    })
  } catch {
    LocalCredentialIssuerStop(issue) => Err(issue)
  }
}

///|
// Only the adopted Host obtains this capability through the existing Account
// Owner. It is confined to one original issuance/adoption intent and scope.
// It does not authorize a checked Effect, expose a secret or permit a send.
struct NativeLocalCredentialIssuerBinding {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  file : NativeLocalSelectedFile
  selection : NativeLocalCredentialIssuerSelection
  principal : String
  connection : String
  scope : String
  operation_cid : String
  authorization : @authorization.DispatchAuthorization
}

///|
fn local_issuer_tuple(
  principal : String,
  connection : String,
  issuer : String,
) -> @authorization.AccessTuple {
  {
    principal,
    connection,
    resource: "credential/" + issuer,
    operation: "issue",
  }
}

///|
// Clock injection is private to the owning module's deterministic boundary
// fixtures. Public acquisition samples the real Host clock, never a caller time.
fn NativeLocalCredentialIssuerBinding::require_current_at(
  self : NativeLocalCredentialIssuerBinding,
  host : NativeLocalHostConnection,
  operation_cid : String,
  at : Int64,
) -> Result[Unit, NativeLocalCredentialIssuerIssue] {
  if !physical_equal(self.host, host) || operation_cid != self.operation_cid {
    return Err(SelectionMismatch)
  }
  let scope = match
    host.authority_scope_cid(self.principal, self.connection, self.crypto) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if scope != self.scope {
    return Err(SelectionMismatch)
  }
  let selected = match host.selected_configuration(self.file.name) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if selected != self.file.body || !self.selection.enabled {
    return Err(
      if self.selection.enabled {
        SelectionMismatch
      } else {
        Disabled
      },
    )
  }
  if at < 0L || at > 9007199254740991L {
    return Err(InvalidClock)
  }
  if self.selection.max_uses < 1 || self.selection.max_uses > 1024 {
    return Err(InvalidIssuerLimits)
  }
  guard @values.timestamp_epoch_milliseconds(self.selection.expires_at)
    is Some(expiry) else {
    return Err(InvalidOriginal)
  }
  if at >= expiry {
    return Err(Expired)
  }
  let tuple = local_issuer_tuple(
    self.principal,
    self.connection,
    self.selection.issuer_authority,
  )
  if !@authorization.dispatch_authorization_matches(
      self.authorization,
      host.session.configuration,
      tuple,
      @authorization.Activation,
      operation_cid,
      scope,
    ) {
    return Err(Authorization(@authorization.ForeignDecision))
  }
  match
    @authorization.bind_dispatch_authorization(
      host.session.configuration,
      tuple,
      @authorization.Activation,
      operation_cid,
      scope,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Authorization(issue))
  }
  // Recheck original physical custody after the Owner decision. A cached
  // authorization cannot repair changed or removed installation originals.
  host.check_binding().map_err(issue => Adoption(issue))
}

///|
fn NativeLocalCredentialIssuerBinding::require_current(
  self : NativeLocalCredentialIssuerBinding,
  host : NativeLocalHostConnection,
  operation_cid : String,
) -> Result[Unit, NativeLocalCredentialIssuerIssue] {
  self.require_current_at(
    host,
    operation_cid,
    @env.now().reinterpret_as_int64(),
  )
}

///|
/// Acquire the current issuer decision for an explicit original grant-adoption
/// intent. A selected installation is not a grant, and submit/approval/resume
/// never call this implicitly. Persistence must separately verify the original
/// Run, checked Provider request, real resume claim, lease and use custody.
pub fn NativeLocalHostConnection::acquire_credential_issuer(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  file_name : String,
  principal : String,
  connection : String,
  operation_cid : String,
) -> Result[
  NativeLocalCredentialIssuerBinding,
  NativeLocalCredentialIssuerIssue,
] {
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  guard self.session.settings.files
    .iter()
    .find_first(file => file.name == file_name)
    is Some(file) else {
    return Err(SelectionMismatch)
  }
  let text = @utf8.decode(file.body) catch { _ => return Err(InvalidOriginal) }
  let selection = match admit_native_local_credential_issuer_selection(text) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if principal != selection.principal || connection != selection.connection {
    return Err(SelectionMismatch)
  }
  if !selection.enabled {
    return Err(Disabled)
  }
  let authorization = match
    @authorization.bind_dispatch_authorization(
      self.session.configuration,
      local_issuer_tuple(principal, connection, selection.issuer_authority),
      @authorization.Activation,
      operation_cid,
      scope,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authorization(issue))
  }
  let binding : NativeLocalCredentialIssuerBinding = {
    host: self,
    crypto,
    file,
    selection,
    principal,
    connection,
    scope,
    operation_cid,
    authorization,
  }
  binding.require_current(self, operation_cid).map(_ => binding)
}
