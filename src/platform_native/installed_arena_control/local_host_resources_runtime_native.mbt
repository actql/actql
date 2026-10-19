///|
/// Match an existing Runtime's original Read to this same Host pair and its
/// already issued consumer. This neither issues nor borrows another read.
pub fn InstalledArenaHost::require_local_host_consuming_read_current(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
) -> Result[Unit, InstalledArenaLocalHostResourcesIssue] {
  match self.original_local_host_resources(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(record.read, read) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  if record.read.consumer is None {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  self.require_local_host_resources_current(record)
}

///|
pub(all) enum InstalledArenaLocalHostReadScope {
  ReadUnentered
  ReadEntered
}

///|
/// Observe only this pair's original consuming Read. An entered observation
/// requires the actual backing's current C frame as well as its nominal
/// consumer state. It issues no scope and transfers no leave responsibility.
pub fn InstalledArenaHost::observe_local_host_consuming_read_scope(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
) -> Result[
  InstalledArenaLocalHostReadScope,
  InstalledArenaLocalHostResourcesIssue,
] {
  match self.require_local_host_consuming_read_current(record, read) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match record.active {
    None =>
      if read.consumer is Some(consumer) &&
        (
          consumer.scope == ConsumerScopeNew ||
          consumer.scope == ConsumerScopeLeft
        ) {
        Ok(ReadUnentered)
      } else {
        Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
      }
    Some(HostSqlite) =>
      Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
    Some(HostRead) => {
      guard read.consumer is Some(consumer) &&
        consumer.scope == ConsumerScopeOpen else {
        return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
      }
      match
        read.domain.backing.require_backed_read_context_entered(
          self,
          read.domain.domain.unwrap(),
          read.domain,
        ) {
        Err(issue) => Err(Domain(issue))
        Ok(_) => Ok(ReadEntered)
      }
    }
  }
}
