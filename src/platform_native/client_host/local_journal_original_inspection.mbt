///|
// Keep the bounded snapshot in the original capture before any scope leave can
// fail. Its DB and scratch retire through their own actual acknowledgements.
fn NativeLocalJournalCapture::inspect_original_retained_journal(
  self : NativeLocalJournalCapture,
  original : NativeLocalJournalOriginalResources,
  library : @sqlite.Library,
) -> Result[Bool, NativeLocalAdoptionIssue] {
  let inspection = match
    original.stage(@arena.HostRead, fn() {
      match
        (if self.command_preparation_journal {
          @journal.prepare_sqlite_journal_source_inspection(
            self.session.state_path + "/client.sqlite3",
            131072L,
            self.max_snapshot_bytes,
          )
        } else {
          @journal.prepare_sqlite_source_inspection(
            self.session.state_path + "/client.sqlite3",
            131072L,
            self.max_snapshot_bytes,
          )
        }) {
        Err(issue) => Err(Inspection(Inspection(issue, None)))
        Ok(value) => {
          self.opening_inspection = Some(value)
          Ok(value)
        }
      }
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let copied = match
    original.stage(@arena.HostSqlite, fn() {
      inspection
      .open_database(library)
      .map_err(issue => Inspection(Inspection(issue, None)))
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let audit = match copied {
    None => Ok(PhysicallyAbsent)
    Some(database) =>
      original.audit_read_stage(database, reads => {
        inspect_native_client_control_rows(
          database,
          self.max_records,
          reads=Some(reads),
        ).map_err(issue => Inspection(Custody(issue)))
      })
  }
  if original.interrupted {
    return Err(
      match audit {
        Err(issue) => issue
        Ok(_) => OriginalResourceScopePending
      },
    )
  }
  // Preserve the original post-audit source check even on a semantic refusal.
  let refusal = match audit {
    Err(Inspection(Custody(issue))) => Some(issue)
    _ => None
  }
  match
    original.stage(@arena.HostRead, fn() {
      inspection
      .validate_source()
      .map_err(issue => Inspection(Inspection(issue, refusal)))
    }) {
    Err(issue) =>
      return Err(
        InspectionPending(
          match audit {
            Err(primary) => Some(primary)
            Ok(_) => None
          },
          issue,
          inspection,
        ),
      )
    Ok(_) => ()
  }
  match
    original.stage(@arena.HostSqlite, fn() {
      inspection.close_database().map_err(issue => InspectionCleanup(issue))
    }) {
    Err(issue) =>
      return Err(
        InspectionPending(
          match audit {
            Err(primary) => Some(primary)
            Ok(_) => None
          },
          issue,
          inspection,
        ),
      )
    Ok(_) => ()
  }
  match
    original.stage(@arena.HostRead, fn() {
      inspection.close_snapshot().map_err(issue => InspectionCleanup(issue))
    }) {
    Err(issue) =>
      return Err(
        InspectionPending(
          match audit {
            Err(primary) => Some(primary)
            Ok(_) => None
          },
          issue,
          inspection,
        ),
      )
    Ok(_) => ()
  }
  self.opening_inspection = None
  match audit {
    Ok(Retained) => Ok(false)
    Ok(PhysicallyAbsent) => Err(CustodyLost)
    Err(issue) => Err(issue)
  }
}
