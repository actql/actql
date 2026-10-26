///|
// Private physical ports borrow the SAME opaque SQLite holder. No raw pointer,
// JSON database identity, permission or independent SQLite library is issued.
#borrow(database)
extern "C" fn submission_name_install_ffi(database : @sqlite.Database) -> Bool = "actql_native_client_submission_name_install"

///|
#borrow(database)
extern "C" fn submission_name_schema_ffi(database : @sqlite.Database) -> Int = "actql_native_client_submission_name_schema"

///|
#borrow(database)
extern "C" fn submission_name_census_ffi(database : @sqlite.Database) -> Int64 = "actql_native_client_submission_name_census"

///|
// A retained count belongs to the original INSERT/DELETE triggers. Issuance is
// still the Native Journal's same-transaction monotonic CAS. Never reset either.
fn NativeClientRunJournal::submitted_name_control(
  self : NativeClientRunJournal,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  let issued = match
    read_client_journal_value(
      self.database,
      "client_submission_name_custody",
      "issued",
      reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(NamedSubmission(OriginalUnavailable))
    Err(issue) => return Err(Physical(issue))
  }
  if read_client_submission_name_schema(self.database, reads) != 1 {
    return Err(CustodyLost)
  }
  let retained = match
    read_client_journal_value(
      self.database,
      "client_submission_name_custody",
      "retained",
      reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let count = match
    @host.client_journal_issuance_count(issued.body, self.max_records) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  match @host.client_journal_issuance_count(retained.body, self.max_records) {
    Ok(value) if value == count => ()
    _ => return Err(CustodyLost)
  }
  Ok((count, issued.revision))
}

///|
// Opening an existing installation checks fixed name-extension control only.
// An individual lookup authenticates its selected name and original binding.
fn NativeClientRunJournal::inspect_submitted_name_control(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !physical_equal(self.database, authority.database) {
    return Err(InvalidSubmission)
  }
  match
    read_client_journal_value(
      self.database,
      "client_submission_name_custody",
      "issued",
      reads,
    ) {
    Ok(_) => self.submitted_name_control(reads~).map(_ => ())
    Err(@sqlite.NotFound) =>
      if read_client_submission_name_schema(self.database, reads) == 0 {
        Ok(())
      } else {
        Err(CustodyLost)
      }
    Err(issue) => Err(Physical(issue))
  }
}
