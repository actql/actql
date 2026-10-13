///|
// Independent canonical Policy bytes/"sha256:07bc8284869020dcb3bcf14cfa9d23dac3e0dd571d983ac9b8271d1eabce8e42", hashed with Python SHA-256 during
// preparation. These tests are definitions until matching Native execution.
let selected_policy_fixture_wire : String = "{\"classification\":\"public\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":false,\"version\":\"actql-effective-data-policy/0.1\"}"

///|
let selected_policy_fixture_cid : String = "sha256:07bc8284869020dcb3bcf14cfa9d23dac3e0dd571d983ac9b8271d1eabce8e42"

///|
let selected_policy_fixture_packet : String = "{\"bodies\":[{\"body\":\"{\\\"classification\\\":\\\"public\\\",\\\"source_data_policy_cids\\\":[],\\\"source_response_policy_cids\\\":[],\\\"unknown_provenance\\\":false,\\\"version\\\":\\\"actql-effective-data-policy/0.1\\\"}\",\"cid\":\"sha256:07bc8284869020dcb3bcf14cfa9d23dac3e0dd571d983ac9b8271d1eabce8e42\",\"kind\":\"data_policy\"}],\"root_policy_cid\":\"sha256:07bc8284869020dcb3bcf14cfa9d23dac3e0dd571d983ac9b8271d1eabce8e42\"}"

///|
fn selected_policy_fixture_record() -> NativeClientRunRecord {
  let (request, _, _, definition) = journal_test_run(
    "selected-policy-request", "selected-policy-run",
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
    revision: 0L,
    checkpoint: None,
  }
}

///|
fn selected_policy_fixture_row(
  record : NativeClientRunRecord,
) -> @sqlite.NativeJournalValue {
  { body: run_record_body(record).unwrap(), revision: record.revision, }
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
  let body = selected_policy_from_fixture_row(
    row,
    original.request,
    selected_policy_fixture_cid,
  ).unwrap()
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
  let restored = read_run_record(row).unwrap()
  assert_eq(run_record_body(restored).unwrap(), row.body)
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
  let restored = read_run_record(row).unwrap()
  assert_true(restored.publication_policy_originals is None)
  assert_eq(run_record_body(restored).unwrap(), row.body)
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
        new="actql-effective-data-policy/99.1",
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
  selected_policy_from_fixture_row(
    row,
    original.request,
    selected_policy_fixture_cid,
  ).unwrap()
  |> ignore
  let restored = read_run_record(row).unwrap()
  assert_true(restored.dispatch_reserved)
  assert_true(restored.physical_start_claimed)
  assert_true(restored.cancellation_requested)
  assert_eq(restored.revision, 7L)
  assert_eq(run_record_body(restored).unwrap(), row.body)
}

///|
test "wire-only lookup defers ChangedIntent until complete Policy validation" {
  let database = epoch_test_database("selected-policy-identity")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "selected-policy-request", "selected-policy-run",
  )
  let record = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  journal
  .save({
    ..record,
    publication_policy_originals: Some(selected_policy_fixture_packet),
  })
  .unwrap()
  |> ignore
  let before = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  let changed = @host.prepare_effect_free_client_program(
    preparation_values_document().replace(old="{\"id\":1}", new="{\"id\":3}"),
    Json,
    preparation_environment(),
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let changed_request = @host.prepare_source_free_client_request_identity(
    changed,
    "sha256:" + "a".repeat(64),
    "selected-policy-request",
  ).unwrap()
  let (wire, comparison) = journal
    .retained_policy_wire(changed_request)
    .unwrap()
  assert_true(comparison is ChangedOriginalIntent)
  assert_true(
    select_run_policy_wire(wire, comparison, selected_policy_fixture_cid)
    is Err(ChangedIntent),
  )
  assert_true(journal.retained(changed_request) is Err(ChangedIntent))
  let after = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  database.close_checked().unwrap()
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
  read_run_record(row).unwrap() |> ignore
  let changed = @host.prepare_effect_free_client_program(
    preparation_values_document().replace(old="{\"id\":1}", new="{\"id\":3}"),
    Json,
    preparation_environment(),
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let changed_request = @host.prepare_source_free_client_request_identity(
    changed,
    "sha256:" + "a".repeat(64),
    "selected-policy-request",
  ).unwrap()
  // Models a different row supplied after current2; no original database mutation.
  let damaged_row = selected_policy_fixture_row({
    ..initial,
    publication_policy_originals: Some("{}"),
  })
  let (wire, comparison) = extract_run_policy_wire(damaged_row, changed_request).unwrap()
  assert_true(comparison is ChangedOriginalIntent)
  assert_true(
    select_run_policy_wire(wire, comparison, selected_policy_fixture_cid)
    is Err(CustodyLost),
  )
  assert_true(read_run_record(damaged_row) is Err(CustodyLost))
}
