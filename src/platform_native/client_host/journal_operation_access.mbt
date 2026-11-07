///|
// Private routing of an already authorized operation on the same Journal.
// This retains the existing transaction and physical Database, not another
// Journal, permission, initialization route or acknowledgement.
priv struct NativeClientJournalOperationAccess {
  reads : NativeClientJournalReadAccess
  before_construction : ((Int, Int, Int) -> Result[
    Unit,
    @host.ClientJournalEncodingIssue,
  ])?
  read_evidence_usage : (String, Int64, Int64) -> Result[
    (Int64, Int64),
    @sqlite.NativeSqliteIssue,
  ]
  install_run_definition_schema : (Int64) -> Result[
    Unit,
    @sqlite.NativeSqliteIssue,
  ]
  install_read_evidence_schema : (Int64) -> Result[
    Unit,
    @sqlite.NativeSqliteIssue,
  ]
  insert : (String, String, Bytes) -> Result[Int64, @sqlite.NativeSqliteIssue]
  compare_exchange : (String, String, Int64, Bytes) -> Result[
    Int64,
    @sqlite.NativeSqliteIssue,
  ]
  remove_exact : (String, String, Int64, Bytes) -> Result[
    Unit,
    @sqlite.NativeSqliteIssue,
  ]
  capacity_usage : (String) -> Result[
    @sqlite.NativeCapacityUsage,
    @sqlite.NativeSqliteIssue,
  ]
  read_capacity : (String, String) -> Result[
    @sqlite.NativeCapacityUsage,
    @sqlite.NativeSqliteIssue,
  ]
  reserve_capacity : (String, String, Int64, Int64, Int64, Int64) -> Result[
    Bool,
    @sqlite.NativeSqliteIssue,
  ]
}

///|
fn install_journal_run_definition_schema(
  database : @sqlite.Database,
  max_inspect_rows : Int64,
  access : NativeClientJournalOperationAccess?,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.install_client_run_definition_schema(max_inspect_rows)
    Some(original) if physical_equal(database, original.reads.database) =>
      (original.install_run_definition_schema)(max_inspect_rows)
    _ => Err(@sqlite.Collision)
  }
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

///|
fn remove_exact_client_journal_value(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  revision : Int64,
  body : Bytes,
  access : NativeClientJournalOperationAccess?,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.remove_exact(table_name, key, revision, body)
    Some(original) => {
      if !physical_equal(database, original.reads.database) {
        return Err(@sqlite.Collision)
      }
      (original.remove_exact)(table_name, key, revision, body)
    }
  }
}

///|
// Read the existing exact reservation through the same physical SQL route.
// Absence cannot create, reserve, release or acknowledge another holding.
fn read_client_journal_capacity(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  access : NativeClientJournalOperationAccess?,
) -> Result[@sqlite.NativeCapacityUsage, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.read_capacity(table_name, key)
    Some(original) if physical_equal(database, original.reads.database) =>
      (original.read_capacity)(table_name, key)
    _ => Err(@sqlite.Collision)
  }
}

///|
fn install_journal_read_evidence_schema(
  database : @sqlite.Database,
  max_inspect_rows : Int64,
  access : NativeClientJournalOperationAccess?,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  match access {
    None => database.install_client_read_evidence_schema(max_inspect_rows)
    Some(original) if physical_equal(database, original.reads.database) =>
      (original.install_read_evidence_schema)(max_inspect_rows)
    _ => Err(@sqlite.Collision)
  }
}

///|
fn read_client_journal_evidence_usage(
  database : @sqlite.Database,
  request_wire : String,
  max_entries : Int64,
  max_bytes : Int64,
  access : NativeClientJournalOperationAccess?,
) -> Result[(Int64, Int64), @sqlite.NativeSqliteIssue] {
  match access {
    None =>
      database.client_read_evidence_usage(request_wire, max_entries, max_bytes)
    Some(original) if physical_equal(database, original.reads.database) =>
      (original.read_evidence_usage)(request_wire, max_entries, max_bytes)
    _ => Err(@sqlite.Collision)
  }
}

///|
// The same entered Read pays every emission of its original submitted row,
// including admission and saved-state CAS. Without an operation, keep the
// legacy finite codec; a foreign Database cannot lend this reservation.
fn submitted_encode_construction(
  database : @sqlite.Database,
  access : NativeClientJournalOperationAccess?,
) -> ((Int, Int, Int) -> Result[Unit, @host.ClientJournalEncodingIssue])? {
  access.bind(original => {
    if physical_equal(database, original.reads.database) {
      original.before_construction
    } else {
      Some((_, _, _) => Err(@host.ClientJournalEncodingIssue::Encoding))
    }
  })
}
