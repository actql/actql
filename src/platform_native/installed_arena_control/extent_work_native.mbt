///|
/// Read cumulative work through this Host's already-entered original backing
/// loan. The fixed DATA copy neither allocates an extent nor retires a parent.
pub fn InstalledArenaHost::observe_backing_extent_work(
  self : InstalledArenaHost,
  borrow : InstalledArenaBackingBorrow,
) -> Result[@bootstrap.NativeExtentWork, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(borrow.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(backing) => backing
  }
  backing.observe_extent_work(self, borrow.original)
}
