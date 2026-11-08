///|
// Exact metadata only. Response bytes and their admitted proof leaves remain
// in the existing encrypted Store. This journal row is neither a new outcome
// issuer nor permission to repeat a missing or unresolved physical call.
fn native_model_settlement_body(
  work : NativeClientMockModelWork,
  saved : NativeMockModelSettlement,
  authority : String,
  binding : String,
  entry_digest : String,
  maximum : Int,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(maximum, 48, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "attempt_cid")
    @encode.string_value(writer, saved.attempt_cid)
    @encode.key(writer, "entry_digest")
    @encode.string_value(writer, entry_digest)
    @encode.key(writer, "request_scope_cid")
    @encode.string_value(writer, @host.client_request_scope_cid(work.request))
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(work.definition),
    )
    @encode.key(writer, "scope_cid")
    @encode.string_value(writer, saved.scope_cid)
    @encode.key(writer, "store_binding")
    @encode.string_value(writer, binding)
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-native-model-call-settlement-original/0.1",
    )
    @encode.key(writer, "slot")
    @encode.number_value(writer, saved.slot.to_double())
    @encode.key(writer, "evidence")
    @encode.begin_array(writer)
    for original in saved.leaves {
      let role = @publication.run_evidence_value_name(original)
      guard @publication.model_scoped_private_holding_cid(
          work.definition,
          authority,
          saved.scope_cid,
          saved.slot_cid,
          saved.attempt_cid,
          1,
          "settled",
          role,
        )
        is Some(holding) else {
        return Err(ForeignRun)
      }
      @encode.begin_object(writer)
      @encode.key(writer, "cid")
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(original),
      )
      @encode.key(writer, "holding_cid")
      @encode.string_value(writer, holding)
      @encode.key(writer, "role")
      @encode.string_value(writer, role)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
