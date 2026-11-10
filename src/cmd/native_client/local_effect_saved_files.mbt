///|
priv struct LocalNativeSavedEffectRowTerminal {
  member_index : Int
  ordinal : Int
  locator : @effect.LogicalItemLocator
  key : @effect.EffectDispatchKey
  basis : @effect.EffectLedgerBasis
  head : @effect.EffectLedgerEntry
  receipt : @publication.PublicationContract
}

///|
// Caller custody on the SAME command. Arena/Resource/FS/Journal remain the
// owners of their respective acknowledgements; this record issues none.
priv struct LocalNativeSavedEffectFileWork {
  mut capacity : @execution.ExecutionCapacity
  mut application_base_retained : Int64?
  mut retained_ack_bytes : Int64
  mut entry : @initial_arena.InstalledArenaNonModelWorkEntry?
  mut ledger : @initial_resources.Ledger?
  mut reservation : @initial_resources.Reservation?
  mut child : @row_file.NativeRelationFileTargetIO?
  acknowledgments : Array[
    (
      @row_file.NativeRelationFilePreparedProvider,
      @row_file.NativeRelationFileReplacementAck,
    ),
  ]
  receipts : Array[LocalNativeSavedEffectRowTerminal]
  mut received : Int64
  mut submitted : Int64
  mut response_pending : Bool
  mut publication : LocalNativeSavedEffectPublication?
}

///|
// SQL/current calls occur only in the SAME original Journal coordinator. In
// particular, no business/FS scope is entered with this flight still open.
fn[T] LocalCommandPreparationOriginal::with_saved_effect_journal(
  self : Self,
  call : () -> T raise ClientStop,
) -> T raise ClientStop {
  guard self.run_observation is Some(observation) &&
    observation.journal_operation is Some(operation) else {
    stop("LocalCheckpointReadUnavailable")
  }
  command_preparation_result(
    operation
    .begin_captured_journal_read()
    .map_err(issue => CommandStoreOperation(issue)),
  )
  let result = Ok(call()) catch { ClientStop(message) => Err(message) }
  let returned = operation.finish_captured_journal_read()
  if returned is Err(issue) {
    self.retain_primary(CommandStoreOperation(issue))
  }
  match (result, returned) {
    (Ok(value), Ok(_)) => value
    (Err(message), _) => stop(message)
    (Ok(_), Err(_)) => stop("LocalCheckpointReadReturnUnavailable")
  }
}

///|
// Same current Account's Effect decision, bound to the actual original signed
// Set approval. A technical Mapping, claim or unresolved Delegate grants no
// write. The existing row/lease fence remains independently required before IO.
fn LocalCommandPreparationOriginal::require_saved_effect_file_write(
  self : Self,
  capture : @local_host.NativeLocalJournalCapture,
  continuation : @local_host.NativeLocalEffectResumeOriginal,
  row : LocalNativeSavedEffectFileRow,
) -> Unit raise ClientStop {
  match
    continuation.authorize_saved_file_effect_in_original_read(
      capture,
      row._retained_member_index,
      row._retained_installation._retained_source._retained_declaration,
      row._retained_installation.write.mapping,
      row._retained_installation.binding,
    ) {
    Ok(_) => ()
    Err(issue) => {
      self.retain_primary(CommandSavedFileResume(issue))
      stop("LocalOriginalEffectWriteDenied")
    }
  }
}

///|
// The existing file implementation runs serially. Its one live decoder/Writer
// peak overlaps actually retained original ACK bytes and checked row slots.
// Future ACK bodies are not allocated or reserved at each row's page maximum.
// Requests remain on their already-backed original Read, not copied here.
fn saved_effect_file_application_capacity(
  row_count : Int,
  physical : @execution.ExecutionCapacity,
  retained_ack_bytes : Int64,
) -> @execution.ExecutionCapacity? {
  if row_count < 0 || retained_ack_bytes < 0L {
    return None
  }
  let count = row_count.to_int64()
  guard @execution.preparation_representation_cost({
      // Work, entry/reservation/optional controls and one original child;
      // ACK/provider pairs and row-receipt tuples plus both growable backings.
      record_headers: 29L + 12L * count,
      reference_slots: 84L + 32L * count,
      scalar_words: 29L + 12L * count,
      owned_utf16_units: 0L,
      owned_wire_bytes: retained_ack_bytes,
    })
    is Some(extra) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(physical),
      extra,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(physical),
      extra,
      1L,
    )
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}

