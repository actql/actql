///|
// Exact immutable metadata and actual logical preimages, not a second
// serializer of Source rows or a copied Request. No physical success is inferred.
fn native_lookup_page_body(
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  page : @host.ClientKeyedNativeCapturedPage,
  bound : Int,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(bound, 9, 2)
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("adoption", @publication.publication_contract_json(page.adoption)),
        ("event", @publication.publication_contract_json(page.event)),
        ("raw", @publication.publication_contract_json(page.raw)),
        ("page_value_wire", page.body),
        ("page_schema_wire", page.schema_wire),
        ("request_scope_cid", @host.client_request_scope_cid(request)),
        (
          "run_definition_cid",
          @publication.publication_contract_identity(definition),
        ),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-lookup-page-original/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
/// Persist ONE captured page under the SAME original activation, Run and
/// captured Journal Read. Only the actual Native Source can retain/match this
/// page original; a separately sealed JSON envelope does not enter this path.
pub fn NativeClientMockModelWork::persist_lookup_page_in_original_read(
  self : Self,
  source : @row_file.NativeRelationFileCapture,
  page : @host.ClientKeyedNativeCapturedPage,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.first_start is Some(_) &&
    self.lookup_entries is Some(entries) &&
    entries.get(page.batch_index) is Some(entry) &&
    entry.slot_cid == page.call_slot_cid &&
    entry.recorded &&
    !entry.page_attempted &&
    !entry.page_recorded &&
    entry._retained_page is None &&
    entry.activation_body is Some(activation_body) &&
    entry.activation_revision is Some(activation_revision) else {
    return Err(ForeignOriginal)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let fixed = "{\"adoption\":\"\",\"event\":\"\",\"raw\":\"\",\"page_value_wire\":\"\",\"page_schema_wire\":\"\",\"request_scope_cid\":\"\",\"run_definition_cid\":\"\",\"version\":\"actql-native-lookup-page-original/0.1\"}"
    .length()
    .to_int64()
  let units = @publication.publication_contract_json(page.adoption)
    .length()
    .to_int64() +
    @publication.publication_contract_json(page.event).length().to_int64() +
    @publication.publication_contract_json(page.raw).length().to_int64() +
    page.body.length().to_int64() +
    page.schema_wire.length().to_int64() +
    @host.client_request_scope_cid(self.request).length().to_int64() +
    @publication.publication_contract_identity(self.definition)
    .length()
    .to_int64()
  guard @execution.checked_preparation_add_product(fixed, units, 6L)
    is Some(bound) &&
    bound > 0L &&
    bound < 2147483519L &&
    bound <= self.capture.max_snapshot_bytes &&
    @execution.preparation_array_representation(2L, 7L, false) is Some(fields) &&
    @execution.compose_preparation_representation([
      fields,
      {
        // Original page Some H1/R1/W1; seven name/text pairs; current-Read
        // closure5R1W and transaction closure11R. Actual retained activation
        // Bytes coexist with the Journal read and encoded page below.
        record_headers: 11L,
        reference_slots: 31L,
        scalar_words: 2L,
        owned_utf16_units: 4L *
        @publication.publication_contract_identity(self.definition)
        .length()
        .to_int64() +
        4L +
        page.batch_plan_cid.length().to_int64() +
        page.call_slot_cid.length().to_int64(),
        owned_wire_bytes: activation_body.length().to_int64(),
      },
    ])
    is Some(controls) else {
    return Err(Encoding)
  }
  match
    self.capture.prepare_model_entry_construction(
      Some(bound.to_int()),
      nodes=9,
      additional=Some((activation_body.length(), 15, 2)),
      additional_controls=Some(controls),
    ) {
    Err(issue) => return Err(Original(issue))
    Ok(_) => ()
  }
  guard !self.closing &&
    !self.closed &&
    !entry.page_attempted &&
    !entry.page_recorded &&
    entry._retained_page is None else {
    return Err(ForeignOriginal)
  }
  // Retain this original before entering any fallible durable operation.
  entry._retained_page = Some(page)
  let result = self.capture.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    guard !self.closing &&
      !self.closed &&
      source.keyed_captured_page_matches(
        page,
        self.request,
        self.compiled,
        self.definition,
        self.graph,
      ) else {
      return Err(Journal(ForeignRun))
    }
    let body = match
      native_lookup_page_body(
        self.request,
        self.definition,
        page,
        bound.to_int(),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    let run = @publication.publication_contract_identity(self.definition)
    let key = run + ":" + page.call_slot_cid
    let scope = run + ":" + page.batch_plan_cid
    let table = "client_lookup_page_originals"
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
          @publication.publication_contract_identity(record.definition) != run {
          return Err(ForeignRun)
        }
        let stored_activation = match
          read_client_journal_value(
            host.database,
            "client_lookup_activation_originals",
            key,
            Some(operations.reads),
          ) {
          Ok(value) => value
          Err(@sqlite.NotFound) => return Err(CustodyLost)
          Err(issue) => return Err(Physical(issue))
        }
        if stored_activation.revision != activation_revision ||
          stored_activation.body != activation_body {
          return Err(CustodyLost)
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
          Err(@sqlite.NotFound) if page.batch_index == 0 =>
            { reserved_bytes: 0L, reserved_objects: 0L, }
          Err(@sqlite.NotFound) => return Err(CustodyLost)
          Err(issue) => return Err(Physical(issue))
        }
        if usage.reserved_objects != page.batch_index.to_int64() ||
          !source.keyed_captured_page_matches(
            page,
            self.request,
            self.compiled,
            self.definition,
            self.graph,
          ) {
          return Err(ForeignRun)
        }
        // Clock is external too. Check its actual fixed activation deadline at
        // the mutation boundary, then retain the same pure Source association.
        guard @values.timestamp_epoch_milliseconds((self.current_time)())
          is Some(now) &&
          now < page.deadline_epoch_ms &&
          source.keyed_captured_page_matches(
            page,
            self.request,
            self.compiled,
            self.definition,
            self.graph,
          ) else {
          return Err(ForeignRun)
        }
        // Any failed/ambiguous mutation now remains on this SAME entry. It
        // cannot become a retry, a second adoption or physical cleanup ACK.
        entry.page_attempted = true
        match
          reserve_client_journal_capacity(
            host.database,
            table,
            scope,
            body.length().to_int64(),
            1L,
            self.capture.max_snapshot_bytes,
            entries.length().to_int64(),
            Some(operations),
          ) {
          Ok(_) => ()
          Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
          Err(issue) => return Err(Physical(issue))
        }
        if !source.keyed_captured_page_matches(
            page,
            self.request,
            self.compiled,
            self.definition,
            self.graph,
          ) {
          return Err(ForeignRun)
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
    // Retain known COMMIT before the outer Read/current return can fail.
    if result is Ok(_) {
      entry.page_recorded = true
      entry.activation_body = None
      entry._retained_page = None
    }
    result.map_err(issue => Journal(issue))
  })
  result.map_err(issue => Original(issue))
}
