///|
/// Trusted selected-runtime assembly after independent process/control funding.
/// Only this original region's captured descriptor reaches the existing Holder;
/// the Holder owns its duplicate and immutable argv/env snapshot. Paths, numbers
/// and successful preparation are not installation, funding or launch grants.
pub fn InstalledArenaHost::prepare_process_child(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
  executable : String,
  arguments : Array[String],
  environment : Array[(String, String)],
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  let descriptor = match self.process_backing_descriptor(domain, process) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard process.holder is Some(holder) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  holder.prepare_duplex_child(executable, arguments, descriptor, environment)
  .map_err(issue => @bootstrap.Process(issue))
}

///|
/// One attempt by the same original process Owner, never a replacement child.
/// Any refused spawn/close or post-spawn binding leaves the original Holder,
/// child, region and frame in this carrier. No error proves non-execution or
/// acknowledges cleanup; the caller uses the existing typed stop/cleanup path.
pub fn InstalledArenaHost::spawn_prepared_process_child(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.require_process_current(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard process.holder is Some(holder) && process.region is Some(region) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  match holder.spawn_prepared_duplex() {
    Err(issue) => return Err(@bootstrap.Process(issue))
    Ok(_) => ()
  }
  domain.backing.bind_process_channel_child(self, region)
}
