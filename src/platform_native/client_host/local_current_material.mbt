///|
fn local_current_material_issue(
  issue : @host.ClientLocalAdoptedCurrentIssue[NativeLocalAdoptionIssue],
) -> NativeLocalAdoptionIssue {
  match issue {
    @host.Physical(issue) => issue
    @host.CommitUnknown => TransactionUnknown
    @host.Scope(@host.InvalidInput) => InvalidInput
    @host.Scope(@host.Encoding) => Encoding
    @host.NotAdopted
    | @host.InvalidOriginal
    | @host.ForeignStore
    | @host.ChangedCurrent => CustodyLost
  }
}

///|
/// Project the existing physical fence and actual original adoption row.
/// This does not initialize a database or substitute a candidate row for custody.
fn NativeLocalHostConnection::current_adoption_material(
  self : NativeLocalHostConnection,
) -> Result[
  @host.ClientLocalAdoptionCurrentObservation[@sqlite.Database],
  NativeLocalAdoptionIssue,
] {
  self.current_adoption_material_with_reads(() => self.check_binding())
}

///|
fn NativeLocalHostConnection::current_adoption_material_with_reads(
  self : NativeLocalHostConnection,
  current : () -> Result[Unit, NativeLocalAdoptionIssue],
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  @host.ClientLocalAdoptionCurrentObservation[@sqlite.Database],
  NativeLocalAdoptionIssue,
] {
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let row = match
    scan_client_journal_value(self.database, "client_local_adoption", "", reads) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  if row.key != "adoption" ||
    row.revision != 0L ||
    row.body != self.adoption_body {
    return Err(CustodyLost)
  }
  match
    scan_client_journal_value(
      self.database,
      "client_local_adoption",
      "adoption",
      reads,
    ) {
    Err(@sqlite.NotFound) => ()
    Err(issue) => return Err(Physical(issue))
    Ok(_) => return Err(CustodyLost)
  }
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(
    @host.Observed(
      self.database,
      self.session.configuration,
      self.session.source_body,
      { key: row.key, body: row.body, revision: row.revision, },
      (self.ownership.device, self.ownership.inode),
    ),
  )
}

///|
/// Retain the original adopted/current material for the shared portable codec.
/// The current port continues to use this Host's existing lock and all original
/// file/settings/epoch/transaction fences. Close makes the same port unavailable.
pub fn NativeLocalHostConnection::adopted_current_material(
  self : NativeLocalHostConnection,
) -> Result[
  @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
  NativeLocalAdoptionIssue,
] {
  @host.bind_client_local_adopted_host_material(self.database, () => {
    self.current_adoption_material()
  }).map_err(local_current_material_issue)
}
