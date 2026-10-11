///|
/// Current facts read from the installed Cloud resume Owner, not from a
/// submitted approval or credential. Settlement-only claims cannot send.
pub(all) struct NativeEffectResumeObservation {
  checkpoint_cid : String
  resolution_cid : String
  resume_intent_id : String
  view : @checkpoint.ResumeIntentView
  claim : @checkpoint.ResumeClaim
  now_ms : Int64
  settlement_only : Bool
}

///|
pub(all) struct NativeResidentEffectWriteLimits {
  response : @catalog.WriteCollectionResponseLimits
  ledger : @checkpoint.WireLimits
}

///|
pub(all) enum NativeResidentEffectWriteIssue {
  Unavailable
  AuthorityDenied
  ForeignRequest
  ReconciliationRequired
  Resolution(NativeResidentEffectResolutionIssue)
  Credential(@resource.NativeCredentialResourceIssue)
  Journal(@journal.NativeRemoteJournalIssue)
  UnclassifiedResponse
}

///|
/// Original-holder custody only; the common Ledger decides dispatch and
/// terminality. Pending raw response bytes are retried without another send.
struct NativeResidentEffectApprovedRow {
  owner : NativeResidentEffectReview
  resolution : @checkpoint.VerifiedResolution
  authentication : @checkpoint.HostAuthentication
  reviewers : Array[@checkpoint.ReviewerAuthority]
  keys : Array[NativeEffectHostAuthority]
  current_authority : () -> Bool
  observe_resume : () -> NativeEffectResumeObservation?
  delivery_claim : @checkpoint.ResumeClaim?
  now : () -> String
  preview : @publication.EffectPreviewIdentity
  scope : @request_scope.LogicalRequestScope
  locator : @effect.LogicalItemLocator
  key : @effect.EffectDispatchKey
  basis : @effect.EffectLedgerBasis
  request : @catalog.SingleWriteRequest
  observation : @catalog.TargetObservation?
  limits : NativeResidentEffectWriteLimits
  mut dispatching : @effect.EffectLedgerEntry?
  mut raw : @journal.NativeEffectSavedResponse?
  mut sending : Bool
  mut started : Bool
  mut terminal : (@publication.PublicationContract, @effect.EffectLedgerEntry)?
}

///|
priv suberror NativeEffectWriteFailure {
  WriteFailed(NativeResidentEffectWriteIssue)
}

///|
fn[T] write_checked(
  result : Result[T, NativeResidentEffectWriteIssue],
) -> T raise NativeEffectWriteFailure {
  match result {
    Ok(value) => value
    Err(issue) => raise WriteFailed(issue)
  }
}

///|
/// Choose the physical verb only from an admitted Catalog request and the
/// checked Preview guard. This does not establish approval, current authority
/// or a Ledger claim; the sender must establish all of those separately.
fn native_resident_effect_row_method(
  request : @catalog.SingleWriteRequest,
  observed_version : String?,
  preview_version : String?,
) -> Result[@http.NativeHttpMethod, NativeResidentEffectWriteIssue] {
  match @catalog.single_write_request_kind(request) {
    @catalog.SingleCreate =>
      if @catalog.single_write_request_method(request) == "POST" &&
        observed_version is None &&
        preview_version is None {
        Ok(@http.Post)
      } else {
        Err(ForeignRequest)
      }
    @catalog.SingleUpdateById(_) =>
      if @catalog.single_write_request_method(request) == "PATCH" &&
        observed_version is Some(_) &&
        observed_version == preview_version {
        Ok(@http.Patch)
      } else {
        Err(ForeignRequest)
      }
    _ => Err(ForeignRequest)
  }
}

