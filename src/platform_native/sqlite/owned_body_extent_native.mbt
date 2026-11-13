///|
#borrow(database, scope, key, body)
extern "C" fn insert_body_extent_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  body : Bytes,
  body_length : Int,
  body_extent : Int64,
) -> Int = "actql_native_sqlite_database_insert_with_body_extent"

///|
#borrow(database, scope, key, body)
extern "C" fn compare_exchange_body_extent_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  revision : Int64,
  body : Bytes,
  body_length : Int,
  body_extent : Int64,
) -> Int = "actql_native_sqlite_database_compare_exchange_with_body_extent"

///|
#borrow(database, scope, key)
extern "C" fn observe_body_extent_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
) -> Int = "actql_native_sqlite_database_observe_body_extent"

///|
#borrow(database, scope, key)
extern "C" fn read_exact_body_extent_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  revision : Int64,
  body_extent : Int64,
) -> Int = "actql_native_sqlite_database_read_exact_body_extent"

///|
/// The enclosing original Owner has already backed these exact Bytes and
/// SQLite's transient binding. The extent is checked against the actual input;
/// it grants no capacity, changes no default ceiling and acknowledges no COMMIT.
pub fn Database::insert_with_body_extent(
  self : Database,
  scope : String,
  key : String,
  body : Bytes,
  body_extent : Int64,
) -> Result[Int64, NativeSqliteIssue] {
  if body_extent < 0L || body_extent != body.length().to_int64() {
    return Err(InvalidLimit)
  }
  self.with_original_store_sql(false, fn() {
    let scope_bytes = @utf8.encode(scope)
    let key_bytes = @utf8.encode(key)
    if !valid_name(scope_bytes) || !valid_name(key_bytes) {
      return Err(InvalidName)
    }
    let code = insert_body_extent_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
      body,
      body.length(),
      body_extent,
    )
    if code == 0 {
      Ok(database_result_revision_ffi(self))
    } else {
      Err(operation_issue(self, code))
    }
  })
}

///|
/// Same original revision CAS, with one already-backed input extent. This
/// leaves the Database ceiling and every other caller's admission unchanged.
pub fn Database::compare_exchange_with_body_extent(
  self : Database,
  scope : String,
  key : String,
  revision : Int64,
  body : Bytes,
  body_extent : Int64,
) -> Result[Int64, NativeSqliteIssue] {
  if body_extent < 0L || body_extent != body.length().to_int64() {
    return Err(InvalidLimit)
  }
  if revision < 0L {
    return Err(Collision)
  }
  self.with_original_store_sql(true, fn() {
    let scope_bytes = @utf8.encode(scope)
    let key_bytes = @utf8.encode(key)
    if !valid_name(scope_bytes) || !valid_name(key_bytes) {
      return Err(InvalidName)
    }
    let code = compare_exchange_body_extent_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
      revision,
      body,
      body.length(),
      body_extent,
    )
    if code == 0 {
      Ok(database_result_revision_ffi(self))
    } else {
      Err(operation_issue(self, code))
    }
  })
}

///|
/// Revision/length/type metadata only, before any adapter or Moon body copy.
/// This is not custody, permission, a capacity reservation or a snapshot ACK.
pub fn Database::observe_body_extent(
  self : Database,
  scope : String,
  key : String,
) -> Result[NativeJournalHeader, NativeSqliteIssue] {
  self.with_original_store_sql(true, fn() {
    let scope_bytes = @utf8.encode(scope)
    let key_bytes = @utf8.encode(key)
    if !valid_name(scope_bytes) || !valid_name(key_bytes) {
      return Err(InvalidName)
    }
    let code = observe_body_extent_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
    )
    if code == 0 {
      Ok({
        revision: database_result_revision_ffi(self),
        body_bytes: database_result_header_body_bytes_ffi(self),
      })
    } else {
      Err(operation_issue(self, code))
    }
  })
}