///|
// Keep all original restoration material beside the next constructor. This
// composes DATA only; an entered original constructor must acquire physical
// backing before the same reservation can grow beyond its current window.
fn saved_effect_file_next_phase_capacity(
  original : @execution.ExecutionCapacity,
  phase : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  let old_retained = @execution.execution_capacity_retained_bytes(original)
  guard @execution.checked_preparation_add_product(
      old_retained,
      @execution.execution_capacity_retained_bytes(phase),
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      old_retained,
      @execution.execution_capacity_execution_bytes(phase),
      1L,
    )
    is Some(overlap) else {
    return None
  }
  @execution.execution_capacity(
    retained,
    Int64::max(@execution.execution_capacity_execution_bytes(original), overlap),
  )
}

///|
// One original byte token serves restoration constructors and later IO. The
// caller backs this entry/control frame on the original Read BEFORE entering.
// A later phase adds its retained data, takes a scratch maximum, and grows the
// same token before any allocation. No attempt, holding or transfer is reset.
fn LocalCommandPreparationOriginal::prepare_saved_effect_file_entry(
  self : Self,
  capacity : @execution.ExecutionCapacity,
) -> Unit raise ClientStop {
  guard self.business is Some(business) &&
    business.profile.kind == SavedEffectApply &&
    business.execution is Some(execution) &&
    self.host is Some(host) &&
    self.pair is Some(pair) &&
    self.read is Some(read) else {
    stop("LocalOriginalEffectEntryUnavailable")
  }
  if business.saved_effect_files is Some(work) {
    guard work.entry is Some(entry) &&
      work.ledger is None &&
      work.child is None &&
      work.reservation is None &&
      work.acknowledgments.is_empty() &&
      work.receipts.is_empty() &&
      work.publication is None &&
      !work.response_pending else {
      stop("LocalOriginalEffectEntryUnavailable")
    }
    guard saved_effect_file_next_phase_capacity(work.capacity, capacity)
      is Some(combined) else {
      stop("LocalOriginalEffectCapacityUnavailable")
    }
    // Preserve the attempted phase tuple even on a declined/current return;
    // actual token/physical cleanup remains on the existing entry itself.
    work.capacity = combined
    match
      entry.grow_in_original_read(
        @execution.execution_capacity_retained_bytes(combined),
        @execution.execution_capacity_execution_bytes(combined),
      ) {
      Ok(_) => return
      Err(issue) => {
        self.retain_primary(CommandSavedFileEntry(issue))
        stop("LocalOriginalEffectEntryUnavailable")
      }
    }
  }
  let work : LocalNativeSavedEffectFileWork = {
    capacity,
    application_base_retained: None,
    retained_ack_bytes: 0L,
    entry: None,
    ledger: None,
    reservation: None,
    child: None,
    acknowledgments: [],
    receipts: [],
    received: 0L,
    submitted: 0L,
    response_pending: false,
    publication: None,
  }
  business.saved_effect_files = Some(work)
  let acquired = host
    .prepare_domain_nonmodel_work_entry(
      pair,
      read,
      execution,
      @execution.execution_capacity_retained_bytes(work.capacity),
      @execution.execution_capacity_execution_bytes(work.capacity),
    )
    .unwrap_or_else(() => stop("LocalOriginalEffectEntryUnavailable"))
  let ready = match acquired {
    Err(issue) => {
      self.retain_primary(CommandSavedFileEntry(issue))
      stop("LocalOriginalEffectEntryUnavailable")
    }
    Ok(@initial_arena.ReadyNonModelWorkEntry(entry)) => {
      work.entry = Some(entry)
      true
    }
    Ok(@initial_arena.PendingNonModelWorkEntry(entry)) => {
      work.entry = Some(entry)
      false
    }
  }
  if !ready {
    stop("LocalOriginalEffectEntryPending")
  }
  // Entry is retained before every later current/callback or scope switch.
}

