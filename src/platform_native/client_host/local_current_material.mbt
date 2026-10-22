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
  snapshot_current? : (() -> Result[Unit, NativeLocalAdoptionIssue])? = None,
) -> Result[
  @host.ClientLocalAdoptionCurrentObservation[@sqlite.Database],
  NativeLocalAdoptionIssue,
] {
  native_timing_count(18)
  if snapshot_current is Some(check) {
    match check() {
      Ok(_) => ()
      Err(issue) => {
        self.journal.admitted_adoption = None
        return Err(issue)
      }
    }
    if (self.journal.transaction_active || self.journal.operation_active) &&
      self.journal.admitted_adoption is Some(original) {
      return Ok(original)
    }
  }
  self.journal.admitted_adoption = None
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let row = match
    read_client_journal_value(
      self.database,
      "client_local_adoption",
      "adoption",
      reads,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  if row.revision != 0L || row.body != self.adoption_body {
    return Err(CustodyLost)
  }
  let observation = @host.Observed(
    self.database,
    self.session.configuration,
    self.session.source_body,
    { key: "adoption", body: row.body, revision: row.revision, },
    (self.ownership.device, self.ownership.inode),
  )
  if snapshot_current is Some(_) &&
    (self.journal.transaction_active || self.journal.operation_active) {
    self.journal.admitted_adoption = Some(observation)
  }
  Ok(observation)
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
