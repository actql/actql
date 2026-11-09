///|
pub(all) enum NativeClientMockEffectReviewIssue {
  Binding(@publication.RunEvidenceChainIssue)
  Checkpoint(@host.ClientEffectCheckpointBindingIssue)
  Journal(NativeClientRunJournalIssue)
}

///|
// A child of the SAME ModelWork. Store owns encryption/persistence/retirement;
// Journal owns waiting. This record retains their partial outcomes before the
// next call/Read return. It issues no new Run, execution or approval authority.
priv struct NativeMockEffectReview {
  _retained_store : @publication_store.Store
  mut capture : @publication_store.EffectCaptureCustody?
  mut preview : @publication_store.EffectPreviewCustody?
  mut checkpoint : @publication_store.EffectCheckpointCustody?
  mut capture_confirmed : Bool
  mut preview_confirmed : Bool
  mut checkpoint_confirmed : Bool
  mut waiting_attempted : Bool
  mut waiting : NativeClientRunRecord?
}

///|
/// Save the original complete computation/Preview/Checkpoint, then commit
/// waiting to this SAME accepted/started Request. No ResidentSourceCompute is
/// manufactured for the Native multi-Source/Model path. A failed/unknown
/// persistence or Journal return retains the original child and prohibits retry.
fn NativeClientMockModelWork::save_effect_review_original_in_scope(
  self : NativeClientMockModelWork,
  store : @publication_store.Store,
  allowed : @host.ClientEffectAllowedRun,
  binding : @publication.EffectCaptureHoldingBinding,
  preview_identity : @publication.EffectPreviewIdentity,
  review_wire : String,
  authoring_cid : String,
  checkpoint : @checkpoint.SealedCheckpoint,
  continuation_wire : String,
  resume_binding : @checkpoint.ResumeBinding,
  connection : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  retained_metadata : Int64,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    guard !self.closing &&
      !self.closed &&
      !self.advancing &&
      self.first_start is Some(_) &&
      self.local_observation is Some(_) &&
      self.effect_review is None else {
      return Err(ForeignOriginal)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    let saved : NativeMockEffectReview = {
      _retained_store: store,
      capture: None,
      preview: None,
      checkpoint: None,
      capture_confirmed: false,
      preview_confirmed: false,
      checkpoint_confirmed: false,
      waiting_attempted: false,
      waiting: None,
    }
    self.effect_review = Some(saved)
    let capture_wire = @publication.publication_contract_json(
      @publication.effect_capture_holding_contract(binding),
    )
    let (bytes, nodes, depth) = native_mock_model_evidence_key_codec_limits
    mock_model_require(
      self.capture
      .prepare_model_entry_construction(
        Some(bytes),
        nodes~,
        depth~,
        additional=Some((32, 1, 1)),
      )
      .map_err(issue => Original(issue)),
    )
    mock_model_require(
      self.capture.prepare_private_store_children_construction(
        store,
        4,
        index => {
          match index {
            0 => capture_wire
            1 => review_wire
            2 => continuation_wire
            _ => checkpoint.wire
          }
        },
        additional_retained=retained_metadata,
      ),
    )
    guard @publication.effect_computation_record_holding_cid(
        self.definition,
        @publication.effect_capture_holding_authority(binding),
      ) ==
      Some(@publication.effect_capture_holding_identity(binding)) &&
      @publication.effect_preview_run_identity(preview_identity) ==
      @publication.publication_contract_identity(self.definition) &&
      checkpoint.checkpoint.required_artifact_cid ==
      @publication.effect_preview_semantic_identity(preview_identity) &&
      checkpoint.checkpoint.review_projection_cid ==
      "sha256:" + @sha.hex(@utf8.encode(review_wire)) else {
      return Err(ForeignOriginal)
    }
    mock_model_require(
      @host.admit_client_effect_review_checkpoint_binding(
        allowed,
        self.definition,
        checkpoint.wire,
        native_checkpoint_limits(),
      ).map_err(issue => Review(Checkpoint(issue))),
    )
    |> ignore
    let result = self.capture.with_current_adoption_material_in_original_read((
      host,
      material,
      operations,
    ) => {
      let record = match
        host.journal.retained(self.request, reads=Some(operations.reads)) {
        Ok(Some(value)) => value
        Ok(None) => return Err(Journal(CustodyLost))
        Err(issue) => return Err(Journal(issue))
      }
      let (authority, device, inode) = match store.custody_location() {
        Ok(value) => value
        Err(issue) => return Err(Journal(PublicationObservation(issue)))
      }
      let store_binding = match
        installed_publication_binding(
          self.namespace_id,
          authority,
          device,
          inode,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
      if !record.dispatch_reserved ||
        !record.physical_start_claimed ||
        record.cancellation_requested ||
        record.checkpoint is Some(_) ||
        record.effect_material_originals is None ||
        record.publication_binding != Some(store_binding) ||
        authority != @publication.effect_capture_holding_authority(binding) ||
        @publication.publication_contract_identity(record.definition) !=
        @publication.publication_contract_identity(self.definition) {
        return Err(Journal(ForeignRun))
      }
      let current = () => {
        !self.closing &&
        !self.closed &&
        self.capture.operation_scope(host, material, self.principal, connection)
        is Ok(scope) &&
        scope == @host.client_request_authority_scope_cid(self.request) &&
        self.capture.operation_account(host, material, {
          principal: self.principal,
          connection,
          resource: "run",
          operation: "submit",
        })
        is Ok(@authorization.Allow(_))
      }
      if !current() {
        return Err(Journal(AuthorizationDenied))
      }
      let key = match
        native_local_private_evidence_key(
          host,
          store_binding,
          operations.reads,
          "actql-native-local-effect-review-key/0.1",
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let persist = fn() -> Result[Unit, NativeClientMockModelIssue] raise NativeMockModelStop {
        let capture = mock_model_require(
          store
          .prepare_effect_capture_custody(binding, self.capture.crypto, key)
          .map_err(issue => Store(issue)),
        )
        saved.capture = Some(capture)
        mock_model_require(capture.persist().map_err(issue => Store(issue)))
        let actual = mock_model_require(
          capture.confirm().map_err(issue => Store(issue)),
        )
        if @publication.publication_contract_json(actual) != capture_wire {
          return Err(ForeignOriginal)
        }
        saved.capture_confirmed = true
        if !current() {
          return Err(Review(Journal(AuthorizationDenied)))
        }
        let preview = mock_model_require(
          store
          .prepare_effect_preview_custody(
            preview_identity,
            review_wire,
            authoring_cid,
            authority,
            self.capture.crypto,
            key,
            max_bytes,
            max_nodes,
            max_depth,
          )
          .map_err(issue => Store(issue)),
        )
        saved.preview = Some(preview)
        mock_model_require(preview.persist().map_err(issue => Store(issue)))
        let (_, actual) = mock_model_require(
          preview.confirm().map_err(issue => Store(issue)),
        )
        if actual != review_wire {
          return Err(ForeignOriginal)
        }
        saved.preview_confirmed = true
        if !current() {
          return Err(Review(Journal(AuthorizationDenied)))
        }
        let checkpoint_custody = mock_model_require(
          store
          .prepare_effect_checkpoint_custody(
            checkpoint,
            continuation_wire,
            authority,
            self.capture.crypto,
            key,
          )
          .map_err(issue => Store(issue)),
        )
        saved.checkpoint = Some(checkpoint_custody)
        mock_model_require(
          checkpoint_custody.persist().map_err(issue => Store(issue)),
        )
        let (persisted, actual) = mock_model_require(
          checkpoint_custody.confirm().map_err(issue => Store(issue)),
        )
        if actual != continuation_wire {
          return Err(ForeignOriginal)
        }
        saved.checkpoint_confirmed = true
        // Store confirmations precede this independent Journal transition.
        // Keep known COMMIT inside the callback BEFORE Read return can fail.
        saved.waiting_attempted = true
        let waiting = match
          host.journal.wait_effect_checkpoint_with_operations(
            self.request,
            allowed,
            persisted,
            record.revision,
            resume_binding,
            [],
            (self.current_time)(),
            current,
            operations=Some(operations),
          ) {
          Ok(value) => value
          Err(issue) => {
            // The original transaction Owner returns TransactionUnknown for
            // lost COMMIT/rollback. All other failures precede COMMIT or have
            // its successful rollback. This clears no Read/Store duty and
            // never retries waiting; it only permits their actual cleanup.
            let unknown = match issue {
              TransactionUnknown | Epoch(TransactionUnknown) => true
              _ => false
            }
            if !unknown {
              saved.waiting_attempted = false
            }
            return Err(Review(Journal(issue)))
          }
        }
        saved.waiting = Some(waiting)
        Ok(())
      }
      Ok(persist() catch { NativeMockModelStop(issue) => Err(issue) })
    })
    match result {
      Ok(value) => value
      Err(issue) => Err(Original(issue))
    }
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
// Do not erase retained capture/Preview on an unknown waiting COMMIT. After
// known waiting, disk custody belongs to the original Run; dropping aliases
// neither deletes its evidence nor acknowledges a Store capacity release.
fn NativeClientMockModelWork::close_effect_review(
  self : NativeClientMockModelWork,
) -> Result[Bool, NativeClientMockModelIssue] {
  guard self.effect_review is Some(saved) else { return Ok(true) }
  if saved.waiting is Some(_) {
    if !saved.capture_confirmed ||
      !saved.preview_confirmed ||
      !saved.checkpoint_confirmed {
      return Err(ForeignOriginal)
    }
    self.effect_review = None
    return Ok(true)
  }
  if saved.waiting_attempted {
    return Err(CleanupPending)
  }
  if saved.checkpoint is Some(child) {
    match child.retry_cleanup() {
      Err(issue) => return Err(Store(issue))
      Ok(false) => return Err(CleanupPending)
      Ok(true) => saved.checkpoint = None
    }
  }
  if saved.preview is Some(child) {
    match child.retry_cleanup() {
      Err(issue) => return Err(Store(issue))
      Ok(false) => return Err(CleanupPending)
      Ok(true) => saved.preview = None
    }
  }
  if saved.capture is Some(child) {
    match child.retry_cleanup() {
      Err(issue) => return Err(Store(issue))
      Ok(false) => return Err(CleanupPending)
      Ok(true) => saved.capture = None
    }
  }
  self.effect_review = None
  Ok(true)
}