///|
fn NativeResidentEffectApprovedRow::current(
  self : NativeResidentEffectApprovedRow,
) -> Bool {
  let owner = self.owner
  guard owner.admit_resolution(
      self.resolution.wire,
      self.authentication,
      self.reviewers,
      self.keys,
      self.current_authority,
      self.now,
    )
    is Ok(resolution) &&
    resolution == self.resolution &&
    (self.observe_resume)() is Some(observed) else {
    return false
  }
  let at = (self.now)()
  guard @checkpoint.resumed_approval(
      self.resolution.wire,
      owner.retention_configuration.unwrap().5,
    )
    is Ok(approval) else {
    return false
  }
  observed.checkpoint_cid == resolution.checkpoint_cid &&
  observed.resolution_cid == resolution.resolution_cid &&
  Some(observed.resume_intent_id) == resolution.resume_intent_id &&
  (self.delivery_claim is None || self.delivery_claim == Some(observed.claim)) &&
  !observed.settlement_only &&
  @checkpoint.decide_resume_fence(
    observed.view,
    observed.claim,
    observed.now_ms,
  ) ==
  @checkpoint.FenceCurrent &&
  @checkpoint.resumed_approval_current(approval, at) &&
  @host.client_effect_run_start_current(
    owner.materials.allowed,
    owner.materials.run_definition,
    at,
  ) &&
  (self.current_authority)() &&
  owner.current()
}

///|
/// Checked original row identities only. No approval or send permission.
priv struct NativeResidentEffectRowContext {
  preview : @publication.EffectPreviewIdentity
  scope : @request_scope.LogicalRequestScope
  locator : @effect.LogicalItemLocator
  key : @effect.EffectDispatchKey
  basis : @effect.EffectLedgerBasis
  request : @catalog.SingleWriteRequest
  observation : @catalog.TargetObservation?
}

