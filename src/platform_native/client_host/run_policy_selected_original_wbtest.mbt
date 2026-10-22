///|
// The selected WB runner reports only static API phases and closed variant
// names. Payloads, original rows, keys, wire, token and native stacks stay private.
fn[T, E] selected_policy_require(
  value : Result[T, E],
  phase : String,
  issue_kind : (E) -> String,
) -> T raise {
  match value {
    Ok(original) => original
    Err(issue) => fail("fixture phase=" + phase + " issue=" + issue_kind(issue))
  }
}

///|
fn selected_policy_environment() -> @checked.CheckEnvironment raise {
  match preparation_environment_original() {
    Some(original) => original
    None => fail("fixture phase=prepare_environment issue=Unavailable")
  }
}

///|
fn selected_policy_require_body(
  row : @sqlite.NativeJournalValue,
  request : @host.ClientRequestIdentity,
  cid : String,
) -> @publication.CapturedEffectDependencyBody raise {
  let (wire, comparison) = selected_policy_require(
    extract_run_policy_wire(row, request),
    "extract",
    selected_policy_journal_issue,
  )
  selected_policy_require(
    select_run_policy_wire(wire, comparison, cid),
    "select",
    selected_policy_journal_issue,
  )
}

///|
fn selected_policy_journal_issue(issue : NativeClientRunJournalIssue) -> String {
  match issue {
    CustodyLost => "CustodyLost"
    CapacityExceeded => "CapacityExceeded"
    AuthorizationDenied => "AuthorizationDenied"
    ChangedIntent => "ChangedIntent"
    ForeignRun => "ForeignRun"
    Fenced => "Fenced"
    TransactionUnknown => "TransactionUnknown"
    Encoding => "Encoding"
    Physical(_) => "Physical"
    Start(_) => "Start"
    Epoch(_) => "Epoch"
    InvalidSubmission => "InvalidSubmission"
    SubmissionReferenceUsed => "SubmissionReferenceUsed"
    NamedSubmission(_) => "NamedSubmission"
    SubmissionEpochRejected(_) => "SubmissionEpochRejected"
    UnsupportedPreparation => "UnsupportedPreparation"
    MissingEffectMaterialOriginal => "MissingEffectMaterialOriginal"
    ChangedEffectMaterialOriginal => "ChangedEffectMaterialOriginal"
    PublicationPolicy(_) => "PublicationPolicy"
    Checkpoint(_) => "Checkpoint"
    CancellationIdentity(_) => "CancellationIdentity"
    CancellationOperation(_) => "CancellationOperation"
    PublicationObservation(_) => "PublicationObservation"
    RunIdIndexIncomplete => "RunIdIndexIncomplete"
  }
}

///|
fn selected_policy_sqlite_issue(issue : @sqlite.NativeSqliteIssue) -> String {
  match issue {
    UnsupportedTarget => "UnsupportedTarget"
    InvalidName => "InvalidName"
    InvalidLimit => "InvalidLimit"
    LibraryLoad(_) => "LibraryLoad"
    DatabaseOpen(_) => "DatabaseOpen"
    DatabaseClosed => "DatabaseClosed"
    NotFound => "NotFound"
    Collision => "Collision"
    Busy => "Busy"
    BodyTooLarge => "BodyTooLarge"
    CapacityExceeded => "CapacityExceeded"
    Physical(_) => "Physical"
    OperationRoutingBefore(_) => "OperationRoutingBefore"
    OperationRoutingAfter(_, _) => "OperationRoutingAfter"
  }
}

///|
// Independent canonical Policy bytes/"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", hashed with Python SHA-256 during
// preparation. These tests are definitions until matching Native execution.
let selected_policy_fixture_wire : String = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"

///|
let selected_policy_fixture_cid : String = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"

///|
let selected_policy_fixture_packet : String = "{\"bodies\":[{\"body\":\"{\\\"classification\\\":\\\"unknown\\\",\\\"source_data_policy_cids\\\":[],\\\"source_response_policy_cids\\\":[],\\\"unknown_provenance\\\":true,\\\"version\\\":\\\"actql-effective-data-policy/0.1\\\"}\",\"cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\",\"kind\":\"data_policy\"}],\"root_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"}"

