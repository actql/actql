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
