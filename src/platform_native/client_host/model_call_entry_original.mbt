///|
// Temporary tuple/Some plus the closed seven-reference callback below. All
// evidence bodies are borrowed from the original Model owner, never copied
// into a second evidence/authority table. Returned wire has its own writer
// construction allowance; a disk quota cannot fund these live constructors.
fn NativeLocalJournalCapture::prepare_model_entry_construction(
  self : NativeLocalJournalCapture,
  output_bytes : Int?,
  nodes? : Int = 16,
  depth? : Int = 2,
  additional? : (Int, Int, Int)? = None,
  additional_controls? : @execution.PreparationRepresentationUnits? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard !self.closing &&
    self.original_resources is Some(original) &&
    !original.interrupted &&
    original.active_phase is Some(@arena.HostRead) else {
    return Err(OriginalResourceScopePending)
  }
  let controls = @execution.preparation_representation_cost({
    record_headers: 3L,
    reference_slots: 12L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let (header, _, _, _, pointer) = @bootstrap.native_managed_value_layout()
  // One closure code pointer plus its seven captured references. This also
  // covers the smaller two-Int/four-reference tuple and its Some wrapper.
  let control_raw = header + 8L * pointer
  let (retained, execution, raw) = match output_bytes {
    None => (0L, controls, control_raw)
    Some(bytes) => {
      guard journal_row_construction_working(bytes, nodes, depth)
        is Some((retained, execution, raw)) &&
        @execution.checked_preparation_add_product(execution, controls, 1L)
        is Some(total) else {
        return Err(ConfigurationLimit)
      }
      (retained, total, Int64::max(raw, control_raw))
    }
  }
  let (retained, execution, raw) = match additional {
    None => (retained, execution, raw)
    Some((bytes, nodes, depth)) => {
      guard journal_row_construction_working(bytes, nodes, depth)
        is Some((more_retained, more_execution, more_raw)) &&
        @execution.checked_preparation_add_product(retained, more_retained, 1L)
        is Some(total_retained) &&
        @execution.checked_preparation_add_product(
          execution, more_execution, 1L,
        )
        is Some(total_execution) else {
        return Err(ConfigurationLimit)
      }
      (total_retained, total_execution, Int64::max(raw, more_raw))
    }
  }
  let (retained, execution, raw) = match additional_controls {
    None => (retained, execution, raw)
    Some(units) => {
      guard @execution.preparation_representation_cost(units) is Some(bytes) &&
        @execution.checked_preparation_add_product(retained, bytes, 1L)
        is Some(r) &&
        @execution.checked_preparation_add_product(execution, bytes, 1L)
        is Some(e) else {
        return Err(ConfigurationLimit)
      }
      (r, e, Int64::max(raw, bytes))
    }
  }
  original.host
  .prepare_domain_original_read_construction(
    original.read,
    retained,
    execution,
    raw,
  )
  .map_err(issue => OriginalResources(@arena.Read(issue)))
}

///|
// Private journal metadata only. The three evidence bodies remain exactly
// those admitted by the existing Model owner; no wire is an execution token.
fn native_model_entry_body(
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  slot : Int,
  call : @publication.RunEvidenceValue,
  attempt : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
  maximum : Int,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(maximum, 16, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "attempt")
    @encode.string_value(writer, @publication.run_evidence_value_json(attempt))
    @encode.key(writer, "authority")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(authority),
    )
    @encode.key(writer, "call")
    @encode.string_value(writer, @publication.run_evidence_value_json(call))
    @encode.key(writer, "request_scope_cid")
    @encode.string_value(writer, @host.client_request_scope_cid(request))
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(definition),
    )
    @encode.key(writer, "slot")
    @encode.number_value(writer, slot.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-model-call-original/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
/// Persist the exact original entry for the installed single-attempt Mock
/// caller. This observes durable entry only: it neither acknowledges Core nor
/// supplies current dispatch permission. The caller retains the committed
/// outcome BEFORE returning the captured Read, then issues Core's same-entry
/// saved acknowledgement only back inside its original Model execution frame.
/// Existing/ambiguous entries never imply a new save or resend permission.
pub fn NativeLocalJournalCapture::persist_model_call_entry_in_original_read(
  self : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  prepared : @model.ModelPreparedCallSet,
  admission : @host.ClientInferDispatchAdmission,
  entry : @model.ModelCallEntry,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.prepare_model_entry_construction(None) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    guard @host.client_infer_dispatch_matches_run(
        admission, compiled, definition,
      ) &&
      @model.model_call_entry_persistence_originals(entry, prepared, admission)
      is Some((count, slot, call, attempt, authority, model_scope)) &&
      count > 0 &&
      slot >= 0 &&
      slot < count else {
      return Err(Journal(ForeignRun))
    }
    // Exact fixed field spelling/punctuation and longest Int spelling. The
    // existing encoder bounds escaped UTF16 by six UTF8 bytes per code unit.
    let fixed = "{\"attempt\":\"\",\"authority\":\"\",\"call\":\"\",\"request_scope_cid\":\"\",\"run_definition_cid\":\"\",\"slot\":2147483647,\"version\":\"actql-native-model-call-original/0.1\"}"
      .length()
      .to_int64()
    let units = @publication.run_evidence_value_json(call).length().to_int64() +
      @publication.run_evidence_value_json(attempt).length().to_int64() +
      @publication.run_evidence_value_json(authority).length().to_int64() +
      @host.client_request_scope_cid(request).length().to_int64() +
      @publication.publication_contract_identity(definition).length().to_int64()
    guard @execution.checked_preparation_add_product(fixed, units, 6L)
      is Some(bound) &&
      bound > 0L &&
      bound < 2147483519L &&
      bound <= self.max_snapshot_bytes else {
      return Err(Journal(CapacityExceeded))
    }
    match self.prepare_model_entry_construction(Some(bound.to_int())) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let body = match
      native_model_entry_body(
        request,
        definition,
        slot,
        call,
        attempt,
        authority,
        bound.to_int(),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    let table = "client_model_call_originals"
    let scope = @publication.model_invocation_scope_cid(model_scope)
    let key = @publication.run_evidence_value_identity(attempt)
    host.journal
    .transaction_with_reads(
      () => {
        let record = match
          host.journal.retained(request, reads=Some(operations.reads)) {
          Ok(Some(value)) => value
          Ok(None) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        if !record.dispatch_reserved ||
          !record.physical_start_claimed ||
          record.effect_material_originals is None ||
          record.checkpoint is Some(_) ||
          @publication.publication_contract_identity(record.definition) !=
          @publication.publication_contract_identity(definition) {
          return Err(ForeignRun)
        }
        // No historical equality/absence shortcut can issue a fresh ACK.
        match
          read_client_journal_value(
            host.database,
            table,
            key,
            Some(operations.reads),
          ) {
          Ok(_) => return Err(ChangedIntent)
          Err(@sqlite.NotFound) => ()
          Err(issue) => return Err(Physical(issue))
        }
        let usage = match
          read_client_journal_capacity(
            host.database,
            table,
            scope,
            Some(operations),
          ) {
          Ok(value) => value
          Err(@sqlite.NotFound) if slot == 0 =>
            { reserved_bytes: 0L, reserved_objects: 0L, }
          Err(@sqlite.NotFound) => return Err(CustodyLost)
          Err(issue) => return Err(Physical(issue))
        }
        // The original synchronous Mock owner enters its finite slots in order.
        // Lost counters, another entry for a past slot and reentry cannot renew
        // consumed calls or recreate accounting from absent metadata.
        if usage.reserved_objects != slot.to_int64() * 2L ||
          usage.reserved_objects >= count.to_int64() * 2L {
          return Err(CustodyLost)
        }
        // This is the existing installation's finite journal byte census, not
        // Model attempts, a memory grant or an extra user-configurable limit.
        // Each checked single-attempt Slot has one Entry and one eventual
        // settlement row. They share this SAME byte/object census; a later
        // Slot cannot start before the preceding settlement was saved.
        match
          reserve_client_journal_capacity(
            host.database,
            table,
            scope,
            body.length().to_int64(),
            1L,
            self.max_snapshot_bytes,
            count.to_int64() * 2L,
            Some(operations),
          ) {
          Ok(_) => ()
          Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
          Err(issue) => return Err(Physical(issue))
        }
        insert_client_journal_value(
          host.database,
          table,
          key,
          body,
          Some(operations),
        )
        .map(_ => ())
        .map_err(issue => Physical(issue))
      },
      reads=Some(operations.reads),
    )
    .map_err(issue => Journal(issue))
  })
}