///|
// Invoked only by the current original child after actual FS metadata and
// BEFORE lock/Reader/body. The restoration and all earlier ACKs still cohold.
// Totals grow monotonically; no logical work or transfer debit is refunded.
fn LocalCommandPreparationOriginal::prepare_saved_effect_response_construction(
  self : Self,
  work : LocalNativeSavedEffectFileWork,
  row : LocalNativeSavedEffectFileRow,
  ledger : @initial_resources.Ledger,
  bytes : Int,
) -> Bool {
  guard work.entry is Some(entry) &&
    work.application_base_retained is Some(base) &&
    self.business is Some(business) &&
    business.saved_effect_files is Some(actual) &&
    physical_equal(work, actual) &&
    @row_file.native_relation_file_target_update_construction(
      row._retained_row_binding.provider,
      row._retained_installation.write.mapping.write_fields.length(),
      bytes,
      row.changes_wire,
    )
    is Some((physical, raw)) &&
    saved_effect_file_application_capacity(
      business.saved_effect_rows.length(),
      physical,
      work.retained_ack_bytes,
    )
    is Some(phase) &&
    @execution.checked_preparation_add_product(
      base,
      @execution.execution_capacity_retained_bytes(phase),
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      base,
      @execution.execution_capacity_execution_bytes(phase),
      1L,
    )
    is Some(peak) &&
    @execution.execution_capacity(
      Int64::max(
        @execution.execution_capacity_retained_bytes(work.capacity),
        retained,
      ),
      Int64::max(
        @execution.execution_capacity_execution_bytes(work.capacity),
        peak,
      ),
    )
    is Some(capacity) else {
    return false
  }
  work.capacity = capacity
  match
    entry.prepare_constructor_in_entered_scope(
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
      raw,
      entered_ledger=Some(ledger),
    ) {
    Err(issue) => {
      self.retain_primary(CommandSavedFileEntry(issue))
      false
    }
    Ok(_) =>
      !self.closing &&
      !self.closed &&
      self.primary is None &&
      work.child is Some(_) &&
      entry.matches_business_scope(false)
  }
}

///|
fn saved_effect_file_reserve_transfer(
  ledger : @initial_resources.Ledger,
  max_page_bytes : Int,
) -> Result[@initial_resources.Reservation, @initial_resources.LedgerIssue] {
  let transfer = max_page_bytes.to_int64() * 2L
  // SAME entry already funds the child's complete R/E working envelope.
  // This token accounts the actual IO attempt and transfer, not another E peak.
  @initial_resources.reserve_attempt(ledger, transfer, 0L, 0L)
}

