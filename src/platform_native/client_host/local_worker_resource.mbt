///|
/// A single saved observation of the original live child. Retaining this value
/// keeps the actual selection/domain reachable on every Store failure. The
/// original child Owner, not this record, still owns stop and cleanup.
priv struct NativeLocalWorkerResourceOriginal {
  attempt : NativeLocalWorkerProvisioningAttempt
  domain : @arena.InstalledArenaDomain
  physical : @bootstrap.NativePreparedDomainTransport
  resource : @resources.BackedExecutionOriginalData
  body : Bytes
}

///|
/// Cold DATA only. The saved revision is not current usage, a live loan, a
/// physical ACK or permission to retry the original write or start a worker.
pub(all) enum NativeLocalWorkerResourceObservation {
  UnresolvedNotRecorded(String)
  UnresolvedRecorded(
    String,
    @bootstrap.NativePreparedDomainTransport,
    @resources.UnresolvedBackedExecutionOriginal
  )
}

///|
fn worker_resource_record_key(key : String) -> String {
  "resource/" + key
}

///|
fn worker_physical_fields() -> Array[String] {
  [
    "provisioning", "source", "recipe", "generation", "device", "inode", "capacity",
    "mapping_offset", "mapping_length", "payload_offset", "payload_length", "writable",
    "resource", "version",
  ]
}

///|
fn worker_physical_body(
  provisioning : Bytes,
  physical : @bootstrap.NativePreparedDomainTransport,
  resource : @resources.BackedExecutionOriginalData,
) -> Result[Bytes, NativeLocalWorkerProvisioningIssue] {
  let extent = physical.extent
  if physical.limits != resource.limits ||
    extent.generation <= 0L ||
    extent.device < 0L ||
    extent.inode <= 0L ||
    extent.source.length() != 40 ||
    extent.recipe.length() != 32 ||
    extent.capacity <= 0L ||
    resource.allocation_bytes > extent.capacity ||
    extent.mapping_offset < resource.extent.offset ||
    extent.mapping_offset - resource.extent.offset >
    extent.capacity - resource.allocation_bytes ||
    extent.mapping_offset < 0L ||
    extent.mapping_length <= 0L ||
    extent.mapping_offset > extent.capacity ||
    extent.mapping_length > extent.capacity - extent.mapping_offset ||
    extent.payload_offset != resource.extent.payload_offset ||
    extent.payload_length != resource.extent.payload_length ||
    extent.mapping_length != resource.extent.length ||
    extent.writable != (resource.access == @resources.ExclusiveWrite) {
    return Err(CustodyLost)
  }
  let data = match @host.client_worker_resource_original_body(resource) {
    Err(_) => return Err(CustodyLost)
    Ok(value) => value
  }
  let original = @utf8.decode(provisioning) catch {
    _ => return Err(CustodyLost)
  }
  let data = @utf8.decode(data) catch { _ => return Err(CustodyLost) }
  let body = local_adoption_record([
    ("provisioning", original),
    ("source", extent.source),
    ("recipe", epoch_hex(extent.recipe)),
    ("generation", extent.generation.to_string()),
    ("device", extent.device.to_string()),
    ("inode", extent.inode.to_string()),
    ("capacity", extent.capacity.to_string()),
    ("mapping_offset", extent.mapping_offset.to_string()),
    ("mapping_length", extent.mapping_length.to_string()),
    ("payload_offset", extent.payload_offset.to_string()),
    ("payload_length", extent.payload_length.to_string()),
    ("writable", extent.writable.to_string()),
    ("resource", data),
    ("version", "actql-local-worker-resource/0.1"),
  ]).map_err(issue => NativeLocalWorkerProvisioningIssue::Adoption(issue))
  match body {
    Ok(value) if value.length() <= 4096 => Ok(value)
    Ok(_) => Err(CustodyLost)
    Err(issue) => Err(issue)
  }
}

///|
fn worker_physical_integer(text : String) -> Int64? {
  let value = @string.parse_int64(text) catch { _ => return None }
  if value < 0L || value.to_string() != text {
    None
  } else {
    Some(value)
  }
}

