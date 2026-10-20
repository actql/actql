///|
// Only the current captured Read may invoke this observation. The same
// physical Journal queries leave/reenter that Read around every SQLite call;
// no candidate row, cached currentness or caller Allow replaces the original.
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
  // Binding immediately invokes the current port below, before its first SQL
  // read. Only private query records are constructed before that invocation;
  // repeating the whole physical fence here observes no intervening operation.
  let queries : NativeLocalJournalReadQueries = {
    original,
    database: host.database,
    failure: None,
  }
  let result = match
    @host.bind_client_local_adopted_host_material(host.database, () => {
      host.current_adoption_material_with_reads(
        () => self.check_current_in_original_read(),
        reads=Some(queries.access()),
      )
    }) {
    Err(issue) => Err(local_current_material_issue(issue))
    Ok(material) => operation(host, material, queries.operation_access())
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
  ) => {
    let body = match
      @host.client_local_adopted_authority_scope_body(
        material,
        host.database,
        principal,
        connection,
      ) {
      Ok(body) => body
      Err(issue) => return Err(local_current_material_issue(issue))
    }
    local_adoption_digest(self.crypto, body)
  })
}

///|
/// Repeat the existing Account Owner decision against current original
/// adoption material. Neither a scope CID nor this observation funds work.
pub fn NativeLocalJournalCapture::authorize_in_original_read(
  self : NativeLocalJournalCapture,
  request : @authorization.AccessTuple,
) -> Result[@authorization.AccountOutcome, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    _operations,
  ) => {
    @host.client_local_adopted_account_outcome(material, host.database, request).map_err(
      local_current_material_issue,
    )
  })
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
  let body = match
    @host.client_local_authority_scope_body(
      host.session.configuration,
      "sha256:" + @sha.hex(host.adoption_body),
      principal,
      connection,
    ) {
    Ok(body) => body
    Err(@host.InvalidInput) => return Err(InvalidInput)
    Err(@host.Encoding) => return Err(Encoding)
  }
  let current_scope = match local_adoption_digest(self.crypto, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if current_scope != expected_scope {
    return Err(Epoch(ScopeMismatch))
  }
  match
    @host.client_local_adopted_account_outcome(material, host.database, {
      principal,
      connection,
      resource: "run",
      operation: "submit",
    }) {
    Ok(Allow(_)) => Ok(true)
    Ok(_) => Ok(false)
    Err(issue) => Err(local_current_material_issue(issue))
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
