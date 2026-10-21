///|
// Private routing for the already authorized first Journal transaction. The
// actual marker/session still selects initialization; this record cannot issue
// execution authority, start a transaction, repair originals or change its Database.
priv struct NativeClientJournalBootstrapAccess {
  reads : NativeClientJournalReadAccess
  insert : (String, String, Bytes) -> Result[Unit, @sqlite.NativeSqliteIssue]
  capacity : (String) -> Result[
    @sqlite.NativeCapacityUsage,
    @sqlite.NativeSqliteIssue,
  ]
  install_names : () -> Bool
  claim_append_format : () -> Result[
    @sqlite.NativeOrdinalClaim,
    @sqlite.NativeSqliteIssue,
  ]
}

///|
fn claim_bootstrap_journal_append_format(
  database : @sqlite.Database,
  access : NativeClientJournalBootstrapAccess?,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  let result = match access {
    None =>
      database.claim_ordinal_action_in_transaction(
        "client_journal_format", "append-index", 1L,
      )
    Some(original) if physical_equal(database, original.reads.database) =>
      (original.claim_append_format)()
    _ => Err(@sqlite.Collision)
  }
  match result {
    Ok(@sqlite.Fresh(1L)) => Ok(())
    Ok(_) => Err(CustodyLost)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn bootstrap_journal_reads(
  access : NativeClientJournalBootstrapAccess?,
) -> NativeClientJournalReadAccess? {
  access.map(original => original.reads)
}

///|
fn insert_bootstrap_journal_value(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  body : Bytes,
  access : NativeClientJournalBootstrapAccess?,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.insert(table_name, key, body).map(_ => ())
    Some(original) => {
      if !physical_equal(database, original.reads.database) {
        return Err(@sqlite.Collision)
      }
      (original.insert)(table_name, key, body)
    }
  }
}

///|
fn bootstrap_journal_capacity_usage(
  database : @sqlite.Database,
  table_name : String,
  access : NativeClientJournalBootstrapAccess?,
) -> Result[@sqlite.NativeCapacityUsage, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.capacity_usage(table_name)
    Some(original) => {
      if !physical_equal(database, original.reads.database) {
        return Err(@sqlite.Collision)
      }
      (original.capacity)(table_name)
    }
  }
}

///|
fn install_bootstrap_submission_name_schema(
  database : @sqlite.Database,
  access : NativeClientJournalBootstrapAccess?,
) -> Bool {
  match access {
    None => submission_name_install_ffi(database)
    Some(original) =>
      physical_equal(database, original.reads.database) &&
      (original.install_names)()
  }
}