///|
/// Validate the complete original binding and every Resource cross-field law.
/// This reader cannot construct the nominal Resource/Host/child types.
fn read_worker_physical_original(
  original : Bytes,
  body : Bytes,
) -> Result[
  (
    @bootstrap.NativePreparedDomainTransport,
    @resources.UnresolvedBackedExecutionOriginal,
  ),
  NativeLocalWorkerProvisioningIssue,
] {
  if body.length() > 4096 {
    return Err(CustodyLost)
  }
  let values = match local_adoption_fields(body, worker_physical_fields()) {
    Err(_) => return Err(CustodyLost)
    Ok(values) => values
  }
  let original_text = @utf8.decode(original) catch {
    _ => return Err(CustodyLost)
  }
  if values[0] != original_text ||
    values[13] != "actql-local-worker-resource/0.1" {
    return Err(CustodyLost)
  }
  let provision = match
    local_adoption_fields(original, [
      "adoption", "epoch", "key", "source", "recipe", "generation", "version",
    ]) {
    Err(_) => return Err(CustodyLost)
    Ok(value) => value
  }
  if values[1] != provision[3] ||
    values[2] != provision[4] ||
    values[3] != provision[5] {
    return Err(CustodyLost)
  }
  let numbers : Array[Int64] = []
  for i in 3..<11 {
    guard worker_physical_integer(values[i]) is Some(value) else {
      return Err(CustodyLost)
    }
    numbers.push(value)
  }
  let writable = match values[11] {
    "true" => true
    "false" => false
    _ => return Err(CustodyLost)
  }
  guard epoch_hex_bytes(values[2]) is Some(recipe) else {
    return Err(CustodyLost)
  }
  let unresolved = match
    @host.read_client_worker_resource_original(@utf8.encode(values[12])) {
    Err(_) => return Err(CustodyLost)
    Ok(value) => value
  }
  let resource = @resources.unresolved_backed_execution_data(unresolved)
  let physical : @bootstrap.NativePreparedDomainTransport = {
    extent: {
      source: values[1],
      recipe,
      generation: numbers[0],
      device: numbers[1],
      inode: numbers[2],
      capacity: numbers[3],
      mapping_offset: numbers[4],
      mapping_length: numbers[5],
      payload_offset: numbers[6],
      payload_length: numbers[7],
      writable,
    },
    limits: resource.limits,
  }
  match worker_physical_body(original, physical, resource) {
    Ok(expected) if expected == body => Ok((physical, unresolved))
    _ => Err(CustodyLost)
  }
}

///|
fn NativeLocalWorkerProvisioningAttempt::require_worker_resource_current(
  self : NativeLocalWorkerProvisioningAttempt,
  original : NativeLocalWorkerResourceOriginal,
  principal : String,
  connection : String,
) -> Result[Unit, NativeLocalWorkerProvisioningIssue] {
  if !(self.host.worker_provisioning_attempt is Some(attempt) &&
    physical_equal(attempt, self)) ||
    !physical_equal(original.attempt, self) ||
    !(self.resource is Some(retained) && physical_equal(retained, original)) {
    return Err(CustodyLost)
  }
  match
    self.host.worker_provisioning_current(principal, connection, "provision") {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // This helper also runs inside the original journal transaction. Inspect
  // the same admitted rows directly; never nest another journal transaction.
  let saved = match
    self.host.database.read_with_body_limit(
      "client_worker_provisioning",
      self.key,
      2048L,
    ) {
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Adoption(Physical(issue)))
    Ok(value) => value
  }
  let selected = match
    self.host.database.read_with_body_limit(
      "client_worker_provisioning_custody", "selected", 71L,
    ) {
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Adoption(Physical(issue)))
    Ok(value) => value
  }
  if saved.revision != 0L ||
    saved.body != self.body ||
    selected.revision != 1L ||
    selected.body != @utf8.encode(self.key) {
    return Err(CustodyLost)
  }
  match
    self.host.worker_provisioning_current(principal, connection, "provision") {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Reuse the original provisioning codec's current epoch/selection binding;
  // a matching retained row alone cannot make a changed epoch current.
  match self.host.worker_provisioning_body(self.selection, self.key) {
    Ok(body) if body == self.body => ()
    Err(issue) => return Err(issue)
    Ok(_) => return Err(CustodyLost)
  }
  match self.selection.project_domain_original(original.domain) {
    Ok((physical, resource)) if physical == original.physical &&
      resource == original.resource =>
      match worker_physical_body(self.body, physical, resource) {
        Ok(body) if body == original.body => Ok(())
        _ => Err(CustodyLost)
      }
    Err(issue) => Err(PhysicalSelection(issue))
    Ok(_) => Err(CustodyLost)
  }
}

