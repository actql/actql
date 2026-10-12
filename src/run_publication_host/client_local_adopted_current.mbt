///|
/// Facts supplied only by the trusted Host's existing adoption/current fence.
/// Observed means the original filesystem/settings/transaction checks finished;
/// it is not a caller grant. The row is the actual committed adoption row.
pub(all) enum ClientLocalAdoptionCurrentObservation[Store] {
  NotAdopted
  CommitUnknown
  Observed(
    Store,
    @authorization.AdmittedAccountConfiguration,
    Bytes,
    ClientJournalPhysicalRow,
    (UInt64, UInt64)
  )
}

///|
pub(all) enum ClientLocalAdoptedCurrentIssue[E] {
  Physical(E)
  NotAdopted
  CommitUnknown
  InvalidOriginal
  ForeignStore
  ChangedCurrent
  Scope(ClientLocalAuthorityScopeIssue)
}

///|
/// Read-only original custody and its trusted current port, not a new Owner.
/// The port must retain its original lock, Store and input/workspace loans.
/// No operation here adopts, writes, repairs, submits, dispatches or retries.
pub struct ClientLocalAdoptedHostMaterial[Store, E] {
  store : Store
  account : @authorization.AdmittedAccountConfiguration
  account_original : Bytes
  adoption : ClientJournalPhysicalRow
  generation : (UInt64, UInt64)
  current : () -> Result[ClientLocalAdoptionCurrentObservation[Store], E]
}

///|
fn client_local_original_adoption(
  row : ClientJournalPhysicalRow,
  generation : (UInt64, UInt64),
) -> Bool {
  if row.key != "adoption" || row.revision != 0L || row.body.length() > 8192 {
    return false
  }
  let cursor = match
    @source.parse_json_bytes_preserving(row.body, {
      max_input_bytes: 8192,
      max_nodes: 64,
      max_depth: 4,
    }) {
    Err(_) => return false
    Ok(value) =>
      match
        @decode.admit(value, {
          max_nodes: 64,
          max_depth: 4,
          max_string_bytes: 4096,
          max_total_string_bytes: 8192,
        }) {
        Ok(value) => value
        Err(_) => return false
      }
  }
  let keys = [
    "configuration_custody_cid", "device", "inode", "intent_cid", "version",
  ]
  let object = match @decode.closed_object(cursor, keys) {
    Ok(value) => value
    Err(_) => return false
  }
  let fields : Array[String] = []
  for key in keys {
    guard @decode.lookup(object, key) is Some(value) &&
      @decode.text(value) is Ok(text) else {
      return false
    }
    fields.push(text)
  }
  if fields[1] != generation.0.to_string() ||
    fields[2] != generation.1.to_string() ||
    fields[4] != "actql-native-local-journal-custody/0.1" {
    return false
  }
  // These links are existing Owner identities, not new permission identifiers.
  for cid in [fields[0], fields[3]] {
    if cid.length() != 71 || !cid.has_prefix("sha256:") {
      return false
    }
    for index in 7..<cid.length() {
      let code = cid[index]
      if !((code >= '0' && code <= '9') || (code >= 'a' && code <= 'f')) {
        return false
      }
    }
  }
  let writer = @encode.writer(8192, 64, 4) catch { _ => return false }
  try {
    @encode.begin_object(writer)
    for index in 0..<keys.length() {
      @encode.key(writer, keys[index])
      @encode.string_value(writer, fields[index])
    }
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer)) == row.body
  } catch {
    _ => false
  }
}

///|
fn[Store, E] client_local_observed_current(
  current : () -> Result[ClientLocalAdoptionCurrentObservation[Store], E],
) -> Result[
  (
    Store,
    @authorization.AdmittedAccountConfiguration,
    Bytes,
    ClientJournalPhysicalRow,
    (UInt64, UInt64),
  ),
  ClientLocalAdoptedCurrentIssue[E],
] {
  match current() {
    Err(issue) => Err(Physical(issue))
    Ok(NotAdopted) => Err(NotAdopted)
    Ok(CommitUnknown) => Err(CommitUnknown)
    Ok(Observed(store, account, account_original, row, generation)) =>
      if client_local_original_adoption(row, generation) {
        Ok((store, account, account_original, row, generation))
      } else {
        Err(InvalidOriginal)
      }
  }
}