///|
// Preserve the original cryptographically correct but inadmissible public/no-
// provenance fixture as a refusal case. No Owner validation is relaxed.
let selected_policy_public_empty_packet : String = "{\"bodies\":[{\"body\":\"{\\\"classification\\\":\\\"public\\\",\\\"source_data_policy_cids\\\":[],\\\"source_response_policy_cids\\\":[],\\\"unknown_provenance\\\":false,\\\"version\\\":\\\"actql-effective-data-policy/0.1\\\"}\",\"cid\":\"sha256:07bc8284869020dcb3bcf14cfa9d23dac3e0dd571d983ac9b8271d1eabce8e42\",\"kind\":\"data_policy\"}],\"root_policy_cid\":\"sha256:07bc8284869020dcb3bcf14cfa9d23dac3e0dd571d983ac9b8271d1eabce8e42\"}"

///|
let selected_policy_public_empty_wire : String = "{\"classification\":\"public\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":false,\"version\":\"actql-effective-data-policy/0.1\"}"

///|
let selected_policy_public_empty_cid : String = "sha256:07bc8284869020dcb3bcf14cfa9d23dac3e0dd571d983ac9b8271d1eabce8e42"

///|
fn selected_policy_fixture_record() -> NativeClientRunRecord raise {
  let (request, _, _, definition) = journal_test_fixture_require(
    journal_test_run_result("selected-policy-request", "selected-policy-run"),
  )
  {
    request,
    definition,
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_requested: false,
    publication_binding: None,
    publication_policy_originals: Some(selected_policy_fixture_packet),
    effect_material_originals: None,
    local_run_policy_originals: None,
    run_observation_originals: None,
    observation_original: None,
    revision: 0L,
    checkpoint: None,
  }
}

///|
fn selected_policy_fixture_row(
  record : NativeClientRunRecord,
) -> @sqlite.NativeJournalValue raise {
  {
    body: selected_policy_require(
      run_record_body(record),
      "record_body",
      selected_policy_journal_issue,
    ),
    revision: record.revision,
  }
}