///|
fn NativeResidentEffectReview::row_context(
  self : NativeResidentEffectReview,
  limits : @checkpoint.WireLimits,
) -> Result[NativeResidentEffectRowContext, NativeResidentEffectWriteIssue] {
  (fn() -> Result[
    NativeResidentEffectRowContext,
    NativeResidentEffectWriteIssue,
  ] raise NativeEffectWriteFailure {
    guard self.captured is Some(capture) &&
      self.targets is Some(targets) &&
      capture.preview.keys.length() == 1 &&
      self.retention_configuration is Some(_) else {
      return Err(Unavailable)
    }
    let (request, observation, origin) = if self.created_targets
      is Some(created) {
      guard targets.is_empty() &&
        created.requests.length() == 1 &&
        created.matches(
          self.consumer,
          self.materials,
          self.inputs,
          self.policy.stage,
          self.policy.effect_id,
          self.policy.result_index,
        ) &&
        @catalog.single_write_request_kind(created.requests[0])
        is @catalog.SingleCreate else {
        return Err(ForeignRequest)
      }
      // Create has no observe use or physical existing target. The exact
      // original Catalog binding supplies its origin, never a later grant.
      (created.requests[0], None, self.policy.catalog.binding.resource_origin)
    } else {
      guard targets.length() == 1 && self.uses.length() == 1 else {
        return Err(Unavailable)
      }
      (targets[0].0, Some(targets[0].2), self.uses[0].scope.resource_origin)
    }
    let scope = write_checked(
      @host.prepared_client_effect_request_scope(
        self.materials.prepared,
        self.request,
      ).map_err(_ => ForeignRequest),
    )
    let preview = write_checked(
      @effect.admit_effect_preview_apply_identity(
        capture.preview.wire,
        @publication.publication_contract_identity(
          self.materials.run_definition,
        ),
        @publication.run_evidence_value_identity(capture.preview.authoring),
        scope,
        [capture.preview.keys.copy()],
        self.policy.preview_limits.max_wire_bytes,
        self.policy.preview_limits.max_nodes,
        self.policy.preview_limits.max_depth,
      ).map_err(_ => ForeignRequest),
    )
    if @publication.effect_preview_member_count(preview) != 1 ||
      @publication.effect_preview_row_count(preview, 0) != Some(1) {
      return Err(ForeignRequest)
    }
    guard @publication.effect_preview_row_intended_value_wire(preview, 0, 0) ==
      Some(@catalog.single_write_request_value(request)) &&
      @publication.effect_preview_row_correlation_wire(preview, 0, 0)
      is Some(correlation) else {
      return Err(ForeignRequest)
    }
    if observation is None {
      let after = "{\"state\":\"present\",\"value\":" +
        @catalog.single_write_request_value(request) +
        "}"
      let inventory = write_checked(
        @publication.derive_effect_create_row_inventory(
          [after],
          1,
          self.policy.preview_limits.max_wire_bytes,
          self.policy.preview_limits.max_nodes,
          self.policy.preview_limits.max_depth,
        ).map_err(_ => ForeignRequest),
      )
      guard inventory.length() == 1 &&
        inventory[0].1 == correlation &&
        @publication.effect_preview_row_guard_version_cid(preview, 0, 0) is None else {
        return Err(ForeignRequest)
      }
    } else {
      guard @catalog.single_write_request_matches_preview_row_target(
          request,
          correlation,
          self.policy.observation_limits.max_identity_bytes,
        )
        is Ok(true) else {
        return Err(ForeignRequest)
      }
    }
    // The Preview was completed by this same holder using these exact requests,
    // current mapping, target observations and Provider footprints.
    let headers = @checked.effect_program_static_headers(
      @host.prepared_client_effect_computation_candidate(
        self.materials.prepared,
      ),
    )
    let program = @syntax.effect_headers_owner(headers)
    guard @syntax.stages(program).get(self.policy.stage) is Some(stage) else {
      return Err(ForeignRequest)
    }
    let bindings = write_checked(
      @effect.prepare_effect_recovery_bindings(
        preview,
        scope,
        program.id,
        stage.id,
        1,
        self.policy.max_work,
      ).map_err(_ => ForeignRequest),
    )
    let binding = bindings[0][0]
    let dispatch = @resident.resident_retained_consumer_request(self.holder)
    let request_cid = write_checked(
      @catalog.single_write_request_cid(
        request,
        origin,
        self.policy.request_limits.max_body_bytes +
        self.policy.request_limits.max_path_bytes +
        4096,
      ).map_err(_ => ForeignRequest),
    )
    let writer = @encode.hashing_writer(1024, 4, 2) catch {
      _ => return Err(ForeignRequest)
    }
    let recovery = try {
      @encode.begin_object(writer)
      @encode.key(writer, "dispatch_request_cid")
      @encode.string_value(writer, @remote.dispatch_request_identity(dispatch))
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-installed-row-effect-recovery/0.1")
      @encode.end_object(writer)
      "sha256:" + @encode.finish_hash(writer)
    } catch {
      _ => return Err(ForeignRequest)
    }
    let unit = @host.client_effect_local_invocation_unit_definition_cid(
      @host.client_effect_local_artifact_invocation(self.artifact),
    )
    let basis = write_checked(
      @effect.prepare_effect_ledger_basis(
        scope,
        binding.locator,
        binding.key,
        unit,
        @publication.effect_preview_member_identity(preview, 0).unwrap(),
        @publication.effect_preview_ordered_row_identity(preview, 0, 0).unwrap(),
        request_cid,
        recovery,
        "unavailable",
        @publication.effect_preview_member_capability_evidence_cid(preview, 0).unwrap(),
        @publication.publication_contract_identity(self.policy.retention),
      ).map_err(_ => ForeignRequest),
    )
    write_checked(
      @effect.issue_prepared_effect_ledger_entry(
        basis,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ).map_err(_ => ForeignRequest),
    )
    |> ignore
    Ok({
      preview,
      scope,
      locator: binding.locator,
      key: binding.key,
      basis,
      request,
      observation,
    })
  })() catch {
    WriteFailed(issue) => Err(issue)
  }
}

