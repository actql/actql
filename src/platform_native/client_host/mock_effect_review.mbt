///|
pub(all) enum NativeClientMockEffectReviewIssue {
  Binding(@publication.RunEvidenceChainIssue)
  Checkpoint(@host.ClientEffectCheckpointBindingIssue)
  Journal(NativeClientRunJournalIssue)
}

///|
// A child of the original command. Store owns encryption/persistence/retirement;
// Journal owns waiting. This record retains their partial outcomes before the
// next call/Read return. It issues no new Run, execution or approval authority.
struct NativeMockEffectReview {
  _retained_store : @publication_store.Store
  mut capture : @publication_store.EffectCaptureCustody?
  mut preview : @publication_store.EffectPreviewCustody?
  mut checkpoint : @publication_store.EffectCheckpointCustody?
  mut capture_confirmed : Bool
  mut preview_confirmed : Bool
  mut checkpoint_confirmed : Bool
  mut waiting_attempted : Bool
  mut waiting : NativeClientRunRecord?
  mut _retained_display_constructor_bytes : Int64
}

///|
/// Save the original complete computation/Preview/Checkpoint, then commit
/// waiting to this SAME accepted/started Request. No ResidentSourceCompute is
/// manufactured for the Native multi-Source/Model path. A failed/unknown
/// persistence or Journal return retains the original child and prohibits retry.
fn NativeLocalJournalCapture::save_effect_review_original_in_scope(
  self : Self,
  first : NativeClientWorkFirstStart,
  definition : @publication.PublicationContract,
  namespace_id : String,
  principal : String,
  current_time : () -> String,
  owner_current : () -> Bool,
  retain : (NativeMockEffectReview) -> Unit,
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
      _retained_display_constructor_bytes: 0L,
    }
    retain(saved)
    let capture_wire = @publication.publication_contract_json(
      @publication.effect_capture_holding_contract(binding),
    )
    let (bytes, nodes, depth) = native_mock_model_evidence_key_codec_limits
    mock_model_require(
      self
      .prepare_model_entry_construction(
        Some(bytes),
        nodes~,
        depth~,
        additional=Some((32, 1, 1)),
      )
      .map_err(issue => Original(issue)),
    )
    let retained_construction = mock_model_require(
      self.prepare_private_store_layouts_construction(
        4,
        index => {
          store.private_evidence_custody_construction(
            match index {
              0 => capture_wire
              1 => review_wire
              2 => continuation_wire
              _ => checkpoint.wire
            },
          )
        },
        additional_retained=retained_metadata,
      ),
    )
    saved._retained_display_constructor_bytes = retained_construction
    guard @publication.effect_computation_record_holding_cid(
        definition,
        @publication.effect_capture_holding_authority(binding),
      ) ==
      Some(@publication.effect_capture_holding_identity(binding)) &&
      @publication.effect_preview_run_identity(preview_identity) ==
      @publication.publication_contract_identity(definition) &&
      checkpoint.checkpoint.required_artifact_cid ==
      @publication.effect_preview_semantic_identity(preview_identity) &&
      checkpoint.checkpoint.review_projection_cid ==
      "sha256:" + @sha.hex(@utf8.encode(review_wire)) else {
      return Err(ForeignOriginal)
    }
    mock_model_require(
      @host.admit_client_effect_review_checkpoint_binding(
        allowed,
        definition,
        checkpoint.wire,
        native_checkpoint_limits(),
      ).map_err(issue => Review(Checkpoint(issue))),
    )
    |> ignore
    let result = self.with_current_adoption_material_in_original_read((
      host,
      material,
      operations,
    ) => {
      let record = match
        host.journal.retained(first.request, reads=Some(operations.reads)) {
        Ok(Some(value)) => value
        Ok(None) => return Err(Journal(CustodyLost))
        Err(issue) => return Err(Journal(issue))
      }
      let (authority, device, inode) = match store.custody_location() {
        Ok(value) => value
        Err(issue) => return Err(Journal(PublicationObservation(issue)))
      }
      let store_binding = match
        installed_publication_binding(namespace_id, authority, device, inode) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
      if !physical_equal(first.journal, host.journal) ||
        first.definition_cid !=
        @publication.publication_contract_identity(definition) ||
        record.revision < first.observed_revision ||
        !record.dispatch_reserved ||
        !record.physical_start_claimed ||
        record.cancellation_requested ||
        record.checkpoint is Some(_) ||
        record.effect_material_originals is None ||
        record.publication_binding != Some(store_binding) ||
        authority != @publication.effect_capture_holding_authority(binding) ||
        @publication.publication_contract_identity(record.definition) !=
        @publication.publication_contract_identity(definition) {
        return Err(Journal(ForeignRun))
      }
      let current = () => {
        owner_current() &&
        self.operation_scope(host, material, principal, connection) is Ok(scope) &&
        scope == @host.client_request_authority_scope_cid(first.request) &&
        self.operation_account(host, material, {
          principal,
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
          .prepare_effect_capture_custody(binding, self.crypto, key)
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
            self.crypto,
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
            self.crypto,
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
            first.request,
            allowed,
            persisted,
            record.revision,
            resume_binding,
            [],
            current_time(),
            current,
            operations=Some(operations),
          ) {
          Ok(value) => value
          Err(issue) => {
            // The original transaction Owner returns TransactionUnknown for
            // lost COMMIT/rollback. All other failures precede COMMIT or have
            // its successful rollback. This clears no Read/Store duty and
            // never retries waiting; it only permits their actual cleanup.
            if !issue.requires_transaction_reconciliation() {
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
  match saved.close() {
    Err(issue) => Err(issue)
    Ok(false) => Ok(false)
    Ok(true) => {
      self.effect_review = None
      Ok(true)
    }
  }
}

///|
pub fn NativeMockEffectReview::close(
  saved : Self,
) -> Result[Bool, NativeClientMockModelIssue] {
  if saved.waiting is Some(_) {
    if !saved.capture_confirmed ||
      !saved.preview_confirmed ||
      !saved.checkpoint_confirmed {
      return Err(ForeignOriginal)
    }
    return Ok(true)
  }
  if saved.waiting_attempted {
    return Err(CleanupPending)
  }
  // Each Store wrapper confirms terminal readback/retirement before returning
  // Ok(changed). False means no quota row changed (including never reserved
  // and already released), not a pending child. Every Err retains that child.
  if saved.checkpoint is Some(child) {
    match child.retry_cleanup() {
      Err(issue) => return Err(Store(issue))
      Ok(_) => saved.checkpoint = None
    }
  }
  if saved.preview is Some(child) {
    match child.retry_cleanup() {
      Err(issue) => return Err(Store(issue))
      Ok(_) => saved.preview = None
    }
  }
  if saved.capture is Some(child) {
    match child.retry_cleanup() {
      Err(issue) => return Err(Store(issue))
      Ok(_) => saved.capture = None
    }
  }
  Ok(true)
}