///|
/// The same row must still have the observed revision, Blob type and extent
/// before the physical copy. Its caller owns the full same-Read decode overlap
/// and SQLite backing. Metadata alone never creates that resource or authority.
pub fn Database::read_exact_body_extent(
  self : Database,
  scope : String,
  key : String,
  original : NativeJournalHeader,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  if original.revision < 0L ||
    original.body_bytes < 0L ||
    original.body_bytes > 2147483647L {
    return Err(InvalidLimit)
  }
  self.with_original_store_sql(true, fn() {
    let scope_bytes = @utf8.encode(scope)
    let key_bytes = @utf8.encode(key)
    if !valid_name(scope_bytes) || !valid_name(key_bytes) {
      return Err(InvalidName)
    }
    let code = read_exact_body_extent_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
      original.revision,
      original.body_bytes,
    )
    if code == 0 {
      Ok({
        revision: database_result_revision_ffi(self),
        body: database_result_body_ffi(self),
      })
    } else {
      Err(operation_issue(self, code))
    }
  })
}

///|
#borrow(database, scope, after)
extern "C" fn observe_scan_body_extent_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  after : Bytes,
  after_length : Int,
) -> Int = "actql_native_sqlite_database_observe_scan_body_extent"

///|
#borrow(database, scope, after, key)
extern "C" fn scan_exact_body_extent_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  after : Bytes,
  after_length : Int,
  key : Bytes,
  key_length : Int,
  revision : Int64,
  body_extent : Int64,
) -> Int = "actql_native_sqlite_database_scan_exact_body_extent"

///|
/// Observe only the next key and row extent. The bounded key/control copy uses
/// the original Read; this does not copy the body or grant backing for it.
pub fn Database::observe_scan_body_extent(
  self : Database,
  scope : String,
  after_key : String,
) -> Result[(String, NativeJournalHeader), NativeSqliteIssue] {
  self.with_original_store_sql(true, fn() {
    let scope = @utf8.encode(scope)
    let after = @utf8.encode(after_key)
    if !valid_name(scope) || after.length() > 512 {
      return Err(InvalidName)
    }
    let code = observe_scan_body_extent_ffi(
      self,
      scope,
      scope.length(),
      after,
      after.length(),
    )
    if code != 0 {
      return Err(operation_issue(self, code))
    }
    let key = @utf8.decode(database_result_key_ffi(self)) catch {
      _ => return Err(Physical("invalid stored journal key"))
    }
    Ok(
      (
        key,
        {
          revision: database_result_revision_ffi(self),
          body_bytes: database_result_header_body_bytes_ffi(self),
        },
      ),
    )
  })
}

///|
/// Revalidate the ordered first row, not just the previously observed key.
/// The original Read must fund both body copies before this constructor.
pub fn Database::scan_exact_body_extent(
  self : Database,
  scope : String,
  after_key : String,
  expected_key : String,
  original : NativeJournalHeader,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  if original.revision < 0L ||
    original.body_bytes < 0L ||
    original.body_bytes > 2147483647L {
    return Err(InvalidLimit)
  }
  self.with_original_store_sql(true, fn() {
    let scope = @utf8.encode(scope)
    let after = @utf8.encode(after_key)
    let key = @utf8.encode(expected_key)
    if !valid_name(scope) || !valid_name(key) || after.length() > 512 {
      return Err(InvalidName)
    }
    let code = scan_exact_body_extent_ffi(
      self,
      scope,
      scope.length(),
      after,
      after.length(),
      key,
      key.length(),
      original.revision,
      original.body_bytes,
    )
    if code != 0 {
      return Err(operation_issue(self, code))
    }
    let key = @utf8.decode(database_result_key_ffi(self)) catch {
      _ => return Err(Physical("invalid stored journal key"))
    }
    Ok({
      key,
      revision: database_result_revision_ffi(self),
      body: database_result_body_ffi(self),
    })
  })
}
