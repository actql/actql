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
) -> Result[InstalledArenaCryptoAcquisition, InstalledArenaCryptoIssue] {
  match self.require_local_host_consuming_read_current(pair, read) {
    Err(issue) => return Err(Resources(issue))
    Ok(_) => ()
  }
  if pair.active != Some(HostRead) ||
    !(read.consumer is Some(consumer) && consumer.scope == ConsumerScopeOpen) {
    return Err(
      Resources(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
    )
  }
  let domain = read.domain
  if !(domain.original_read is Some(original) && physical_equal(original, read)) ||
    domain.crypto_component is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.live_channel is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  match
    domain.backing.require_backed_read_context_entered(
      self,
      domain.domain.unwrap(),
      domain,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  let record = register_crypto_component_original(domain)
  let primary = self.load_crypto_component_original(
    record, path, heap_bytes, diagnostic_ceiling,
  )
  record.failed = primary is Some(_)
  match primary {
    Some(issue) => Ok(PendingCrypto(record, issue))
    None => Ok(ReadyCrypto(record))
  }
}
