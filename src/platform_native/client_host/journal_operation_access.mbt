///|
// Private routing of an already authorized operation on the same Journal.
// This retains the existing transaction and physical Database, not another
// Journal, permission, initialization route or acknowledgement.
priv struct NativeClientJournalOperationAccess {
  reads : NativeClientJournalReadAccess
  insert : (String, String, Bytes) -> Result[Int64, @sqlite.NativeSqliteIssue]
  compare_exchange : (String, String, Int64, Bytes) -> Result[
    Int64,
    @sqlite.NativeSqliteIssue,
  ]
}

///|
fn compare_exchange_client_journal_value(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  revision : Int64,
  body : Bytes,
  access : NativeClientJournalOperationAccess?,
) -> Result[Int64, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.compare_exchange(table_name, key, revision, body)
    Some(original) => {
      if !physical_equal(database, original.reads.database) {
        return Err(@sqlite.Collision)
      }
      (original.compare_exchange)(table_name, key, revision, body)
    }
  }
}

///|
fn insert_client_journal_value(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  body : Bytes,
  access : NativeClientJournalOperationAccess?,
) -> Result[Int64, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.insert(table_name, key, body)
    Some(original) => {
      if !physical_equal(database, original.reads.database) {
        return Err(@sqlite.Collision)
      }
      (original.insert)(table_name, key, body)
    }
  }
}