/// Commit only after every original proof/response cell has confirmed. Keep
/// this original attempt sticky and the known COMMIT BEFORE returning Read;
/// a later current/return failure cannot erase that historical observation.
/// Existing/missing rows never grant an automatic save, resend or Model ACK.
pub fn NativeClientMockModelWork::commit_settlement_in_original_read(
  self : NativeClientMockModelWork,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    guard !self.closing &&
      !self.closed &&
      !self.advancing &&
      self.settlement is Some(saved) &&
      saved.store_complete &&
      saved.stored == saved.leaves.length() &&
      saved.store is Some(store) &&
      !saved.journal_attempted else {
      return Err(ForeignOriginal)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    saved.journal_attempted = true
    mock_model_require(
      self.capture
      .with_current_adoption_material_in_original_read((
        host,
        _material,
        operations,
      ) => {
        let (authority, device, inode) = match store.custody_location() {
          Ok(value) => value
          Err(issue) => return Err(Journal(PublicationObservation(issue)))
        }
        let binding = match
          installed_publication_binding(
            self.namespace_id,
            authority,
            device,
            inode,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Journal(issue))
        }
        let entry = match
          read_client_journal_value(
            host.database,
            "client_model_call_originals",
            saved.attempt_cid,
            Some(operations.reads),
          ) {
          Ok(value) if value.revision == 0L => value
          Ok(_) | Err(@sqlite.NotFound) => return Err(Journal(CustodyLost))
          Err(issue) => return Err(Journal(Physical(issue)))
        }
        // Actual immutable strings plus closed punctuation/longest Int.
        // A canonical holding/semantic digest has exactly 71 ASCII units.
        let fixed = "{\"attempt_cid\":\"\",\"entry_digest\":\"\",\"request_scope_cid\":\"\",\"run_definition_cid\":\"\",\"scope_cid\":\"\",\"store_binding\":\"\",\"slot\":2147483647,\"evidence\":[],\"version\":\"actql-native-model-call-settlement-original/0.1\"}"
          .length()
          .to_int64()
        let mut units = saved.attempt_cid.length().to_int64() +
          71L +
          @host.client_request_scope_cid(self.request).length().to_int64() +
          @publication.publication_contract_identity(self.definition)
          .length()
          .to_int64() +
          saved.scope_cid.length().to_int64() +
          binding.length().to_int64()
        for original in saved.leaves {
          units += @publication.run_evidence_value_name(original)
            .length()
            .to_int64() +
            142L
        }
        let syntax = fixed +
          saved.leaves.length().to_int64() *
          "{\"cid\":\"\",\"holding_cid\":\"\",\"role\":\"\"},"
          .length()
          .to_int64()
        guard @execution.checked_preparation_add_product(syntax, units, 6L)
          is Some(bound) &&
          bound > 0L &&
          bound < 2147483519L &&
          bound <= self.capture.max_snapshot_bytes else {
          return Err(Journal(CapacityExceeded))
        }
        // Both the expected original Entry and new metadata remain live until
        // Read returns. Fund their combined writer/parse/byte geometry first.
        match
          self.capture.prepare_model_entry_construction(
            Some(entry.body.length()),
            additional=Some((bound.to_int(), 48, 4)),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        let expected_entry = match
          native_model_entry_body(
            self.request,
            self.definition,
            saved.slot,
            saved.call,
            saved.leaves[0],
            saved.leaves[3],
            entry.body.length(),
          ) {
          Ok(value) => value
          Err(issue) => return Err(Journal(issue))
        }
        if entry.body != expected_entry {
          return Err(Journal(CustodyLost))
        }
        let body = match
          native_model_settlement_body(
            self,
            saved,
            authority,
            binding,
            "sha256:" + @sha.hex(entry.body),
            bound.to_int(),
          ) {
          Ok(value) => value
          Err(issue) => return Err(Journal(issue))
        }
        let committed = host.journal.transaction_with_reads(
          () => {
            let record = match
              host.journal.retained(self.request, reads=Some(operations.reads)) {
              Ok(Some(value)) => value
              Ok(None) => return Err(CustodyLost)
              Err(issue) => return Err(issue)
            }
            if !record.dispatch_reserved ||
              !record.physical_start_claimed ||
              record.effect_material_originals is None ||
              record.checkpoint is Some(_) ||
              record.publication_binding != Some(binding) ||
              @publication.publication_contract_identity(record.definition) !=
              @publication.publication_contract_identity(self.definition) {
              return Err(ForeignRun)
            }
            let usage = match
              read_client_journal_capacity(
                host.database,
                "client_model_call_originals",
                saved.scope_cid,
                Some(operations),
              ) {
              Ok(value) => value
              Err(@sqlite.NotFound) => return Err(CustodyLost)
              Err(issue) => return Err(Physical(issue))
            }
            if usage.reserved_objects != saved.slot.to_int64() * 2L + 1L {
              return Err(CustodyLost)
            }
            match
              reserve_client_journal_capacity(
                host.database,
                "client_model_call_originals",
                saved.scope_cid,
                body.length().to_int64(),
                1L,
                self.capture.max_snapshot_bytes,
                saved.count.to_int64() * 2L,
                Some(operations),
              ) {
              Ok(_) => ()
              Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
              Err(issue) => return Err(Physical(issue))
            }
            insert_client_journal_value(
              host.database,
              "client_model_call_settlements",
              saved.attempt_cid,
              body,
              Some(operations),
            )
            .map(_ => ())
            .map_err(issue => Physical(issue))
          },
          reads=Some(operations.reads),
        )
        match committed {
          Ok(_) => {
            saved.journal_recorded = true
            Ok(())
          }
          Err(issue) => Err(Journal(issue))
        }
      })
      .map_err(issue => NativeClientMockModelIssue::Original(issue)),
    )
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
/// Only back in the SAME original Model frame, after actual Store confirmation
/// and known original Journal COMMIT. Neither a CID, caller flag, terminal Run
/// state nor physical process exit can supply this acknowledgement.
pub fn NativeClientMockModelWork::acknowledge_saved_settlement(
  self : NativeClientMockModelWork,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    guard !self.closed &&
      !self.advancing &&
      self.settlement is Some(saved) &&
      saved.store_complete &&
      saved.journal_recorded else {
      return Err(ForeignOriginal)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    if saved.exporter is Some(exporter) {
      let retired = mock_model_require(
        @model.cleanup_model_capture_export(exporter).map_err(issue => {
          NativeClientMockModelIssue::Capture(issue)
        }),
      )
      if !retired {
        return Err(CleanupPending)
      }
      saved.exporter = None
    }
    if !@model.acknowledge_model_call_settlement(saved.original) {
      return Err(ForeignOriginal)
    }
    self.settlement = None
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}
