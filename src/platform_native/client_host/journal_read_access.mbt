///|
// Private call routing inside the original Journal Owner. Each callback uses
// the same Database and its actual scope; these functions issue no authority,
// capacity, new transaction or original row. Legacy callers keep direct reads.
priv struct NativeClientJournalReadAccess {
  database : @sqlite.Database
  schema : () -> Int
  census : () -> Int64
  transaction : (NativeClientJournalTransactionOperation) -> Result[Unit, @sqlite.NativeSqliteIssue]
  read : (String, String) -> Result[@sqlite.NativeJournalValue, @sqlite.NativeSqliteIssue]
  scan : (String, String) -> Result[@sqlite.NativeJournalEntry, @sqlite.NativeSqliteIssue]
}

///|
fn read_client_journal_value(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  reads : NativeClientJournalReadAccess?,
) -> Result[@sqlite.NativeJournalValue, @sqlite.NativeSqliteIssue] {
  match reads {
    None => database.read(table_name, key)
    Some(original) => {
      if !physical_equal(database, original.database) {
        return Err(@sqlite.Collision)
      }
      (original.read)(table_name, key)
    }
  }
}

///|
fn scan_client_journal_value(
  database : @sqlite.Database,
  table_name : String,
  cursor : String,
  reads : NativeClientJournalReadAccess?,
) -> Result[@sqlite.NativeJournalEntry, @sqlite.NativeSqliteIssue] {
  match reads {
    None => database.scan_after(table_name, cursor)
    Some(original) => {
      if !physical_equal(database, original.database) {
        return Err(@sqlite.Collision)
      }
      (original.scan)(table_name, cursor)
    }
  }
}

///|
priv enum NativeClientJournalTransactionOperation {
  JournalBegin
  JournalCommit
  JournalRollback
}

///|
fn read_client_submission_name_schema(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Int {
  match reads {
    None => submission_name_schema_ffi(database)
    Some(original) =>
      if physical_equal(database, original.database) {
        (original.schema)()
      } else {
        -1
      }
  }
}

///|
fn read_client_submission_name_census(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Int64 {
  match reads {
    None => submission_name_census_ffi(database)
    Some(original) =>
      if physical_equal(database, original.database) {
        (original.census)()
      } else {
        -1L
      }
  }
}

///|
fn client_journal_transaction_operation(
  database : @sqlite.Database,
  operation : NativeClientJournalTransactionOperation,
  reads : NativeClientJournalReadAccess?,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  match reads {
    Some(original) => {
      if !physical_equal(database, original.database) {
        return Err(@sqlite.Collision)
      }
      (original.transaction)(operation)
    }
    None =>
      match operation {
        JournalBegin => database.begin_immediate()
        JournalCommit => database.commit()
        JournalRollback => database.rollback()
      }
  }
}
