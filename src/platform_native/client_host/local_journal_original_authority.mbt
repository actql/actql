///|
// Same Read-owned fixed controls for the existing Effect Journal route. This
// admission runs BEFORE each new accessor/operation/callback bundle exists.
// Keep its full prefix through the row codec and the original Read's return.
// Each claim/fence/dispatch/receipt entry admits before its captured callback;
// neither a successful metadata lookup nor a returned lease pays this cost.
fn NativeLocalJournalCapture::retain_effect_journal_route_controls(
  self : NativeLocalJournalCapture,
  additional_controls? : Int64 = 0L,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard !self.closing && self.original_resources is Some(resources) else {
    return Err(OriginalResourceScopePending)
  }
  resources.retain_effect_journal_route_controls(additional_controls~)
}

///|
fn NativeLocalJournalOriginalResources::retain_effect_journal_route_controls(
  self : Self,
  additional_controls? : Int64 = 0L,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard !self.interrupted &&
    self.active_phase is Some(@arena.HostRead) &&
    additional_controls >= 0L else {
    return Err(OriginalResourceScopePending)
  }
  // Charge fixed newly retained routing controls, not a larger allowance:
  // two Read accessor bundles (34 headers/86 references), the operation
  // bundle (13/35), queries plus invalidator (2/6), and callback/options/
  // Results/temporary handoffs (15/33 plus sixteen scalar words). Each
  // accessor closure includes its code and original receiver reference.
  // Keep this prefix in SAME Read metadata so the subsequent row codec
  // pays its simultaneous overlap; a temporary peak would omit that sum.
  let controls = @execution.preparation_representation_cost({
    record_headers: 64L,
    reference_slots: 160L,
    scalar_words: 16L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let controls = match
    @execution.checked_preparation_add_product(
      controls, additional_controls, 1L,
    ) {
    Some(total) => total
    None => return Err(ConfigurationLimit)
  }
  guard @execution.checked_preparation_add_product(
      self.metadata_retained,
      controls,
      1L,
    )
    is Some(total) else {
    return Err(ConfigurationLimit)
  }
  // Existing non-grant Owner admission checks the unchanged Ledger policy
  // and acquires backing before any callback/bundle below is constructed.
  // Refusal keeps its original resource/cleanup issue and emits no commit.
  match
    self.host.prepare_domain_original_read_construction(
      self.read,
      total,
      total,
      controls,
    ) {
    Ok(_) => self.metadata_retained = total
    Err(issue) => return Err(OriginalResources(@arena.Read(issue)))
  }
  Ok(())
}

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
  installation_written? : Ref[Bool]? = None,
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
        is Some("client_local_read_evidence" | "client_local_read_custody") {
        self.clear_read_evidence_observations()
      }
      if table is Some("client_submission_epoch") {
        host.epoch.invalidate_custody()
      }
      let installation = table
        is Some(
          "client_local_settings"
          | "client_local_installation_originals"
          | "client_local_installation_custody"
        )
      if installation && installation_written is Some(written) {
        // The explicit installer owns one closed transaction. It authenticates
        // any other installed roles under the same admitted Account and source
        // files before the commit. Retire this observation before it returns.
        written.val = true
      } else if installation ||
        table is None ||
        table is Some("client_local_adoption") {
        self.read_facts_valid = false
        self.clear_read_operation_facts()
        host.journal.admitted_adoption = None
      }
      if table
        is Some("client_submitted_intents" | "client_submitted_intent_custody") {
        host.journal.invalidate_operation_submission()
      }
      if table is None ||
        table == Some(effect_ledger_entry_table) ||
        table
        is Some(
          "client_runs"
          | "client_effect_custody"
          | "client_task_run_materials"
        ) {
        host.journal.invalidate_operation_run()
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
  let retire_installation_snapshot = installation_written is Some(written) &&
    written.val
  if retire_installation_snapshot {
    host.journal.admitted_adoption = None
  }
  if retire_installation_snapshot ||
    queries.failure is Some(_) ||
    self.read_operation_issue is Some(_) {
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
// Join the accepted request to the current submit authority before allowing
// the caller to claim or observe its original physical start.
fn[T] NativeLocalJournalCapture::with_local_effect_start_authority(
  self : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity,
  principal : String,
  connection : String,
  owner_current : () -> Bool,
  source : (String, String)?,
  operation : (
    NativeClientRunJournal,
    NativeClientJournalOperationAccess,
    () -> Bool,
  ) -> Result[T, NativeLocalAdoptionIssue],
) -> Result[T, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let current = () => {
      owner_current() &&
      self.operation_scope(host, material, principal, connection) is Ok(scope) &&
      scope == @host.client_request_authority_scope_cid(request) &&
      self.operation_account(host, material, {
        principal,
        connection,
        resource: "run",
        operation: "submit",
      })
      is Ok(@authorization.Allow(_)) &&
      (match source {
        None => true
        Some((connection, resource)) =>
          self.operation_account(host, material, {
            principal,
            connection,
            resource,
            operation: "read",
          })
          is Ok(@authorization.Allow(_))
      })
    }
    operation(host.journal, operations, current)
  })
}

///|
/// Claim the original accepted Effect start. Retain its proof while the
/// captured Read still owns the original Journal operation.
pub fn NativeLocalJournalCapture::claim_effect_start_in_original_read(
  self : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity,
  principal : String,
  connection : String,
  owner_current : () -> Bool,
  retain : (NativeClientWorkFirstStart) -> Unit,
) -> Result[Result[Unit, NativeClientSourceWorkIssue], NativeLocalAdoptionIssue] {
  self.with_local_effect_start_authority(
    request,
    principal,
    connection,
    owner_current,
    None,
    (journal, operations, current) => {
      let original = claim_native_client_retained_work_first_start_with_operations(
        journal,
        request,
        current,
        operations=Some(operations),
      )
      Ok(original.map(retain))
    },
  )
}

///|
/// Reobserve the first-start proof before using already captured inputs.
pub fn NativeLocalJournalCapture::require_effect_start_in_original_read(
  self : NativeLocalJournalCapture,
  first : NativeClientWorkFirstStart,
  request : @host.ClientRequestIdentity,
  principal : String,
  connection : String,
  owner_current : () -> Bool,
) -> Result[Result[Unit, NativeClientSourceWorkIssue], NativeLocalAdoptionIssue] {
  self.with_local_effect_start_authority(
    request,
    principal,
    connection,
    owner_current,
    None,
    (journal, operations, current) => {
      Ok(
        first.require_current(
          journal,
          request,
          current,
          reads=Some(operations.reads),
        ),
      )
    },
  )
}

///|
/// Recheck the exact claim and Source grant before a physical step.
pub fn NativeLocalJournalCapture::require_effect_source_in_original_read(
  self : NativeLocalJournalCapture,
  first : NativeClientWorkFirstStart,
  request : @host.ClientRequestIdentity,
  principal : String,
  control_connection : String,
  source_connection : String,
  resource : String,
  owner_current : () -> Bool,
) -> Result[Result[Unit, NativeClientSourceWorkIssue], NativeLocalAdoptionIssue] {
  self.with_local_effect_start_authority(
    request,
    principal,
    control_connection,
    owner_current,
    Some((source_connection, resource)),
    (journal, operations, current) => {
      Ok(
        first.require_current(
          journal,
          request,
          current,
          reads=Some(operations.reads),
        ),
      )
    },
  )
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
  self.original_run_operation_allowed(
    host, material, principal, connection, expected_scope, "submit",
  )
}

///|
// The original Account Owner evaluates the selected actual operation. Shared
// scope/current plumbing does not create a cached Allow or another authority.
fn NativeLocalJournalCapture::original_run_operation_allowed(
  self : NativeLocalJournalCapture,
  host : NativeLocalHostConnection,
  material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
  principal : String,
  connection : String,
  expected_scope : String,
  operation : String,
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
      operation,
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

///|
// A fixed higher signing wrapper overlaps the existing Read routing bundle.
// This is a real same-Read Owner admission, never an allowance or permission.
fn NativeLocalJournalCapture::retain_initial_signing_journal_controls(
  self : NativeLocalJournalCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard !self.closing && self.original_resources is Some(resources) else {
    return Err(OriginalResourceScopePending)
  }
  resources.retain_initial_signing_journal_controls()
}

///|
fn NativeLocalJournalOriginalResources::retain_initial_signing_journal_controls(
  self : Self,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  // Closed additional overlap: two wrapper/work closures and their captured
  // originals, one typed outcome Ref and its Result/Some/return handoffs
  // (at most 12 headers, 40 references, 16 words); the finite signing ->
  // storage/append -> custody -> validation stack adds at most twelve
  // read/operation option frames and joins (12/24/16). No payload copies,
  // growing collections or per-row retained wrapper are admitted here.
  let additional_controls = @execution.preparation_representation_cost({
    record_headers: 24L,
    reference_slots: 64L,
    scalar_words: 32L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  self.retain_effect_journal_route_controls(additional_controls~)
}
