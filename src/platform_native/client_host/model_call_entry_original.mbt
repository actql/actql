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
  dependency? : NativeModelEntryDependency? = None,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  guard native_model_entry_dependency_geometry(dependency)
    is Some((_, nodes, depth)) else {
    return Err(CapacityExceeded)
  }
  try {
    let writer = @encode.writer(maximum, nodes, depth)
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
    if dependency is Some(original) {
      @encode.key(writer, "dependency")
      emit_native_model_entry_dependency(writer, original)
    }
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
    @encode.string_value(
      writer,
      if dependency is Some(_) {
        native_dependent_model_entry_version
      } else {
        native_plain_model_entry_version
      },
    )
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
// Select the durable prerequisites from the trusted installed Work. The
// Portable uses the compiled Result policy and Store binding. A Source-backed
// Model must also carry the admitted Whole tuple on its original Execution.
// The Mock Effect path retains its existing material requirement.
fn NativeClientMockModelWork::matches_model_call_journal_run(
  self : Self,
  record : NativeClientRunRecord,
) -> Bool {
  if !record.dispatch_reserved ||
    !record.physical_start_claimed ||
    @host.client_request_identity_relation(record.request, self.request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(record.definition) !=
    @publication.publication_contract_identity(self.definition) {
    return false
  }
  match self.provider_role {
    Mock(_) => record.effect_material_originals is Some(_)
    PortableHttp(_) => {
      guard record.checkpoint is None &&
        record.publication_policy_originals is Some(_) &&
        record.publication_binding is Some(_) else {
        return false
      }
      let effect = record.effect_material_originals is Some(_)
      let compilation = match self.compiled.compilation {
        @host.Tasks(original) if !effect &&
          @host.client_compiled_run_has_original_definition(
            self.compiled,
            self.definition,
          ) => original
        @host.Effects(allowed) if effect => allowed.compilation.compiled
        _ => return false
      }
      guard compilation.serialization is None else { return false }
      for plan in compilation.infers {
        if physical_equal(plan, self.graph) {
          return if effect ||
            @host.prepared_client_has_checked_sources(compilation.owner) {
            self.active is Some(active) &&
            @infer.original_whole_model_journal_matches(
              active,
              self.graph,
              self.compiled,
              self.definition,
            )
          } else {
            @host.prepared_client_acquisition_count(compilation.owner) == 0
          }
        }
      }
      false
    }
  }
}

///|
/// Persist the exact original entry for the installed single-attempt Model.
/// This observes durable entry only: it neither acknowledges Core nor
/// supplies current dispatch permission. The caller retains the committed
/// outcome BEFORE returning the captured Read, then issues Core's same-entry
/// saved acknowledgement only back inside its original Model execution frame.
/// Existing/ambiguous entries never imply a new save or resend permission.
fn NativeClientMockModelWork::persist_model_entry_original(
  self : Self,
  prepared : @model.ModelPreparedCallSet,
  admission : @host.ClientInferDispatchAdmission,
  entry : @model.ModelCallEntry,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  let request = self.request
  let compiled = self.compiled
  let definition = self.definition
  let capture = self.capture
  match capture.prepare_model_entry_construction(None) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // The clock may reenter. Read the original Account and Run after it returns.
  let dependency_at = if self.provider_role is PortableHttp(http) &&
    http.installation.run_policy.egress is NativeEgressPending(_) {
    Some((self.current_time)())
  } else {
    None
  }
  capture
  .with_current_adoption_material_in_original_read((host, material, operations) => {
    guard self.model_output_dependency_scope_current() &&
      @host.client_infer_dispatch_matches_run(admission, compiled, definition) &&
      @model.model_call_entry_persistence_originals(entry, prepared, admission)
      is Some((count, slot, call, attempt, authority, model_scope)) &&
      count > 0 &&
      slot >= 0 &&
      slot < count else {
      return Err(Journal(ForeignRun))
    }
    let scope = @publication.model_invocation_scope_cid(model_scope)
    let dependency = match self.model_entry_dependency(scope) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    if dependency is Some(_) {
      guard dependency_at is Some(at) else { return Err(Journal(ForeignRun)) }
      let current = match
        @host.client_local_adopted_current_account(material, host.database) {
        Ok(value) => value
        Err(issue) => return Err(local_current_material_issue(issue))
      }
      if self.closing ||
        self.closed ||
        !self.model_output_dependency_scope_current() ||
        !self.model_output_dependency_issuers_current(current, at) {
        return Err(Journal(ForeignRun))
      }
    }
    guard native_model_entry_dependency_geometry(dependency)
      is Some((extra, nodes, depth)) else {
      return Err(Journal(CapacityExceeded))
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
    guard @execution.checked_preparation_add_product(fixed + extra, units, 6L)
      is Some(bound) &&
      bound > 0L &&
      bound < 2147483519L &&
      bound <= capture.max_snapshot_bytes else {
      return Err(Journal(CapacityExceeded))
    }
    let checked_store = self.provider_role is PortableHttp(_)
    let store_writer = if checked_store { Some((4096, 8, 2)) } else { None }
    let store_controls : @execution.PreparationRepresentationUnits? = if checked_store {
      Some({
        record_headers: 3L,
        reference_slots: 8L,
        scalar_words: 2L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
    } else {
      None
    }
    match
      capture.prepare_model_entry_construction(
        Some(bound.to_int()),
        nodes~,
        depth~,
        additional=store_writer,
        additional_controls=store_controls,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    // Check the same physical Store as the later settlement, outside of the
    // SQLite transaction. The retained binding only compares inside it.
    let expected_store = match self.provider_role {
      Mock(_) => None
      PortableHttp(http) => {
        let (authority, device, inode) = match http.store.custody_location() {
          Ok(value) => value
          Err(issue) => return Err(Journal(PublicationObservation(issue)))
        }
        match
          installed_publication_binding(
            self.namespace_id,
            authority,
            device,
            inode,
          ) {
          Ok(value) => Some(value)
          Err(issue) => return Err(Journal(issue))
        }
      }
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
        dependency~,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    let table = "client_model_call_originals"
    let key = @publication.run_evidence_value_identity(attempt)
    let dependent_original = if dependency is Some(_) {
      guard self.provider_role is PortableHttp(receiver) &&
        receiver.dependencies is Some(staged) &&
        staged.scope is Some((_, bound)) &&
        physical_equal(bound, model_scope) else {
        return Err(Journal(ForeignRun))
      }
      match fund_native_saved_model_selection(operations.reads) {
        Ok(_) => ()
        Err(issue) => return Err(Journal(issue))
      }
      let proof : NativeDependentModelEnteredOriginal = {
        entry,
        scope: model_scope,
        attempt_cid: key,
        entry_digest: "sha256:" + @sha.hex(body),
        extent: body.length().to_int64(),
      }
      Some((staged, proof))
    } else {
      None
    }
    host.journal
    .transaction_with_reads(
      () => {
        let record = match
          host.journal.retained(request, reads=Some(operations.reads)) {
          Ok(Some(value)) => value
          Ok(None) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        if !self.model_output_dependency_scope_current() ||
          !self.matches_model_call_journal_run(record) ||
          (
            expected_store is Some(binding) &&
            record.publication_binding != Some(binding)
          ) ||
          record.checkpoint is Some(_) ||
          (
            self.provider_role is PortableHttp(_) &&
            record.cancellation_requested
          ) {
          return Err(ForeignRun)
        }
        if dependency is Some(_) {
          match host.journal.recheck_model_run_cut(request, operations.reads) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
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
        // The original Model component enters its finite slots in order.
        // Lost counters, another entry for a past slot and reentry cannot renew
        // consumed calls or recreate accounting from absent metadata.
        if usage.reserved_objects != slot.to_int64() * 2L ||
          usage.reserved_objects >= count.to_int64() * 2L {
          return Err(CustodyLost)
        }
        // This is the selected invocation scope's finite journal byte bound,
        // not a namespace-wide history ceiling, memory grant or extra limit.
        // Each checked single-attempt Slot has one Entry and one eventual
        // settlement row. They share this SAME byte/object census; a later
        // Slot cannot start before the preceding settlement was saved.
        match
          grow_client_journal_key_capacity(
            host.database,
            table,
            scope,
            usage,
            body.length().to_int64(),
            1L,
            capture.max_snapshot_bytes,
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
        .map(_ => dependent_original)
        .map_err(issue => Physical(issue))
      },
      reads=Some(operations.reads),
    )
    .map_err(issue => Journal(issue))
  })
  .map(original => {
    if original is Some((staged, proof)) {
      staged.entered = Some(proof)
    }
  })
}
