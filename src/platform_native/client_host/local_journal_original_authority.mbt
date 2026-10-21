///|
// Only the current captured Read may invoke this observation. The same
// physical Journal queries leave/reenter that Read around every SQLite call;
// snapshot facts may be reused only while the same original remains live.
// No candidate row, cached Allow or physical ACK replaces that original.
fn[T] NativeLocalJournalCapture::with_current_adoption_material_in_original_read(
  self : NativeLocalJournalCapture,
  operation : (
    NativeLocalHostConnection,
    @host.ClientLocalAdoptedHostMaterial[
      @sqlite.Database,
      NativeLocalAdoptionIssue,
    ],
    NativeClientJournalOperationAccess,
  ) -> Result[T, NativeLocalAdoptionIssue],
) -> Result[T, NativeLocalAdoptionIssue] {
  if self.closing || self.read_operation_issue is Some(_) {
    return Err(
      self.read_operation_issue.unwrap_or(OriginalResourceScopePending),
    )
  }
  guard self.opening is JournalAcquired(host) &&
    self.original_resources is Some(original) &&
    !original.interrupted &&
    original.active_phase is Some(@arena.HostRead) else {
    return Err(OriginalResourceScopePending)
  }
  if self.read_callback_active && !self.read_facts_valid {
    return Err(OriginalResourceScopePending)
  }
  // The public command entry admitted current originals. Retain that material
  // throughout this operation; a trusted query or phase exchange is not an
  // additional Account/configuration admission boundary.
  let queries : NativeLocalJournalReadQueries = {
    original,
    database: host.database,
    failure: None,
    invalidate_snapshot: table => {
      if table is None ||
        table
        is Some(
          "client_local_adoption"
          | "client_local_settings"
          | "client_local_installation_originals"
          | "client_local_installation_custody"
        ) {
        self.read_facts_valid = false
        self.clear_read_operation_facts()
        host.journal.admitted_adoption = None
      }
      if table is None || table is Some("client_runs" | "client_effect_custody") {
        host.journal.invalidate_operation_record()
      }
    },
  }
  let admitted = if self.read_callback_active &&
    self.read_facts_valid &&
    self.read_material is Some(material) {
    self.check_original_read_lifetime().map(_ => material)
  } else {
    native_timing_count(33)
    @host.bind_client_local_adopted_host_material(host.database, () => {
      host.current_adoption_material_with_reads(
        () => self.check_current_in_original_read(),
        reads=Some(queries.access()),
        snapshot_current=Some(() => {
          if self.read_callback_active && !self.read_facts_valid {
            Err(OriginalResourceScopePending)
          } else {
            self.check_original_read_lifetime()
          }
        }),
      )
    }).map_err(local_current_material_issue)
  }
  let result = match admitted {
    Err(issue) => Err(issue)
    Ok(material) => {
      if self.read_callback_active && self.read_facts_valid {
        self.read_material = Some(material)
      }
      operation(host, material, queries.operation_access())
    }
  }
  if queries.failure is Some(_) || self.read_operation_issue is Some(_) {
    self.read_facts_valid = false
    self.clear_read_operation_facts()
  }
  match (queries.failure, self.read_operation_issue, result) {
    (
      Some(issue),
      _,
      Err(
        Epoch(TransactionUnknown)
        | Journal(TransactionUnknown)
        | Journal(Epoch(TransactionUnknown))
      ),
    ) => {
      self.read_operation_issue = Some(issue)
      Err(InstallationReadTransactionFailure(issue, TransactionUnknown))
    }
    (Some(issue), _, _) => {
      self.read_operation_issue = Some(issue)
      Err(issue)
    }
    (None, Some(issue), _) => Err(issue)
    (None, None, result) => result
  }
}

///|
/// The same adopted configuration/caller scope under the original Read. This
/// observes identity only; it issues no Submission, execution supply or grant.
pub fn NativeLocalJournalCapture::authority_scope_cid_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
) -> Result[String, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    _operations,
  ) => self.operation_scope(host, material, principal, connection))
}

///|
/// Repeat the existing Account Owner decision against current original
/// adoption material. Neither a scope CID nor this observation funds work.
pub fn NativeLocalJournalCapture::authorize_in_original_read(
  self : NativeLocalJournalCapture,
  request : @authorization.AccessTuple,
) -> Result[@authorization.AccountOutcome, NativeLocalAdoptionIssue] {
  native_timing_count(23)
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    _operations,
  ) => self.operation_account(host, material, request))
}

///|
/// Issue through the existing epoch Owner only under this capture's same
/// current Read/SQL exchange. The original Account is consulted here, never a
/// caller Boolean. The command must separately acquire its complete business
/// supplier before invoking this durable clock operation.
pub fn NativeLocalJournalCapture::issue_epoch_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  now : Double,
) -> Result[NativeClientSubmissionEpoch, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let allowed = match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    host.epoch
    .issue_epoch_with_operations(
      expected_scope,
      allowed,
      now,
      operations=Some(operations),
    )
    .map_err(issue => Epoch(issue))
  })
}

///|
fn NativeLocalJournalCapture::original_submit_allowed(
  self : NativeLocalJournalCapture,
  host : NativeLocalHostConnection,
  material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
  principal : String,
  connection : String,
  expected_scope : String,
) -> Result[Bool, NativeLocalAdoptionIssue] {
  // These immutable originals determine identity, never Allow. The material
  // was joined to this Host immediately before this closed operation. Account
  // evaluation below still observes that same material before and after its
  // actual decision, including after the digest and before protected SQL.
  let current_scope = match
    self.operation_scope(host, material, principal, connection) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if current_scope != expected_scope {
    return Err(Epoch(ScopeMismatch))
  }
  match
    self.operation_account(host, material, {
      principal,
      connection,
      resource: "run",
      operation: "submit",
    }) {
    Ok(Allow(_)) => Ok(true)
    Ok(_) => Ok(false)
    Err(issue) => Err(issue)
  }
}

///|
/// Save the exact retained intent through the original Journal transaction.
/// This neither supplies execution nor replaces an uncertain prior admission.
pub fn NativeLocalJournalCapture::record_submitted_intent_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  reference : NativeClientSubmissionReference,
  intent : @host.ClientSubmittedIntent,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let allowed = match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    host.journal
    .record_submitted_intent_with_operations(
      host.epoch,
      reference,
      intent,
      expected_scope,
      allowed,
      now,
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
/// Borrow the already opened original handles only under this captured Read.
/// Their presence grants no permission and does not select unscoped SQL.
pub fn NativeLocalJournalCapture::submission_originals_in_original_read(
  self : NativeLocalJournalCapture,
) -> Result[
  (NativeClientRunJournal, NativeClientEpochAuthority),
  NativeLocalAdoptionIssue,
] {
  match self.check_current_in_original_read() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.opening is JournalAcquired(host) &&
    self.original_resources is Some(_) else {
    return Err(OriginalResourceScopePending)
  }
  if !physical_equal(host.database, host.journal.database) ||
    !physical_equal(host.database, host.epoch.database) {
    return Err(CustodyLost)
  }
  Ok((host.journal, host.epoch))
}

///|
/// Admit the same original checked Run through its existing transaction and
/// epoch/intent custody under this captured Read. No compilation, dispatch,
/// replacement Run or caller authorization flag is manufactured here.
pub fn NativeLocalJournalCapture::accept_submitted_run_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let allowed = match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    host.journal
    .accept_submitted_run_with_operations(
      host.epoch,
      reference,
      preparation,
      request,
      compiled,
      definition,
      expected_scope,
      allowed,
      now,
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}
