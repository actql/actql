///|
pub(all) enum InstalledArenaLocalHostCryptoIssue {
  Resources(InstalledArenaLocalHostResourcesIssue)
  Crypto(InstalledArenaCryptoIssue)
}

///|
/// The original trusted assembly covers this fixed registration in its existing
/// outer control envelope, after the Read claim but before its first entry.
/// It neither loads a component nor supplies another control/domain/profile.
pub fn InstalledArenaHost::prepare_local_host_read_crypto_control(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
) -> Result[InstalledArenaCryptoComponent, InstalledArenaLocalHostCryptoIssue] {
  match self.require_local_host_consuming_read_current(pair, read) {
    Err(issue) => return Err(Resources(issue))
    Ok(_) => ()
  }
  if pair.active is Some(_) ||
    !(read.consumer is Some(consumer) && consumer.scope == ConsumerScopeNew) {
    return Err(
      Resources(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
    )
  }
  let domain = read.domain
  if domain.crypto_component is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.live_channel is Some(_) {
    return Err(Crypto(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed))))
  }
  match
    domain.backing.require_backed_read_context_unentered(
      self,
      domain.domain.unwrap(),
      domain,
    ) {
    Err(issue) => return Err(Crypto(Domain(issue)))
    Ok(_) => ()
  }
  Ok(register_crypto_component_original(domain))
}

///|
/// Trusted assembly only, after the existing complete Read profile has included
/// this component's heap, metadata, diagnostics and all simultaneous aliases.
/// The same pair's one-shot consumer must already own an active HostRead phase.
/// This entry issues no scope, claim, capacity, grant or replacement context.
pub fn InstalledArenaHost::prepare_local_host_read_crypto(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
  command_member? : @filesystem.NativeObservedComponentMember? = None,
) -> Result[InstalledArenaCryptoAcquisition, InstalledArenaLocalHostCryptoIssue] {
  match self.require_local_host_consuming_read_current(pair, read) {
    Err(issue) => return Err(Resources(issue))
    Ok(_) => ()
  }
  guard pair.active == Some(HostRead) &&
    read.consumer is Some(consumer) &&
    consumer.scope == ConsumerScopeOpen else {
    return Err(
      Resources(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
    )
  }
  // Necessary bound only: the complete quote must also include metadata,
  // alignment, diagnostics, retention and all other simultaneous Read users.
  if heap_bytes > consumer.execution_bytes {
    return Err(
      Resources(Read(Read(@resources.Resource(@resources.ExecutionLimit)))),
    )
  }
  let domain = read.domain
  if !(domain.original_read is Some(original) && physical_equal(original, read)) ||
    domain.sqlite_library is Some(_) ||
    domain.live_channel is Some(_) {
    return Err(Crypto(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed))))
  }
  match
    domain.backing.require_backed_read_context_entered(
      self,
      domain.domain.unwrap(),
      domain,
    ) {
    Err(issue) => return Err(Crypto(Domain(issue)))
    Ok(_) => ()
  }
  guard domain.crypto_component is Some(record) else {
    return Err(Crypto(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable))))
  }
  if record.attempted ||
    record.failed ||
    record.closed ||
    record.scope_open ||
    record.component is Some(_) {
    return Err(Crypto(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed))))
  }
  let primary = self.load_crypto_component_original(
    record, path, heap_bytes, diagnostic_ceiling, command_member~,
  )
  record.failed = primary is Some(_)
  match primary {
    Some(issue) => Ok(PendingCrypto(record, issue))
    None => Ok(ReadyCrypto(record))
  }
}
