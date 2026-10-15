///|
/// Installed physical caller only. First keep the existing DB/session cleanup
/// order and fence, then observe close of the Roots this session itself opened.
/// A borrowed Root with the same path/inode is not one of these descriptors.
///
/// Success acknowledges directory descriptors only. It is NOT retirement of
/// Readers, managed aliases, worker/domain/FD loans or the surrounding funded
/// read context. The installed carrier must retain those original Owners until
/// their separate stop/cleanup and managed-reference retirement are confirmed.
/// Any failure keeps this same Host/session/Root reachable; Root itself owns
/// idempotent close and sticky Unknown, so no raw descriptor retry is added.
pub fn NativeLocalHostConnection::close_owned_root_descriptors(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.close() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.session.settings.managed is Some(managed) {
    match managed.root.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => ()
    }
  }
  // Each open produced its own Root even when source and parent have the same
  // ownership DATA. Do not deduplicate by path, device/inode or serialized CID.
  for root in [self.session.root, self.session.source_root, self.session.parent] {
    match root.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => ()
    }
  }
  Ok(())
}