///|
/// Restore the original dispatch and response custody without current write
/// permission. The installed caller controls evidence disclosure. Missing or
/// uncertain custody retains cleanup responsibility; this never sends.
pub fn NativeResidentEffectReview::restore_row_custody(
  self : NativeResidentEffectReview,
  limits : @checkpoint.WireLimits,
) -> Result[@journal.NativeEffectRowCustody?, NativeResidentEffectWriteIssue] {
  if self.closed {
    return Err(Unavailable)
  }
  self.effect_pending = true
  self.row_custody_confirmed = false
  (fn() -> Result[
    @journal.NativeEffectRowCustody?,
    NativeResidentEffectWriteIssue,
  ] raise NativeEffectWriteFailure {
    let context = write_checked(self.row_context(limits))
    let custody = write_checked(
      self.journal
      .effect_ledger_custody(
        @resident.resident_retained_consumer_request(self.holder),
        context.scope,
        context.locator,
        context.key,
        context.basis,
        limits,
        self.retention_configuration.unwrap().5,
      )
      .map_err(issue => Journal(issue)),
    )
    if custody is Some(saved) && saved.dispatching is Some(original) {
      if self.approved_row is Some(row) {
        if row.dispatching is Some(existing) &&
          (
            @effect.effect_ledger_entry_cid(existing) !=
            @effect.effect_ledger_entry_cid(original) ||
            @effect.effect_ledger_entry_wire(existing) !=
            @effect.effect_ledger_entry_wire(original)
          ) {
          return Err(ForeignRequest)
        }
        row.dispatching = Some(original)
        row.started = true
        if row.terminal is Some((_, terminal)) &&
          @effect.effect_ledger_entry_cid(terminal) ==
          @effect.effect_ledger_entry_cid(saved.head) &&
          @effect.effect_ledger_entry_wire(terminal) ==
          @effect.effect_ledger_entry_wire(saved.head) {
          self.effect_pending = false
        }
      }
    } else {
      if self.approved_row is Some(row) && (row.started || row.raw is Some(_)) {
        return Err(ReconciliationRequired)
      }
      self.effect_pending = false
    }
    self.row_custody_confirmed = true
    Ok(custody)
  })() catch {
    WriteFailed(issue) => Err(issue)
  }
}

///|
/// Prepare a bounded single-record create or update from this holder's actual
/// checked Preview. No request, membership or claim identity is caller-issued.
pub fn NativeResidentEffectReview::prepare_approved_row(
  self : NativeResidentEffectReview,
  verified_wire : String,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  keys : Array[NativeEffectHostAuthority],
  current_authority : () -> Bool,
  observe_resume : () -> NativeEffectResumeObservation?,
  now : () -> String,
  limits : NativeResidentEffectWriteLimits,
  delivery_claim? : @checkpoint.ResumeClaim? = None,
) -> Result[NativeResidentEffectApprovedRow, NativeResidentEffectWriteIssue] {
  (fn() -> Result[
    NativeResidentEffectApprovedRow,
    NativeResidentEffectWriteIssue,
  ] raise NativeEffectWriteFailure {
    if limits.response.max_bytes < 1 ||
      limits.response.max_bytes > 1000000 ||
      limits.response.max_nodes < 1 ||
      limits.response.max_nodes > 1000 ||
      limits.response.max_depth < 1 ||
      limits.response.max_depth > 32 ||
      limits.response.max_rows != 1 {
      return Err(ForeignRequest)
    }
    let prior = write_checked(self.restore_row_custody(limits.ledger))
    let resolution = write_checked(
      self
      .admit_resolution(
        verified_wire, authentication, reviewers, keys, current_authority, now,
      )
      .map_err(issue => Resolution(issue)),
    )
    if resolution.decision != @checkpoint.Approved ||
      resolution.resume_intent_id is None {
      return Err(AuthorityDenied)
    }
    if self.approved_row is Some(row) {
      if row.resolution != resolution || row.delivery_claim != delivery_claim {
        return Err(ForeignRequest)
      }
      if !row.current() {
        return Err(AuthorityDenied)
      }
      return Ok(row)
    }
    let context = write_checked(self.row_context(limits.ledger))
    let preview = context.preview
    let scope = context.scope
    let request = context.request
    let basis = context.basis
    let row = {
      owner: self,
      resolution,
      authentication,
      reviewers: reviewers.copy(),
      keys: keys.copy(),
      current_authority,
      observe_resume,
      delivery_claim,
      now,
      preview,
      scope,
      locator: context.locator,
      key: context.key,
      basis,
      request,
      observation: context.observation,
      limits,
      dispatching: None,
      raw: None,
      sending: false,
      started: false,
      terminal: None,
    }
    if !row.current() {
      return Err(AuthorityDenied)
    }
    if prior is Some(custody) && custody.dispatching is Some(original) {
      // Restore responsibility before exposing a replacement row. Even a
      // terminal head must be reconciled against the original raw response;
      // physical resource zero does not establish semantic completion.
      row.dispatching = Some(original)
      row.started = true
      self.effect_pending = true
    }
    if !row.current() {
      return Err(AuthorityDenied)
    }
    self.approved_row = Some(row)
    Ok(row)
  })() catch {
    WriteFailed(issue) => Err(issue)
  }
}