///|
fn LocalCommandPreparationOriginal::apply_saved_effect_files(
  self : Self,
  capture : @local_host.NativeLocalJournalCapture,
  continuation : @local_host.NativeLocalEffectResumeOriginal,
  capacity : @execution.ExecutionCapacity,
  initial_raw : Int64,
) -> Unit raise ClientStop {
  guard self.business is Some(business) &&
    business.profile.kind == SavedEffectApply &&
    business.execution is Some(execution) &&
    self.host is Some(_) &&
    self.pair is Some(_) &&
    self.read is Some(_) else {
    stop("LocalOriginalEffectExecutionUnavailable")
  }
  continuation
  .prepare_saved_publication_construction_in_original_read()
  .map_err(issue => CommandSavedEffectPublication(issue))
  |> command_preparation_result
  continuation
  .prepare_file_application_controls_in_original_read()
  .map_err(issue => CommandSavedFileResume(issue))
  |> command_preparation_result
  let work = business.saved_effect_files.unwrap()
  guard work.application_base_retained is None else {
    stop("LocalOriginalEffectEntryUnavailable")
  }
  work.application_base_retained = Some(
    @execution.execution_capacity_retained_bytes(work.capacity),
  )
  // The last restoration constructor backed only its own original window.
  // A Read-side logical resize cannot acquire more business backing. Retain
  // the attempted full phase first, then enter the SAME original business
  // constructor below: it acquires usable storage BEFORE resizing this token.
  work.capacity = saved_effect_file_next_phase_capacity(work.capacity, capacity).unwrap_or_else(() => {
      stop("LocalOriginalEffectCapacityUnavailable")
    },
  )
  let capacity = work.capacity
  self.with_business_request(capture, () => {
    let entry = work.entry.unwrap()
    let (header, _, _, array_header, pointer) = @initial_bootstrap.native_managed_value_layout()
    // This immediate original Ledger/entered-controller frame has at most
    //64 slots; variable IO backing is the separately admitted full capacity.
    match
      entry.prepare_constructor_in_entered_scope(
        @execution.execution_capacity_retained_bytes(capacity),
        @execution.execution_capacity_execution_bytes(capacity),
        Int64::max(
          initial_raw,
          Int64::max(header, array_header) + 64L * pointer,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => {
        self.retain_primary(CommandSavedFileEntry(issue))
        stop("LocalOriginalEffectEntryUnavailable")
      }
    }
    let ledger = entry
      .take_entered_ledger(
        execution,
        @execution.execution_capacity_retained_bytes(capacity),
        @execution.execution_capacity_execution_bytes(capacity),
      )
      .unwrap_or_else(() => stop("LocalOriginalEffectEntryUnavailable"))
    work.ledger = Some(ledger)
  })
  self.with_saved_effect_journal(() => {
    match continuation.claim(30000L) {
      Ok(@local_host.Claimed(_)) => ()
      Ok(_) => stop("LocalOriginalEffectSettlementOnly")
      Err(issue) => {
        self.retain_primary(CommandSavedFileResume(issue))
        stop("LocalOriginalEffectClaimUnavailable")
      }
    }
  })
  // Claim is ownership only. Admit every actual target's current Effect tuple
  // against that SAME original signed Set before the first row dispatch.
  for row in business.saved_effect_rows {
    self.require_saved_effect_file_write(capture, continuation, row)
  }
  for row in business.saved_effect_rows {
    let member_index = row._retained_member_index
    let ordinal = row._retained_row_ordinal
    let original = continuation
      .application_original_in_original_read()
      .unwrap_or_else(() => stop("LocalCheckpointOriginalUnavailable"))
    let (locator, key, basis) = continuation
      .prepare_application_file_row_in_original_read(
        member_index,
        ordinal,
        row.request_cid,
      )
      .unwrap_or_else(() => stop("LocalOriginalEffectRowUnavailable"))
    self.require_saved_effect_file_write(capture, continuation, row)
    let dispatch = self.with_saved_effect_journal(() => {
      match
        continuation.dispatch_row(
          original.effect_preview(),
          member_index,
          ordinal,
          locator,
          key,
          basis,
        ) {
        Ok(@local_host.DispatchRecorded(value)) => value
        Ok(_) => stop("LocalOriginalEffectRowNoSend")
        Err(issue) => {
          self.retain_primary(CommandSavedFileResume(issue))
          stop("LocalOriginalEffectDispatchUnavailable")
        }
      }
    })
    // A foreign provider, even for an equal path, cannot inherit a prior ACK.
    let provider = row._retained_row_binding.provider
    let mut predecessor = None
    for (prior_provider, ack) in work.acknowledgments {
      if physical_equal(prior_provider, provider) {
        predecessor = Some(ack)
      }
    }
    self.with_business_request(capture, () => {
      let ledger = work.ledger.unwrap()
      let reservation = saved_effect_file_reserve_transfer(
        ledger,
        row._retained_row_binding.limits.page.max_bytes,
      ).map_err(issue => CommandSavedFileResource(issue))
      let reservation = command_preparation_result(reservation)
      work.reservation = Some(reservation)
      let staging = "actql-update-" +
        member_index.to_string() +
        "-" +
        ordinal.to_string()
      let holder : Ref[@row_file.NativeRelationFileTargetIO?] = Ref(None)
      let child = match
        @row_file.prepare_native_relation_file_target_update_io(
          provider,
          row._retained_installation.write.mapping.write_fields,
          row.identity,
          (row.version, row.changes_wire, staging),
          bytes => {
            guard holder.val is Some(child) &&
              work.child is Some(actual) &&
              physical_equal(child, actual) &&
              !self.closing &&
              !self.closed &&
              self.primary is None &&
              work.ledger is Some(original) &&
              physical_equal(original, ledger) else {
              return false
            }
            self.prepare_saved_effect_response_construction(
              work, row, ledger, bytes,
            )
          },
          predecessor~,
        ) {
        Ok(value) => value
        Err(issue) => {
          self.retain_primary(CommandBusinessSource(issue))
          stop("LocalOriginalEffectTargetUnavailable")
        }
      }
      holder.val = Some(child)
      work.child = Some(child)
      command_preparation_result(
        @initial_resources.consume_reserved_attempt(ledger, reservation).map_err(issue => {
            CommandSavedFileResource(issue)
          },
        ),
      )
      work.received = 0L
      work.submitted = 0L
    })
    let mut complete = false
    for _ in 0..<row._retained_row_binding.limits.max_work {
      self.require_saved_effect_file_write(capture, continuation, row)
      self.with_saved_effect_journal(() => {
        match continuation.fence() {
          Ok(@local_host.Current) => ()
          Ok(_) => stop("LocalOriginalEffectFenceUnavailable")
          Err(issue) => {
            self.retain_primary(CommandSavedFileResume(issue))
            stop("LocalOriginalEffectFenceUnavailable")
          }
        }
      })
      complete = self.with_business_request(capture, () => {
        let child = work.child.unwrap()
        let result = child.advance()
        // Preserve actual physical failure before any later accounting failure.
        if result is Err(issue) {
          self.retain_primary(CommandBusinessSource(issue))
        }
        let (received, submitted) = child.byte_counts()
        if received < work.received || submitted < work.submitted {
          stop("LocalOriginalEffectTransferUnavailable")
        }
        let ledger = work.ledger.unwrap()
        let reservation = work.reservation.unwrap()
        command_preparation_result(
          @initial_resources.charge_transfer(
            ledger,
            reservation,
            received - work.received,
          ).map_err(issue => CommandSavedFileResource(issue)),
        )
        work.received = received
        let charged = if result is Err(_) {
          @initial_resources.mark_transfer_uncertain(
            ledger,
            reservation,
            submitted - work.submitted,
          )
        } else {
          @initial_resources.charge_transfer(
            ledger,
            reservation,
            submitted - work.submitted,
          )
        }
        command_preparation_result(
          charged.map_err(issue => CommandSavedFileResource(issue)),
        )
        work.submitted = submitted
        match result {
          Ok(value) => value
          Err(_) => stop("LocalOriginalEffectTargetFailed")
        }
      })
      if complete {
        break
      }
    }
    if !complete {
      stop("LocalOriginalEffectTargetWorkLimit")
    }
    let ack = self.with_business_request(capture, () => {
      let child = work.child.unwrap()
      let ack = child
        .replacement_acknowledgment()
        .unwrap_or_else(() => {
          stop("LocalOriginalEffectReplacementUnacknowledged")
        })
      // Retain SAME ACK/body before close or its scope return can fail.
      let ack_bytes = @execution.checked_preparation_add_product(
        work.retained_ack_bytes,
        ack.replacement().length().to_int64(),
        1L,
      ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
      work.acknowledgments.push((provider, ack))
      work.retained_ack_bytes = ack_bytes
      work.response_pending = true
      match child.close() {
        Ok(true) => work.child = None
        Ok(false) => stop("LocalOriginalEffectTargetCleanupPending")
        Err(issue) => {
          self.retain_primary(CommandBusinessSource(issue))
          stop("LocalOriginalEffectTargetCleanupPending")
        }
      }
      command_preparation_result(
        @initial_resources.settle_reservation(
          work.ledger.unwrap(),
          work.reservation.unwrap(),
        ).map_err(issue => CommandSavedFileResource(issue)),
      )
      work.reservation = None
      ack
    })
    if ack.identity() != row.identity {
      stop("LocalOriginalEffectAckForeignRow")
    }
    // Prepared DATA becomes outcome evidence only with this SAME actual
    // fsync/generation ACK, never from the Preview or template alone.
    let outcome = row.outcome_template
    let (receipt, head) = self.with_saved_effect_journal(() => {
      continuation
      .record_file_row_receipt_in_original_read(
        dispatch,
        member_index,
        ordinal,
        locator,
        key,
        row._retained_installation.binding,
        row.target_cid,
        row.request_cid,
        ack,
        outcome,
        row._retained_row_binding.limits.page.max_bytes,
      )
      .map_err(issue => CommandSavedFileResume(issue))
      |> command_preparation_result
    })
    work.receipts.push({
      member_index,
      ordinal,
      locator,
      key,
      basis,
      head,
      receipt,
    })
    work.response_pending = false
  }
}

///|
// Pure prepared DATA only. The caller matches the SAME actual physical ACK
// before recording it; this template grants no outcome or published Result.
fn saved_effect_file_outcome_wire(
  identity : String,
  max_bytes : Int,
) -> String? {
  try {
    let writer = @encode.writer(max_bytes, 8, 3)
    @encode.begin_object(writer)
    @encode.key(writer, "result")
    @encode.begin_object(writer)
    @encode.key(writer, "id")
    @encode.string_value(writer, identity)
    @encode.end_object(writer)
    @encode.key(writer, "state")
    @encode.string_value(writer, "applied")
    @encode.end_object(writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}

///|
fn LocalCommandPreparationOriginal::close_saved_effect_file_children(
  self : Self,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.business is Some(business) &&
    business.saved_effect_files is Some(work) else {
    return Ok(())
  }
  guard self.host is Some(host) && business.execution is Some(execution) else {
    return Err(CommandBusinessChildren)
  }
  match self.close_saved_effect_publication(work) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if work.ledger is Some(ledger) {
    match business.enter_children_cleanup(host) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if work.child is Some(child) {
      match child.close() {
        Ok(true) => work.child = None
        Ok(false) => return Err(CommandBusinessChildren)
        Err(issue) => return Err(CommandBusinessSource(issue))
      }
    }
    if work.response_pending {
      return Err(CommandBusinessChildren)
    }
    work.acknowledgments.clear()
    work.acknowledgments.shrink_to_fit()
    if work.reservation is Some(reservation) {
      match @initial_resources.settle_reservation(ledger, reservation) {
        Ok(_) => work.reservation = None
        Err(issue) => return Err(CommandSavedFileResource(issue))
      }
    }
    work.ledger = None
    if !work.entry.unwrap().finish_business_cleanup() {
      return Err(CommandBusinessChildren)
    }
    match host.leave_domain_retained_execution(execution) {
      Ok(_) => business.active = false
      Err(issue) => return Err(CommandRetainedExecution(issue))
    }
  } else if business.active {
    match business.enter_children_cleanup(host) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    match host.leave_domain_retained_execution(execution) {
      Ok(_) => business.active = false
      Err(issue) => return Err(CommandRetainedExecution(issue))
    }
  }
  // The Store still uses this SAME execution in its cleanup coordinator.
  // Keep the original entry/context until Store, Root and routing metadata
  // acknowledge; completing file children alone cannot retire that context.
  Ok(())
}

///|
fn LocalCommandPreparationOriginal::close_saved_effect_entry_after_stores(
  self : Self,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.business is Some(business) &&
    business.saved_effect_files is Some(work) else {
    return Ok(())
  }
  if business.store is Some(_) ||
    business.store_failure is Some(_) ||
    business.operation is Some(_) ||
    business.store_root is Some(_) ||
    business.store_parent is Some(_) ||
    work.child is Some(_) ||
    work.reservation is Some(_) ||
    work.ledger is Some(_) ||
    work.response_pending ||
    work.publication is Some(_) ||
    business.active {
    return Err(CommandBusinessChildren)
  }
  work.receipts.clear()
  work.receipts.shrink_to_fit()
  // Every child has now returned. Only the existing entry Owner can attest
  // actual C retirement, settle its original token and report/close domain.
  if work.entry is Some(entry) {
    if !entry.close_after_original_return() {
      return Err(CommandBusinessChildren)
    }
    business.execution = None
  }
  business.saved_effect_files = None
  Ok(())
}
