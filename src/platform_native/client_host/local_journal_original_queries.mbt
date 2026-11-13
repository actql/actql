///|
// Private routing state, not another physical Owner. The same original pair
// and DB remain with the capture/failure. Remember the first scope failure so
// a conservative internal SQL refusal cannot replace its actual cause.
priv struct NativeLocalJournalReadQueries {
  original : NativeLocalJournalOriginalResources
  database : @sqlite.Database
  mut failure : NativeLocalAdoptionIssue?
  invalidate_snapshot : (String?) -> Unit
}

///|
fn[T] NativeLocalJournalOriginalResources::query_while_read(
  self : NativeLocalJournalOriginalResources,
  query : () -> T,
) -> Result[T, NativeLocalAdoptionIssue] {
  if self.interrupted || !(self.active_phase is Some(@arena.HostRead)) {
    return Err(OriginalResourceScopePending)
  }
  // Leave only the actual original Read scope; its material aliases and loan
  // remain retained. A missing leave ACK cannot authorize another entry.
  match self.host.leave_local_host_phase(self.pair) {
    Err(issue) => {
      self.interrupted = true
      return Err(OriginalResourceLeave(None, issue))
    }
    Ok(_) => self.active_phase = None
  }
  let value = match self.stage(@arena.HostSqlite, fn() { Ok(query()) }) {
    Ok(value) => value
    Err(issue) => {
      self.interrupted = true
      return Err(issue)
    }
  }
  match
    self.host.require_local_host_consuming_read_current(self.pair, self.read) {
    Err(issue) => {
      self.interrupted = true
      return Err(OriginalResources(issue))
    }
    Ok(_) => ()
  }
  match self.host.enter_local_host_phase(self.pair, @arena.HostRead) {
    Err(issue) => {
      self.interrupted = true
      Err(OriginalResources(issue))
    }
    Ok(_) => {
      self.active_phase = Some(@arena.HostRead)
      Ok(value)
    }
  }
}

///|
#borrow(database, receiver)
extern "C" fn journal_database_matches_store_receiver_ffi(
  database : @sqlite.Database,
  receiver : NativeLocalStoreOperationReceiver,
) -> Bool = "actql_native_sqlite_database_matches_store_receiver"

///|
fn[T] NativeLocalJournalReadQueries::query(
  self : NativeLocalJournalReadQueries,
  query : () -> T,
) -> Result[T, @sqlite.NativeSqliteIssue] {
  if self.failure is Some(_) {
    return Err(@sqlite.Busy)
  }
  if self.original.store_operation is Some(receiver) &&
    receiver.phase == StoreRouteRead &&
    journal_database_matches_store_receiver_ffi(self.database, receiver) {
    // The SAME bound Database brackets every SQL call below. Applying the
    // unbound manual exchange as well would enter the original pair twice.
    return Ok(query())
  }
  match self.original.query_while_read(query) {
    Ok(value) => Ok(value)
    Err(issue) => {
      self.failure = Some(issue)
      // The private audit immediately returns its recorded original scope
      // issue. This internal refusal never becomes a public replacement cause.
      Err(@sqlite.Busy)
    }
  }
}

