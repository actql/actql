///|
// Private routing for the already authorized first Journal transaction. The
// actual marker/session still selects initialization; this record cannot issue
// a claim, start a transaction, repair missing originals or change its Database.
priv struct NativeClientJournalBootstrapAccess {
  reads : NativeClientJournalReadAccess
  insert : (String, String, Bytes) -> Result[Unit, @sqlite.NativeSqliteIssue]
  capacity : (String) -> Result[
    @sqlite.NativeCapacityUsage,
    @sqlite.NativeSqliteIssue,
  ]
  install_names : () -> Bool
  install_run_definition_schema : (Int64) -> Result[
    Unit,
    @sqlite.NativeSqliteIssue,
  ]
  install_read_evidence_schema : (Int64) -> Result[
    Unit,
    @sqlite.NativeSqliteIssue,
  ]
}

///|
fn install_bootstrap_run_definition_schema(
  database : @sqlite.Database,
  max_inspect_rows : Int64,
  access : NativeClientJournalBootstrapAccess?,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.install_client_run_definition_schema(max_inspect_rows)
    Some(original) if physical_equal(database, original.reads.database) =>
      (original.install_run_definition_schema)(max_inspect_rows)
    _ => Err(@sqlite.Collision)
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

///|
fn install_bootstrap_read_evidence_schema(
  database : @sqlite.Database,
  max_inspect_rows : Int64,
  access : NativeClientJournalBootstrapAccess?,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.install_client_read_evidence_schema(max_inspect_rows)
    Some(original) if physical_equal(database, original.reads.database) =>
      (original.install_read_evidence_schema)(max_inspect_rows)
    _ => Err(@sqlite.Collision)
  }
}