///|
/// Only a confirmed new common Ledger claim may reach physical sending. A
/// failed/uncertain send is reconciled, never retried under another use identity.
pub fn NativeResidentEffectApprovedRow::send(
  self : NativeResidentEffectApprovedRow,
  access : NativeSalesforceTargetAccess,
) -> Result[Unit, NativeResidentEffectWriteIssue] {
  if self.started || self.sending {
    return Err(ReconciliationRequired)
  }
  if !self.current() {
    return Err(AuthorityDenied)
  }
  let owner = self.owner
  let dispatch = @resident.resident_retained_consumer_request(owner.holder)
  let execution = @remote.dispatch_request_execution_scope(dispatch)
  let route = @remote.dispatch_request_journal_key(dispatch)
  let scope = access.scope
  if scope.operation !=
    @catalog.single_write_request_grant_operation(self.request) ||
    scope.site_key != execution[0] ||
    scope.site_generation.to_string() != execution[1] ||
    scope.runtime_bundle_cid != execution[2] ||
    scope.task_attempt.to_string() != route[6] ||
    scope.dispatch_request_cid != @remote.dispatch_request_identity(dispatch) ||
    scope.run_invocation_cid !=
    @publication.publication_contract_identity(owner.invocation) ||
    access.credential_org_id !=
    @catalog.single_write_request_org_id(self.request) ||
    !@catalog.single_write_request_matches_site_scope(
      self.request,
      scope.namespace_id,
      scope.principal,
      scope.environment,
      scope.site_key,
      scope.site_generation,
      scope.connector_registration,
      scope.connector_revision,
      scope.resource_origin,
      scope.run_invocation_cid,
      scope.dispatch_request_cid,
    ) ||
    @catalog.recheck_single_write_request(self.request, owner.policy.catalog)
    is Err(_) {
    return Err(ForeignRequest)
  }
  let http_verb = match
    native_resident_effect_row_method(
      self.request,
      self.observation.map(@catalog.target_observation_version_cid),
      @publication.effect_preview_row_guard_version_cid(self.preview, 0, 0),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @catalog.single_write_request_cid(
      self.request,
      scope.resource_origin,
      owner.policy.request_limits.max_body_bytes +
      owner.policy.request_limits.max_path_bytes +
      4096,
    )
    is Ok(request_cid) &&
    request_cid == self.basis.canonical_request_cid else {
    return Err(ForeignRequest)
  }
  self.started = true
  self.sending = true
  owner.effect_pending = true
  let result = (fn() -> Result[Unit, NativeResidentEffectWriteIssue] raise NativeEffectWriteFailure {
    let (won, entry) = write_checked(
      owner.journal
      .claim_effect_ledger_dispatch(
        dispatch,
        self.scope,
        self.locator,
        self.key,
        self.basis,
        self.limits.ledger,
        owner.retention_configuration.unwrap().5,
      )
      .map_err(issue => Journal(issue)),
    )
    self.dispatching = Some(entry)
    if !won {
      return Err(ReconciliationRequired)
    }
    let response = write_checked(
      @resource.call_native_credential_resource_guarded_request_at_path(
        access.service,
        access.grant,
        access.use_id,
        access.scope,
        http_verb,
        @catalog.single_write_request_path(self.request),
        @utf8.encode(@catalog.single_write_request_body(self.request)),
        () => self.current(),
      ).map_err(issue => Credential(issue)),
    )
    self.raw = Some({
      credential_use_cid: response.use_cid,
      status_code: response.status,
      body: Bytes::from_array(response.body.to_array()),
    })
    write_checked(
      owner.journal
      .record_effect_ledger_response(
        dispatch,
        entry,
        self.scope,
        self.locator,
        self.key,
        self.basis.canonical_request_cid,
        self.raw.unwrap(),
      )
      .map_err(issue => Journal(issue)),
    )
    Ok(())
  })() catch {
    WriteFailed(issue) => Err(issue)
  }
  self.sending = false
  result
}

///|
/// Confirm custody of the original response without invoking the Provider or
/// completing the row. Failed or uncertain persistence retains the bytes and
/// cleanup responsibility for the same retry.
pub fn NativeResidentEffectApprovedRow::retry_response_custody(
  self : NativeResidentEffectApprovedRow,
) -> Result[Bool, NativeResidentEffectWriteIssue] {
  if self.sending {
    return Err(ReconciliationRequired)
  }
  guard self.dispatching is Some(entry) else {
    return Err(ReconciliationRequired)
  }
  let journal = self.owner.journal
  let dispatch = @resident.resident_retained_consumer_request(self.owner.holder)
  if self.raw is Some(response) {
    match
      journal.record_effect_ledger_response(
        dispatch,
        entry,
        self.scope,
        self.locator,
        self.key,
        self.basis.canonical_request_cid,
        response,
      ) {
      Err(issue) => return Err(Journal(issue))
      Ok(_) => {
        self.raw = None
        return Ok(true)
      }
    }
  }
  match journal.effect_ledger_response(dispatch, entry) {
    Ok(Some(_)) => Ok(false)
    Ok(None) => Err(ReconciliationRequired)
    Err(issue) => Err(Journal(issue))
  }
}

///|
fn settle_original_row_response(
  owner : NativeResidentEffectReview,
  context : NativeResidentEffectRowContext,
  entry : @effect.EffectLedgerEntry,
  response : @journal.NativeEffectSavedResponse,
  limits : NativeResidentEffectWriteLimits,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeResidentEffectWriteIssue,
] {
  let dispatch = @resident.resident_retained_consumer_request(owner.holder)
  (fn() -> Result[
    (@publication.PublicationContract, @effect.EffectLedgerEntry),
    NativeResidentEffectWriteIssue,
  ] raise NativeEffectWriteFailure {
    if limits.response.max_bytes < 1 ||
      limits.response.max_bytes > 1000000 ||
      limits.response.max_nodes < 1 ||
      limits.response.max_nodes > 1000 ||
      limits.response.max_depth < 1 ||
      limits.response.max_depth > 32 ||
      limits.response.max_rows != 1 {
      return Err(ForeignRequest)
    }
    let projected = if response.status_code >= 200 && response.status_code < 300 {
      @catalog.project_write_single_success(
        response.status_code,
        response.body,
        @catalog.single_write_request_kind(context.request),
        limits.response,
      )
    } else {
      @catalog.project_write_single_rejection(
        response.status_code,
        response.body,
        context.request,
        limits.response,
      )
    }
    let typed = match projected {
      Ok(value) => value
      Err(_) => return Err(UnclassifiedResponse)
    }
    let outcome = match
      @catalog.project_single_effect_outcome(
        typed,
        @publication.effect_preview_ordered_row_identity(context.preview, 0, 0).unwrap(),
        limits.ledger.max_wire_bytes,
        limits.ledger.max_nodes,
        limits.ledger.max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(UnclassifiedResponse)
    }
    let terminal = write_checked(
      owner.journal
      .record_effect_row_receipt(
        dispatch,
        entry,
        context.preview,
        context.scope,
        context.locator,
        context.key,
        context.basis.canonical_request_cid,
        @catalog.write_row_effect_projection_wire(outcome),
        limits.response.max_bytes,
        limits.ledger,
      )
      .map_err(issue => Journal(issue)),
    )
    Ok(terminal)
  })() catch {
    WriteFailed(issue) => Err(issue)
  }
}

///|
/// Reconcile a Store-owned response through the original common receipt Owner.
/// No Resolution renewal, claim or Provider I/O occurs. Absent response bytes
/// remain unresolved; a historical terminal is not accepted without its receipt.
pub fn NativeResidentEffectReview::settle_saved_row(
  self : NativeResidentEffectReview,
  limits : NativeResidentEffectWriteLimits,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeResidentEffectWriteIssue,
] {
  if self.approved_row is Some(row) && row.sending {
    return Err(ReconciliationRequired)
  }
  (fn() -> Result[
    (@publication.PublicationContract, @effect.EffectLedgerEntry),
    NativeResidentEffectWriteIssue,
  ] raise NativeEffectWriteFailure {
    let saved = write_checked(self.restore_row_custody(limits.ledger))
    guard saved is Some(custody) &&
      custody.dispatching is Some(entry) &&
      custody.response is Some(response) else {
      return Err(ReconciliationRequired)
    }
    let context = write_checked(self.row_context(limits.ledger))
    let terminal = write_checked(
      settle_original_row_response(self, context, entry, response, limits),
    )
    if self.approved_row is Some(row) {
      row.terminal = Some(terminal)
      row.raw = None
    }
    self.effect_pending = false
    Ok(terminal)
  })() catch {
    WriteFailed(issue) => Err(issue)
  }
}

///|
/// Retain and classify the same original raw response; this never invokes a
/// Provider. Unknown responses keep the original claim and cleanup obligation.
pub fn NativeResidentEffectApprovedRow::settle(
  self : NativeResidentEffectApprovedRow,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeResidentEffectWriteIssue,
] {
  if self.sending {
    return Err(ReconciliationRequired)
  }
  if self.terminal is Some(value) {
    return Ok(value)
  }
  guard self.dispatching is Some(entry) else {
    return Err(ReconciliationRequired)
  }
  let owner = self.owner
  let dispatch = @resident.resident_retained_consumer_request(owner.holder)
  (fn() -> Result[
    (@publication.PublicationContract, @effect.EffectLedgerEntry),
    NativeResidentEffectWriteIssue,
  ] raise NativeEffectWriteFailure {
    ignore(write_checked(self.retry_response_custody()))
    guard write_checked(
        owner.journal
        .effect_ledger_response(dispatch, entry)
        .map_err(issue => Journal(issue)),
      )
      is Some(response) else {
      return Err(ReconciliationRequired)
    }
    let context = write_checked(owner.row_context(self.limits.ledger))
    let terminal = write_checked(
      settle_original_row_response(owner, context, entry, response, self.limits),
    )
    self.terminal = Some(terminal)
    self.raw = None
    owner.effect_pending = false
    Ok(terminal)
  })() catch {
    WriteFailed(issue) => Err(issue)
  }
}

///|
/// Inspect the checked physical request already retained by this row; this
/// confers no approval or permission to invoke the Provider directly.
pub fn NativeResidentEffectApprovedRow::request(
  self : NativeResidentEffectApprovedRow,
) -> @catalog.SingleWriteRequest {
  self.request
}

///|
/// Inspect original immutable dispatch custody, never issue another claim.
pub fn NativeResidentEffectApprovedRow::dispatch_entry(
  self : NativeResidentEffectApprovedRow,
) -> @effect.EffectLedgerEntry? {
  self.dispatching
}