///|
/// One original live write only; no public DATA/Bool admission or retry API.
/// The same carrier is retained BEFORE any Store mutation. An unknown COMMIT
/// keeps it and the child; lookup cannot issue another carrier or write.
pub fn NativeLocalWorkerProvisioningAttempt::record_resource_original(
  self : NativeLocalWorkerProvisioningAttempt,
  domain : @arena.InstalledArenaDomain,
  principal : String,
  connection : String,
) -> Result[Unit, NativeLocalWorkerProvisioningIssue] {
  if self.resource is Some(_) {
    return Err(CustodyLost)
  }
  match self.observe(principal, connection) {
    Ok(UnresolvedOriginal(_, _, Recorded)) => ()
    Err(issue) => return Err(issue)
    _ => return Err(CustodyLost)
  }
  match
    self.host.worker_provisioning_current(principal, connection, "provision") {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (physical, resource) = match
    self.selection.project_domain_original(domain) {
    Err(issue) => return Err(PhysicalSelection(issue))
    Ok(value) => value
  }
  let body = match worker_physical_body(self.body, physical, resource) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The closed decoder independently verifies source/recipe/generation binding.
  match read_worker_physical_original(self.body, body) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let retained : NativeLocalWorkerResourceOriginal = {
    attempt: self,
    domain,
    physical,
    resource,
    body,
  }
  self.resource = Some(retained)
  let result = self.host.journal.transaction(() => {
    match
      self.require_worker_resource_current(retained, principal, connection) {
      Err(issue) => return Err(worker_provisioning_journal_issue(issue))
      Ok(_) => ()
    }
    let key = worker_resource_record_key(self.key)
    match self.host.database.read("client_worker_provisioning", key) {
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
      Ok(_) => return Err(CustodyLost)
    }
    // Existing bounded metadata budget, not physical bootstrap/VM funding.
    // Four bounded raw-byte slots are charged to the existing metadata budget.
    // Decoded/native control and physical allocator overhead are not declared
    // funded by this accounting entry. The existing total/count stay fixed.
    match
      self.host.database.reserve_capacity_in_transaction(
        "client_local_settings", "worker-resource", 16384L, 1L, 65536L, 8L,
      ) {
      Ok(true) => ()
      Ok(false) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
    match self.host.database.insert("client_worker_provisioning", key, body) {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => ()
    }
    self
    .require_worker_resource_current(retained, principal, connection)
    .map_err(worker_provisioning_journal_issue)
  })
  match result {
    Err(issue) => Err(Journal(issue))
    Ok(_) =>
      self.require_worker_resource_current(retained, principal, connection)
  }
}

///|
/// Cold same-Store lookup only. No original domain is reconstructed from rows;
/// NotRecorded is unresolved, never known zero debt or permission to reissue.
pub fn NativeLocalHostConnection::lookup_worker_resource_original(
  self : NativeLocalHostConnection,
  selection : @arena.InstalledArenaWorkerSelection,
  principal : String,
  connection : String,
) -> Result[
  NativeLocalWorkerResourceObservation,
  NativeLocalWorkerProvisioningIssue,
] {
  let (key, original) = match
    self.lookup_worker_provisioning(selection, principal, connection) {
    Ok(UnresolvedOriginal(key, body, Recorded)) => (key, body)
    Err(issue) => return Err(issue)
    _ => return Err(CustodyLost)
  }
  let observed = self.journal
    .transaction(() => {
      match
        self.database.read(
          "client_worker_provisioning",
          worker_resource_record_key(key),
        ) {
        Err(@sqlite.NotFound) => Ok(None)
        Err(issue) => Err(Physical(issue))
        Ok(row) if row.revision == 0L => Ok(Some(row.body))
        Ok(_) => Err(CustodyLost)
      }
    })
    .map_err(issue => NativeLocalWorkerProvisioningIssue::Journal(issue))
  let observation = match observed {
    Err(issue) => return Err(issue)
    Ok(None) => UnresolvedNotRecorded(key)
    Ok(Some(body)) =>
      match read_worker_physical_original(original, body) {
        Err(issue) => return Err(issue)
        Ok((physical, resource)) => UnresolvedRecorded(key, physical, resource)
      }
  }
  match self.lookup_worker_provisioning(selection, principal, connection) {
    Ok(UnresolvedOriginal(final_key, final_body, Recorded)) if final_key == key &&
      final_body == original => Ok(observation)
    Err(issue) => Err(issue)
    _ => Err(CustodyLost)
  }
}