///|
/// Bind already committed, genuine adoption through the trusted original port.
/// The supplier must use the existing Host fence and complete singleton adoption
/// inspection; JSON or a callback shape cannot authenticate a malicious supplier.
pub fn[Store, E] bind_client_local_adopted_host_material(
  store : Store,
  current : () -> Result[ClientLocalAdoptionCurrentObservation[Store], E],
) -> Result[
  ClientLocalAdoptedHostMaterial[Store, E],
  ClientLocalAdoptedCurrentIssue[E],
] {
  let (observed, account, account_original, row, generation) = match
    client_local_observed_current(current) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !physical_equal(store, observed) {
    return Err(ForeignStore)
  }
  // Preserve the actual source bytes as well as the configuration identity.
  // Configuration canonicalization cannot excuse replacement of its original.
  if account_original.length() > 1048576 {
    return Err(InvalidOriginal)
  }
  let account_wire = @utf8.decode(account_original) catch {
    _ => return Err(InvalidOriginal)
  }
  let original = match
    @authorization.admit_account_configuration_json(account_wire) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  if original.configuration_cid() != account.configuration_cid() {
    return Err(InvalidOriginal)
  }
  let material = {
    store,
    account,
    account_original,
    adoption: row,
    generation,
    current,
  }
  match client_local_adopted_current_account(material, store) {
    Ok(_) => Ok(material)
    Err(issue) => Err(issue)
  }
}

///|
/// Recheck physical current before each scope, Account or publisher operation.
/// A changed original cannot be filled in from a new default configuration.
pub fn[Store, E] client_local_adopted_current_account(
  material : ClientLocalAdoptedHostMaterial[Store, E],
  store : Store,
) -> Result[
  @authorization.AdmittedAccountConfiguration,
  ClientLocalAdoptedCurrentIssue[E],
] {
  if !physical_equal(material.store, store) {
    return Err(ForeignStore)
  }
  let (observed, account, account_original, row, generation) = match
    client_local_observed_current(material.current) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !physical_equal(material.store, observed) {
    return Err(ForeignStore)
  }
  if account_original != material.account_original ||
    row.body != material.adoption.body ||
    row.revision != material.adoption.revision ||
    generation != material.generation ||
    account.configuration_cid() != material.account.configuration_cid() {
    return Err(ChangedCurrent)
  }
  Ok(account)
}

///|
/// Scope from the original adopted/current material; still not an Allow grant.
pub fn[Store, E] client_local_adopted_authority_scope_body(
  material : ClientLocalAdoptedHostMaterial[Store, E],
  store : Store,
  principal : String,
  connection : String,
) -> Result[Bytes, ClientLocalAdoptedCurrentIssue[E]] {
  let account = match client_local_adopted_current_account(material, store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match
    client_local_authority_scope_body(
      account,
      "sha256:" + @sha.hex(material.adoption.body),
      principal,
      connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Scope(issue))
  }
  match client_local_adopted_current_account(material, store) {
    Ok(_) => Ok(body)
    Err(issue) => Err(issue)
  }
}

///|
/// Evaluate the existing Account Owner independently of scope/adoption facts.
pub fn[Store, E] client_local_adopted_account_outcome(
  material : ClientLocalAdoptedHostMaterial[Store, E],
  store : Store,
  tuple : @authorization.AccessTuple,
) -> Result[@authorization.AccountOutcome, ClientLocalAdoptedCurrentIssue[E]] {
  let account = match client_local_adopted_current_account(material, store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let outcome = @authorization.evaluate_account(account, tuple)
  match client_local_adopted_current_account(material, store) {
    Ok(_) => Ok(outcome)
    Err(issue) => Err(issue)
  }
}
