///|
// Identity-only reference to the existing exact immutable grant packet.
// Admission cannot create a live Work fence, grant ACK or credential-use claim.
struct NativeLocalPreparationGrantReference {
  original : NativeLocalGrantOriginal
}

///|
pub(all) enum NativeLocalPreparationGrantLookup {
  RetainedOriginal
  UnresolvedOriginal
}

///|
/// Retain this exact original before invoking adoption. This serializes only
/// the existing bounded original packet; it does not commit or issue anything.
pub fn NativeLocalPreparationGrantOperation::reference_record(
  self : NativeLocalPreparationGrantOperation,
) -> Result[Bytes, NativeLocalSalesforcePreparationIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let packet = match local_grant_original_packet(self.original) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  self.require_current().map(_ => packet)
}

///|
/// Validate identity through the same original packet/intent/grant reader.
/// No authorization, journal mutation or physical entry is inferred from it.
pub fn admit_native_local_preparation_grant_reference(
  crypto : @crypto.Library,
  operation_cid : String,
  packet : Bytes,
) -> Result[NativeLocalPreparationGrantReference, NativeClientRunJournalIssue] {
  let object = match local_grant_packet_object(packet) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(object, "intent") is Some(intent) else {
    return Err(CustodyLost)
  }
  let fields = match
    local_adoption_fields(@utf8.encode(intent), [
      "domain", "grant_cid", "issuer_selection_cid", "operation_id", "request",
    ]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let request = match
    @host.admit_client_request_identity_record_wire(fields[4]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let key = match local_grant_original_key(crypto, request, fields[3]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = match
    read_local_grant_original(crypto, { key, body: packet, revision: 0L, }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard original.grant is PreparationGrant(_) &&
    original.operation_cid == operation_cid else {
    return Err(ChangedIntent)
  }
  Ok({ original, })
}

///|
pub fn NativeLocalPreparationGrantReference::operation_cid(
  self : NativeLocalPreparationGrantReference,
) -> String {
  self.original.operation_cid
}

///|
// History lookup requires current original Run read. Issuer acquisition below
// separately checks its existing exact operation-bound issue authority. Neither
// lookup permission substitutes for current target read or a live send fence.
fn NativeLocalHostConnection::preparation_grant_lookup_current(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeLocalPreparationGrantReference,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  guard reference.original.grant is PreparationGrant(grant) else {
    return Err(ForeignInstallation)
  }
  let scope = @credential.local_preparation_credential_grant_scope(grant)
  let current_scope = match
    self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if current_scope != scope.authority_scope_cid ||
    current_scope !=
    @host.client_request_authority_scope_cid(reference.original.request) ||
    principal != scope.principal ||
    scope.host_adoption_cid != self.adoption_cid ||
    scope.account_configuration_cid !=
    self.session.configuration.configuration_cid() ||
    scope.account_id != self.session.configuration.account_id() {
    return Err(ForeignInstallation)
  }
  if !(self.authorize({
      principal,
      connection,
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Allow(_))) {
    return Err(AuthorizationDenied)
  }
  // Recheck original installation after the independent Account observation.
  self.check_binding().map_err(issue => Adoption(issue))
}

///|
/// Query the exact original operation after response loss or process restart.
/// The result contains no operational grant ACK, Work token or entry permit.
/// Absence is unresolved, never proof that issuance/use/send did not occur.
pub fn NativeLocalHostConnection::lookup_preparation_grant_operation(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  issuer_file_name : String,
  principal : String,
  connection : String,
  reference : NativeLocalPreparationGrantReference,
) -> Result[
  NativeLocalPreparationGrantLookup,
  NativeLocalSalesforcePreparationIssue,
] {
  match
    self.preparation_grant_lookup_current(
      crypto, principal, connection, reference,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let issuer = match
    self.acquire_credential_issuer(
      crypto,
      issuer_file_name,
      principal,
      connection,
      reference.original.operation_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Issuer(issue))
  }
  match
    self.preparation_grant_lookup_current(
      crypto, principal, connection, reference,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let saved = match issuer.lookup_grant_original(reference.original) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match issuer.require_current(self, reference.original.operation_cid) {
    Ok(_) => ()
    Err(issue) => return Err(Issuer(issue))
  }
  match
    self.preparation_grant_lookup_current(
      crypto, principal, connection, reference,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match saved {
    Some(original) if original.intent == reference.original.intent &&
      original.operation_cid == reference.original.operation_cid =>
      Ok(RetainedOriginal)
    Some(_) => Err(Journal(ChangedIntent))
    None => Ok(UnresolvedOriginal)
  }
}