///|
fn selected_policy_from_fixture_row(
  row : @sqlite.NativeJournalValue,
  request : @host.ClientRequestIdentity,
  cid : String,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  let (wire, comparison) = match extract_run_policy_wire(row, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  select_run_policy_wire(wire, comparison, cid)
}

///|
test "wire-only lookup selects exact Policy without changing the ordinary row" {
  let original = selected_policy_fixture_record()
  let row = selected_policy_fixture_row(original)
  let body = selected_policy_require_body(
    row,
    original.request,
    selected_policy_fixture_cid,
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(body),
    selected_policy_fixture_wire,
  )
  assert_eq(
    @publication.captured_effect_dependency_body_cid(body),
    selected_policy_fixture_cid,
  )
  assert_eq(
    @publication.captured_effect_dependency_body_kind(body),
    "data_policy",
  )
  let restored = selected_policy_require(
    read_run_record(row),
    "read_record",
    selected_policy_journal_issue,
  )
  assert_eq(
    selected_policy_require(
      run_record_body(restored),
      "record_body",
      selected_policy_journal_issue,
    ),
    row.body,
  )
  assert_eq(restored.revision, 0L)
  assert_false(restored.physical_start_claimed)
  assert_false(restored.cancellation_requested)
}

///|
test "wire-only missing Policy refuses without repairing originals" {
  let record = selected_policy_fixture_record()
  assert_true(
    selected_policy_from_fixture_row(
      selected_policy_fixture_row(record),
      record.request,
      "sha256:" + "f".repeat(64),
    )
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  let absent = { ..record, publication_policy_originals: None, }
  let row = selected_policy_fixture_row(absent)
  assert_true(
    selected_policy_from_fixture_row(
      row,
      record.request,
      selected_policy_fixture_cid,
    )
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  let restored = selected_policy_require(
    read_run_record(row),
    "read_record",
    selected_policy_journal_issue,
  )
  assert_true(restored.publication_policy_originals is None)
  assert_eq(
    selected_policy_require(
      run_record_body(restored),
      "record_body",
      selected_policy_journal_issue,
    ),
    row.body,
  )
}

///|
test "wire-only selection validates malformed nonselected bodies and full dependencies" {
  let record = selected_policy_fixture_record()
  let extra = selected_policy_fixture_packet.replace(
    old="}],",
    new="},{\"body\":\"{}\",\"cid\":\"sha256:" +
      "f".repeat(64) +
      "\",\"kind\":\"data_policy\"}],",
  )
  for
    invalid in [
      extra,
      selected_policy_fixture_packet.replace(
        old="\"root_policy_cid\":\"" + selected_policy_fixture_cid,
        new="\"root_policy_cid\":\"sha256:" + "f".repeat(64),
      ),
      selected_policy_fixture_packet.replace(
        old="actql-effective-data-policy/0.1",
        new="actql-effective-data-policy/" + "99.1",
      ),
      "{\"bodies\":[{\"body\":\"{\\\"classification\\\":\\\"unknown\\\",\\\"source_data_policy_cids\\\":[\\\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\\\"],\\\"source_response_policy_cids\\\":[],\\\"unknown_provenance\\\":true,\\\"version\\\":\\\"actql-effective-data-policy/0.1\\\"}\",\"cid\":\"sha256:d1aba7f7812dd69b2f4283b234948716212ed28e8a83ff339de663ca8470dc50\",\"kind\":\"data_policy\"}],\"root_policy_cid\":\"sha256:d1aba7f7812dd69b2f4283b234948716212ed28e8a83ff339de663ca8470dc50\"}",
      " ".repeat(65537),
      "{}",
    ] {
    let row = selected_policy_fixture_row({
      ..record,
      publication_policy_originals: Some(invalid),
    })
    assert_true(
      selected_policy_from_fixture_row(
        row,
        record.request,
        selected_policy_fixture_cid,
      )
      is Err(CustodyLost),
    )
    assert_true(read_run_record(row) is Err(CustodyLost))
  }
}

///|
test "wire-only extraction rejects Effect Checkpoint and canonical damage" {
  let record = selected_policy_fixture_record()
  let bad_effect = { ..record, effect_material_originals: Some("{}"), }
  assert_true(
    extract_run_policy_wire(
      selected_policy_fixture_row(bad_effect),
      record.request,
    )
    is Err(CustodyLost),
  )
  let row = selected_policy_fixture_row(record)
  let wire = @utf8.decode(row.body) catch { _ => fail("original UTF8") }
  for
    invalid in [
      wire + " ",
      wire.replace(old="\"checkpoint\":null", new="\"checkpoint\":\"{}\""),
    ] {
    let damaged = { ..row, body: @utf8.encode(invalid), }
    assert_true(
      extract_run_policy_wire(damaged, record.request) is Err(CustodyLost),
    )
    assert_true(read_run_record(damaged) is Err(CustodyLost))
  }
}

///|
test "wire-only lookup leaves cancellation start and revision facts unchanged" {
  let original = {
    ..selected_policy_fixture_record(),
    dispatch_reserved: true,
    physical_start_claimed: true,
    cancellation_requested: true,
    revision: 7L,
  }
  let row = selected_policy_fixture_row(original)
  selected_policy_require_body(
    row,
    original.request,
    selected_policy_fixture_cid,
  )
  |> ignore
  let restored = selected_policy_require(
    read_run_record(row),
    "read_record",
    selected_policy_journal_issue,
  )
  assert_true(restored.dispatch_reserved)
  assert_true(restored.physical_start_claimed)
  assert_true(restored.cancellation_requested)
  assert_eq(restored.revision, 7L)
  assert_eq(
    selected_policy_require(
      run_record_body(restored),
      "record_body",
      selected_policy_journal_issue,
    ),
    row.body,
  )
}

///|
test "wire-only lookup defers ChangedIntent until complete Policy validation" {
  let database = epoch_test_database("selected-policy-identity")
  selected_policy_require(
    initialize_native_client_run_journal(database),
    "initialize_journal",
    selected_policy_journal_issue,
  )
  let journal = selected_policy_require(
    open_native_client_run_journal(database, 8),
    "open_journal",
    selected_policy_journal_issue,
  )
  let (request, prepared, compiled, definition) = journal_test_fixture_require(
    journal_test_run_result("selected-policy-request", "selected-policy-run"),
  )
  let record = selected_policy_require(
    journal.bind_run(request, prepared, compiled, definition, true),
    "bind_run",
    selected_policy_journal_issue,
  )
  selected_policy_require(
    journal.transaction(() => {
      journal.save({
        ..record,
        publication_policy_originals: Some(selected_policy_fixture_packet),
      })
    }),
    "save_row",
    selected_policy_journal_issue,
  )
  |> ignore
  let before = selected_policy_require(
    database.read("client_runs", @host.client_request_scope_cid(request)),
    "database_read_before",
    selected_policy_sqlite_issue,
  )
  let changed = selected_policy_require(
    @host.prepare_effect_free_client_program(
      preparation_values_document().replace(old="{\"id\":1}", new="{\"id\":3}"),
      Json,
      selected_policy_environment(),
      None,
      @host.client_standard_program_preparation_limits(),
    ),
    "prepare_changed",
    journal_test_preparation_issue,
  )
  let changed_request = selected_policy_require(
    @host.prepare_source_free_client_request_identity(
      changed,
      "sha256:" + "a".repeat(64),
      "selected-policy-request",
    ),
    "request_changed",
    journal_test_request_issue,
  )
  let (wire, comparison) = selected_policy_require(
    journal.retained_policy_wire(changed_request),
    "retained_wire",
    selected_policy_journal_issue,
  )
  assert_true(comparison is ChangedOriginalIntent)
  assert_true(
    select_run_policy_wire(wire, comparison, selected_policy_fixture_cid)
    is Err(ChangedIntent),
  )
  assert_true(journal.retained(changed_request) is Err(ChangedIntent))
  let after = selected_policy_require(
    database.read("client_runs", @host.client_request_scope_cid(request)),
    "database_read_after",
    selected_policy_sqlite_issue,
  )
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  selected_policy_require(
    database.close_checked(),
    "database_close",
    selected_policy_sqlite_issue,
  )
}

///|
test "deferred identity keeps malformed Policy priority and missing wire identity order" {
  for
    comparison in [
      OriginalRequest,
      ChangedOriginalIntent,
      ForeignOriginalRequest,
    ] {
    assert_true(
      select_run_policy_wire(
        Some("{}"),
        comparison,
        selected_policy_fixture_cid,
      )
      is Err(CustodyLost),
    )
  }
  assert_true(
    select_run_policy_wire(
      Some(selected_policy_fixture_packet),
      ChangedOriginalIntent,
      selected_policy_fixture_cid,
    )
    is Err(ChangedIntent),
  )
  assert_true(
    select_run_policy_wire(
      None,
      ChangedOriginalIntent,
      selected_policy_fixture_cid,
    )
    is Err(ChangedIntent),
  )
  assert_true(
    select_run_policy_wire(
      None,
      ForeignOriginalRequest,
      selected_policy_fixture_cid,
    )
    is Err(CustodyLost),
  )
  assert_true(
    select_run_policy_wire(None, OriginalRequest, selected_policy_fixture_cid)
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
}

///|
test "changed work row after normal custody cannot bypass malformed Policy" {
  let initial = selected_policy_fixture_record()
  let row = selected_policy_fixture_row(initial)
  selected_policy_require(
    read_run_record(row),
    "read_record_initial",
    selected_policy_journal_issue,
  )
  |> ignore
  let changed = selected_policy_require(
    @host.prepare_effect_free_client_program(
      preparation_values_document().replace(old="{\"id\":1}", new="{\"id\":3}"),
      Json,
      selected_policy_environment(),
      None,
      @host.client_standard_program_preparation_limits(),
    ),
    "prepare_changed",
    journal_test_preparation_issue,
  )
  let changed_request = selected_policy_require(
    @host.prepare_source_free_client_request_identity(
      changed,
      "sha256:" + "a".repeat(64),
      "selected-policy-request",
    ),
    "request_changed",
    journal_test_request_issue,
  )
  // Models a different row supplied after current2; no original database mutation.
  let damaged_row = selected_policy_fixture_row({
    ..initial,
    publication_policy_originals: Some("{}"),
  })
  let (wire, comparison) = selected_policy_require(
    extract_run_policy_wire(damaged_row, changed_request),
    "extract_changed",
    selected_policy_journal_issue,
  )
  assert_true(comparison is ChangedOriginalIntent)
  assert_true(
    select_run_policy_wire(wire, comparison, selected_policy_fixture_cid)
    is Err(CustodyLost),
  )
  assert_true(read_run_record(damaged_row) is Err(CustodyLost))
}

///|
test "public empty provenance Policy refuses despite its exact original CID" {
  assert_true(
    @publication.admit_captured_effect_dependency_body(
      "data_policy",
      Some(selected_policy_public_empty_cid),
      selected_policy_public_empty_wire,
      65536,
      8192,
      64,
    )
    is Err(@publication.InvalidBody),
  )
  assert_true(
    read_run_policy_originals(selected_policy_public_empty_packet)
    is Err(CustodyLost),
  )
  let record = selected_policy_fixture_record()
  let row = selected_policy_fixture_row({
    ..record,
    publication_policy_originals: Some(selected_policy_public_empty_packet),
  })
  assert_true(read_run_record(row) is Err(CustodyLost))
  assert_true(
    selected_policy_from_fixture_row(
      row,
      record.request,
      selected_policy_public_empty_cid,
    )
    is Err(CustodyLost),
  )
}
