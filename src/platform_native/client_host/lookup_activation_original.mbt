///|
// One original's persistence observation in the existing Work/Journal, not a
// Source, Ledger, cleanup owner or issuer. Retained BEFORE first fallible I/O.
priv struct NativeMockLookupJournalEntry {
  slot_cid : String
  mut _retained_original : @host.ClientKeyedNativeActivation?
  mut attempted : Bool
  mut recorded : Bool
}

///|
fn native_lookup_activation_body(
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  original : @host.ClientKeyedNativeActivation,
  bound : Int,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(bound, 15, 2)
    @encode.begin_object(writer)
    for
      (name, contract) in [
        ("activation", original.activation),
        ("batch_plan", original.batch),
        ("call_slot", original.slot),
        ("key_set", original.keys),
        ("request", original.semantic_request),
        ("transport", original.transport),
      ] {
      @encode.key(writer, name)
      @encode.string_value(
        writer,
        @publication.publication_contract_json(contract),
      )
    }
    @encode.key(writer, "request_scope_cid")
    @encode.string_value(writer, @host.client_request_scope_cid(request))
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(definition),
    )
    for
      (name, value) in [
        ("batch_index", original.batch_index.to_int64()),
        ("batch_count", original.batch_count.to_int64()),
        ("reserved_wire_bytes", original.reserved_wire_bytes),
        ("reserved_decoded_bytes", original.reserved_decoded_bytes),
        ("reserved_duration_ms", original.reserved_duration_ms),
      ] {
      @encode.key(writer, name)
      @encode.number_value(writer, value.to_double())
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-lookup-activation-original/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
/// Persist only this original accepted Run's selected first Native attempt.
/// The same captured Read, epoch and Journal transaction own currentness and
/// capacity. Existing or ambiguous entries never authorize another dispatch.
/// Successful COMMIT is retained before any fallible return/current boundary;
/// even that historical observation is not current Source permission or ACK.
pub fn NativeClientMockModelWork::persist_lookup_activation_in_original_read(
  self : Self,
  original : @host.ClientKeyedNativeActivation,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.first_start is Some(_) &&
    self.lookup_entries is Some(entries) else {
    return Err(ForeignOriginal)
  }
  for entry in entries {
    if entry.slot_cid ==
      @publication.publication_contract_identity(original.slot) {
      return Err(ForeignOriginal)
    }
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  // Exact punctuation/field names and the longest admitted scalar spellings;
  // only the eight original Strings below need JSON escape expansion.
  let fixed = "{\"activation\":\"\",\"batch_plan\":\"\",\"call_slot\":\"\",\"key_set\":\"\",\"request\":\"\",\"transport\":\"\",\"request_scope_cid\":\"\",\"run_definition_cid\":\"\",\"batch_index\":2147483647,\"batch_count\":2147483647,\"reserved_wire_bytes\":9007199254740991,\"reserved_decoded_bytes\":9007199254740991,\"reserved_duration_ms\":9007199254740991,\"version\":\"actql-native-lookup-activation-original/0.1\"}"
    .length()
    .to_int64()
  let units = @host.client_request_scope_cid(self.request).length().to_int64() +
    @publication.publication_contract_identity(self.definition)
    .length()
    .to_int64() +
    @publication.publication_contract_json(original.activation)
    .length()
    .to_int64() +
    @publication.publication_contract_json(original.batch).length().to_int64() +
    @publication.publication_contract_json(original.slot).length().to_int64() +
    @publication.publication_contract_json(original.keys).length().to_int64() +
    @publication.publication_contract_json(original.semantic_request)
    .length()
    .to_int64() +
    @publication.publication_contract_json(original.transport)
    .length()
    .to_int64()
  guard @execution.checked_preparation_add_product(fixed, units, 6L)
    is Some(bound) &&
    bound > 0L &&
    bound < 2147483519L &&
    bound <= self.capture.max_snapshot_bytes &&
    @execution.preparation_array_representation(
      1L,
      entries.length().to_int64() + 1L,
      true,
    )
    is Some(array) &&
    @execution.preparation_array_representation(2L, 11L, false) is Some(fields) &&
    @execution.compose_preparation_representation([
      array,
      fields,
      {
        // Entry H1/R2/W2 plus original Some H1/R1/W1, six (name,contract)
        // and five (name,count) pairs,
        // and current-Read (3Refs+bound Int) / transaction (9Refs) closures.
        // Both final scope/key Strings and their concatenation intermediates.
        record_headers: 19L,
        reference_slots: 32L,
        scalar_words: 11L,
        owned_utf16_units: 4L *
        @publication.publication_contract_identity(self.definition)
        .length()
        .to_int64() +
        4L +
        @publication.publication_contract_identity(original.batch)
        .length()
        .to_int64() +
        @publication.publication_contract_identity(original.slot)
        .length()
        .to_int64(),
        owned_wire_bytes: 0L,
      },
    ])
    is Some(controls) else {
    return Err(Encoding)
  }
  match
    self.capture.prepare_model_entry_construction(
      Some(bound.to_int()),
      nodes=15,
      additional_controls=Some(controls),
    ) {
    Err(issue) => return Err(Original(issue))
    Ok(_) => ()
  }
  let entry = {
    slot_cid: @publication.publication_contract_identity(original.slot),
    _retained_original: Some(original),
    attempted: false,
    recorded: false,
  }
  entries.push(entry)
  let result = self.capture.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    guard !self.closing &&
      !self.closed &&
      original.issuer_id == host.adoption_cid() &&
      @host.client_keyed_native_activation_matches(
        original,
        self.request,
        self.compiled,
        self.definition,
        self.graph,
      ) &&
      @values.timestamp_epoch_milliseconds((self.current_time)()) is Some(now) &&
      now < original.deadline_epoch_ms &&
      !self.closing &&
      !self.closed else {
      return Err(Journal(ForeignRun))
    }
    let body = match
      native_lookup_activation_body(
        self.request,
        self.definition,
        original,
        bound.to_int(),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    let table = "client_lookup_activation_originals"
    let run = @publication.publication_contract_identity(self.definition)
    let scope = run +
      ":" +
      @publication.publication_contract_identity(original.batch)
    let key = run +
      ":" +
      @publication.publication_contract_identity(original.slot)
    let result = host.journal.transaction_with_reads(
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
          @publication.publication_contract_identity(record.definition) != run ||
          !@host.client_keyed_native_activation_matches(
            original,
            self.request,
            self.compiled,
            self.definition,
            self.graph,
          ) {
          return Err(ForeignRun)
        }
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
          Err(@sqlite.NotFound) if original.batch_index == 0 =>
            { reserved_bytes: 0L, reserved_objects: 0L, }
          Err(@sqlite.NotFound) => return Err(CustodyLost)
          Err(issue) => return Err(Physical(issue))
        }
        if original.batch_count < 1 ||
          original.batch_index < 0 ||
          original.batch_index >= original.batch_count ||
          usage.reserved_objects != original.batch_index.to_int64() {
          return Err(CustodyLost)
        }
        // Pure correspondence/read refusals above have attempted no mutation.
        // Retain uncertainty before entering the first fallible durable write.
        entry.attempted = true
        match
          reserve_client_journal_capacity(
            host.database,
            table,
            scope,
            body.length().to_int64(),
            1L,
            self.capture.max_snapshot_bytes,
            original.batch_count.to_int64(),
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
    // Keep a known COMMIT even if the following Read/current return fails.
    if result is Ok(_) {
      entry.recorded = true
      // The durable original is now in the Journal. Do not retain the whole
      // lookup/Request graph past its own payload retirement through this
      // persistence observation. An uncertain transaction keeps that original.
      entry._retained_original = None
    }
    result.map_err(issue => Journal(issue))
  })
  result.map_err(issue => Original(issue))
}
