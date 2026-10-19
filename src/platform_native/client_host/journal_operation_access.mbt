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
  capacity_usage : (String) -> Result[
    @sqlite.NativeCapacityUsage,
    @sqlite.NativeSqliteIssue,
  ]
  reserve_capacity : (String, String, Int64, Int64, Int64, Int64) -> Result[
    Bool,
    @sqlite.NativeSqliteIssue,
  ]
}

///|
fn client_journal_capacity_usage(
  database : @sqlite.Database,
  table_name : String,
  access : NativeClientJournalOperationAccess?,
) -> Result[@sqlite.NativeCapacityUsage, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.capacity_usage(table_name)
    Some(original) => {
      if !physical_equal(database, original.reads.database) {
        return Err(@sqlite.Collision)
      }
      (original.capacity_usage)(table_name)
    }
  }
}

///|
// This performs only the existing same-transaction metadata reservation.
// Bounds and reservation rows do not issue physical backing or permission.
fn reserve_client_journal_capacity(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  bytes : Int64,
  objects : Int64,
  max_bytes : Int64,
  max_objects : Int64,
  access : NativeClientJournalOperationAccess?,
) -> Result[Bool, @sqlite.NativeSqliteIssue] {
  match access {
    None =>
      database.reserve_capacity_in_transaction(
        table_name, key, bytes, objects, max_bytes, max_objects,
      )
    Some(original) => {
      if !physical_equal(database, original.reads.database) {
        return Err(@sqlite.Collision)
      }
      (original.reserve_capacity)(
        table_name, key, bytes, objects, max_bytes, max_objects,
      )
    }
  }
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