///|
fn NativeLocalJournalReadQueries::access(
  self : NativeLocalJournalReadQueries,
) -> NativeClientJournalReadAccess {
  {
    database: self.database,
    before_submitted_decode: Some(stage => self.prepare_submitted_decode(stage)),
    before_run_decode: Some(stage => self.prepare_run_decode(stage)),
    before_metadata_construction: Some((r, e, raw) => {
      self.prepare_metadata_construction(r, e, raw)
    }),
    read_evidence_schema: () => {
      self
      .query(() => self.database.client_read_evidence_schema())
      .unwrap_or(Err(@sqlite.Busy))
    },
    run_definition_schema: () => {
      self
      .query(() => self.database.client_run_definition_schema())
      .unwrap_or(Err(@sqlite.Busy))
    },
    run_definition_key: definition_cid => {
      self
      .query(() => self.database.client_run_definition_key(definition_cid))
      .unwrap_or(Err(@sqlite.Busy))
    },
    fenced: () => {
      self.query(() => self.database.transaction_fenced()).unwrap_or(true)
    },
    fence: () => {
      (self.invalidate_snapshot)(None)
      self.query(() => self.database.fence_transactions()) |> ignore
    },
    read: (table_name, key) => {
      if table_name == "client_submitted_intents" || table_name == "client_runs" {
        let header = match
          self.query(() => self.database.observe_body_extent(table_name, key)) {
          Ok(Ok(value)) => value
          Ok(Err(issue)) | Err(issue) => return Err(issue)
        }
        if self.prepare_submitted_copy(header.body_bytes) is Err(_) {
          return Err(@sqlite.Busy)
        }
        return self
          .query(() => {
            self.database.read_exact_body_extent(table_name, key, header)
          })
          .unwrap_or(Err(@sqlite.Busy))
      }
      match self.query(() => self.database.read(table_name, key)) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    scan: (table_name, cursor) => {
      if table_name == "client_submitted_intents" || table_name == "client_runs" {
        let (key, header) = match
          self.query(() => {
            self.database.observe_scan_body_extent(table_name, cursor)
          }) {
          Ok(Ok(value)) => value
          Ok(Err(issue)) | Err(issue) => return Err(issue)
        }
        if self.prepare_submitted_copy(header.body_bytes) is Err(_) {
          return Err(@sqlite.Busy)
        }
        return self
          .query(() => {
            self.database.scan_exact_body_extent(
              table_name, cursor, key, header,
            )
          })
          .unwrap_or(Err(@sqlite.Busy))
      }
      match self.query(() => self.database.scan_after(table_name, cursor)) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    schema: () => {
      self.query(() => submission_name_schema_ffi(self.database)).unwrap_or(-1)
    },
    _observed_census: () => {
      self.query(() => submission_name_census_ffi(self.database)).unwrap_or(-1L)
    },
    transaction: operation => {
      match
        self.query(() => {
          match operation {
            JournalBegin => self.database.begin_immediate()
            JournalCommit => self.database.commit()
            JournalRollback => self.database.rollback()
          }
        }) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
  }
}

///|
fn[T] NativeLocalJournalOriginalResources::audit_read_stage(
  self : NativeLocalJournalOriginalResources,
  database : @sqlite.Database,
  audit : (NativeClientJournalReadAccess) -> Result[T, NativeLocalAdoptionIssue],
) -> Result[T, NativeLocalAdoptionIssue] {
  self.stage(@arena.HostRead, fn() {
    let queries : NativeLocalJournalReadQueries = {
      original: self,
      database,
      failure: None,
      invalidate_snapshot: _ => (),
    }
    let result = audit(queries.access())
    match (queries.failure, result) {
      (Some(original), Err(Journal(TransactionUnknown))) =>
        Err(InstallationReadTransactionFailure(original, TransactionUnknown))
      (Some(original), _) => Err(original)
      (None, value) => value
    }
  })
}

///|
// Only the original trusted initializer receives this private routing view.
// Each physical SQL call leaves and reenters the same retained Read, just like
// the startup audit. A failed exchange remains with the original capture.
fn NativeLocalJournalReadQueries::bootstrap_access(
  self : NativeLocalJournalReadQueries,
) -> NativeClientJournalBootstrapAccess {
  {
    reads: self.access(),
    install_read_evidence_schema: max_rows => {
      (self.invalidate_snapshot)(Some("client_local_read_evidence"))
      self
      .query(() => self.database.install_client_read_evidence_schema(max_rows))
      .unwrap_or(Err(@sqlite.Busy))
    },
    install_run_definition_schema: max_rows => {
      self
      .query(() => self.database.install_client_run_definition_schema(max_rows))
      .unwrap_or(Err(@sqlite.Busy))
    },
    insert: (table_name, key, body) => {
      (self.invalidate_snapshot)(Some(table_name))
      match self.query(() => self.database.insert(table_name, key, body)) {
        Ok(value) => value.map(_ => ())
        Err(issue) => Err(issue)
      }
    },
    capacity: table_name => {
      match self.query(() => self.database.capacity_usage(table_name)) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    install_names: () => {
      self
      .query(() => submission_name_install_ffi(self.database))
      .unwrap_or(false)
    },
  }
}

///|
// The first marker is admitted by the original Session before this private
// route is selected. Keep the original transaction/rollback and Unknown fence;
// a failed phase exchange never replays initialization or confirms a COMMIT.
fn[T] NativeLocalJournalOriginalResources::bootstrap_read_stage(
  self : NativeLocalJournalOriginalResources,
  database : @sqlite.Database,
  initialize : (NativeClientJournalBootstrapAccess) -> Result[
    T,
    NativeLocalAdoptionIssue,
  ],
) -> Result[T, NativeLocalAdoptionIssue] {
  self.stage(@arena.HostRead, fn() {
    let queries : NativeLocalJournalReadQueries = {
      original: self,
      database,
      failure: None,
      invalidate_snapshot: _ => (),
    }
    let result = initialize(queries.bootstrap_access())
    match (queries.failure, result) {
      (Some(original), Err(TransactionUnknown)) =>
        Err(InstallationReadTransactionFailure(original, TransactionUnknown))
      (Some(original), Err(Journal(TransactionUnknown))) =>
        Err(InstallationReadTransactionFailure(original, TransactionUnknown))
      (Some(original), _) => Err(original)
      (None, value) => value
    }
  })
}

///|
fn NativeLocalJournalReadQueries::operation_access(
  self : NativeLocalJournalReadQueries,
) -> NativeClientJournalOperationAccess {
  {
    reads: self.access(),
    before_construction: Some((bytes, nodes, depth) => {
      self.prepare_row_construction(bytes, nodes, depth)
    }),
    install_read_evidence_schema: max_rows => {
      (self.invalidate_snapshot)(Some("client_local_read_evidence"))
      self
      .query(() => self.database.install_client_read_evidence_schema(max_rows))
      .unwrap_or(Err(@sqlite.Busy))
    },
    install_run_definition_schema: max_rows => {
      self
      .query(() => self.database.install_client_run_definition_schema(max_rows))
      .unwrap_or(Err(@sqlite.Busy))
    },
    capacity_usage: table => {
      match self.query(() => self.database.capacity_usage(table)) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    read_evidence_usage: (wire, max_rows, max_bytes) => {
      self
      .query(() => {
        self.database.client_read_evidence_usage(wire, max_rows, max_bytes)
      })
      .unwrap_or(Err(@sqlite.Busy))
    },
    read_capacity: (table, key) => {
      match self.query(() => self.database.read_capacity(table, key)) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    reserve_capacity: (table, key, bytes, objects, max_bytes, max_objects) => {
      (self.invalidate_snapshot)(Some(table))
      match
        self.query(() => {
          self.database.reserve_capacity_in_transaction(
            table, key, bytes, objects, max_bytes, max_objects,
          )
        }) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    grow_capacity: (
      table,
      key,
      previous,
      bytes,
      objects,
      max_bytes,
      max_objects,
    ) => {
      (self.invalidate_snapshot)(Some(table))
      self
      .query(() => {
        grow_journal_capacity_in_transaction(
          self.database,
          table,
          key,
          previous,
          bytes,
          objects,
          max_bytes,
          max_objects,
        )
      })
      .unwrap_or(Err(@sqlite.Busy))
    },
    insert: (table, key, body) => {
      (self.invalidate_snapshot)(Some(table))
      match
        self.query(() => {
          if table == "client_submitted_intents" || table == "client_runs" {
            self.database.insert_with_body_extent(
              table,
              key,
              body,
              body.length().to_int64(),
            )
          } else {
            self.database.insert(table, key, body)
          }
        }) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    remove_exact: (table, key, revision, body) => {
      (self.invalidate_snapshot)(Some(table))
      match
        self.query(() => self.database.remove_exact(table, key, revision, body)) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
    compare_exchange: (table, key, revision, body) => {
      (self.invalidate_snapshot)(Some(table))
      match
        self.query(() => {
          if table == "client_submitted_intents" || table == "client_runs" {
            self.database.compare_exchange_with_body_extent(
              table,
              key,
              revision,
              body,
              body.length().to_int64(),
            )
          } else {
            self.database.compare_exchange(table, key, revision, body)
          }
        }) {
        Ok(value) => value
        Err(issue) => Err(issue)
      }
    },
  }
}
