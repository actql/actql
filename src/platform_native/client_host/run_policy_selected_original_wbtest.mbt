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
test "selected original Policy reuses one complete decode without changing the row" {
  let row = selected_policy_fixture_row(selected_policy_fixture_record())
  let (record, selected) = read_run_record_with_selected_policy(
    row,
    Some(selected_policy_fixture_cid),
  ).unwrap()
  let body = selected.unwrap()
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
  assert_eq(run_record_body(record).unwrap(), row.body)
  assert_eq(record.revision, 0L)
  assert_false(record.physical_start_claimed)
  assert_false(record.cancellation_requested)
  let (unselected, none) = read_run_record_with_selected_policy(row, None).unwrap()
  assert_true(none is None)
  assert_eq(run_record_body(unselected).unwrap(), row.body)
  assert_eq(run_record_body(read_run_record(row).unwrap()).unwrap(), row.body)
}

///|
test "missing selected Policy stays absent and does not repair old originals" {
  let record = selected_policy_fixture_record()
  let row = selected_policy_fixture_row(record)
  let (_, missing) = read_run_record_with_selected_policy(
    row,
    Some("sha256:" + "f".repeat(64)),
  ).unwrap()
  assert_true(missing is None)
  let absent = { ..record, publication_policy_originals: None, }
  let old_row = selected_policy_fixture_row(absent)
  let (restored, selected) = read_run_record_with_selected_policy(
    old_row,
    Some(selected_policy_fixture_cid),
  ).unwrap()
  assert_true(selected is None)
  assert_true(restored.publication_policy_originals is None)
  assert_eq(run_record_body(restored).unwrap(), old_row.body)
}

///|
test "selected Policy cannot bypass malformed nonselected bodies or dependencies" {
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
      read_run_record_with_selected_policy(
        row,
        Some(selected_policy_fixture_cid),
      )
      is Err(CustodyLost),
    )
    assert_true(read_run_record(row) is Err(CustodyLost))
  }
}

///|
test "selected Policy is not returned before later original and canonical checks" {
  let record = selected_policy_fixture_record()
  let bad_effect = { ..record, effect_material_originals: Some("{}"), }
  assert_true(
    read_run_record_with_selected_policy(
      selected_policy_fixture_row(bad_effect),
      Some(selected_policy_fixture_cid),
    )
    is Err(CustodyLost),
  )
  let row = selected_policy_fixture_row(record)
  assert_true(
    read_run_record_with_selected_policy(
      {
        ..row,
        body: @utf8.encode(
          (@utf8.decode(row.body) catch { _ => fail("original UTF8") }) + " ",
        ),
      },
      Some(selected_policy_fixture_cid),
    )
    is Err(CustodyLost),
  )
  let bad_checkpoint = (@utf8.decode(row.body) catch {
    _ => fail("original UTF8")
  }).replace(old="\"checkpoint\":null", new="\"checkpoint\":\"{}\"")
  assert_true(
    read_run_record_with_selected_policy(
      { ..row, body: @utf8.encode(bad_checkpoint), },
      Some(selected_policy_fixture_cid),
    )
    is Err(CustodyLost),
  )
}

///|
test "selected Policy projection preserves original cancellation and start facts" {
  let record = {
    ..selected_policy_fixture_record(),
    dispatch_reserved: true,
    physical_start_claimed: true,
    cancellation_requested: true,
  }
  let row = selected_policy_fixture_row(record)
  let (restored, _) = read_run_record_with_selected_policy(
    row,
    Some(selected_policy_fixture_cid),
  ).unwrap()
  assert_true(restored.dispatch_reserved)
  assert_true(restored.physical_start_claimed)
  assert_true(restored.cancellation_requested)
  assert_eq(run_record_body(restored).unwrap(), row.body)
  // This private metadata projection is not a read grant or a continuation.
}

///|
test "selected retained Policy still rejects ChangedIntent without row changes" {
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
  let (_, selected) = journal
    .retained_with_selected_policy(request, Some(selected_policy_fixture_cid))
    .unwrap()
    .unwrap()
  assert_true(selected is Some(_))
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
  assert_true(
    journal.retained_with_selected_policy(
      changed_request,
      Some(selected_policy_fixture_cid),
    )
    is Err(ChangedIntent),
  )
  let after = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  database.close_checked().unwrap()
}

///|
test "Policy-last phase keeps CustodyLost for independently malformed combinations" {
  let record = selected_policy_fixture_record()
  for originals in [Some(selected_policy_fixture_packet), Some("{}"), None] {
    for effect in [Some("{}"), None] {
      let invalid_checkpoint_record = {
        ..record,
        publication_policy_originals: originals,
        effect_material_originals: effect,
      }
      let row = selected_policy_fixture_row(invalid_checkpoint_record)
      let wire = (@utf8.decode(row.body) catch { _ => fail("original UTF8") }).replace(
        old="\"checkpoint\":null",
        new="\"checkpoint\":\"{}\"",
      )
      assert_true(
        read_run_record_with_selected_policy(
          { ..row, body: @utf8.encode(wire), },
          Some(selected_policy_fixture_cid),
        )
        is Err(CustodyLost),
      )
      assert_true(
        read_run_record({ ..row, body: @utf8.encode(wire), })
        is Err(CustodyLost),
      )
    }
  }
  let compound = {
    ..record,
    publication_policy_originals: Some("{}"),
    effect_material_originals: Some("{}"),
    local_run_policy_originals: Some("{}"),
  }
  let row = selected_policy_fixture_row(compound)
  assert_true(
    read_run_record_with_selected_policy(row, Some(selected_policy_fixture_cid))
    is Err(CustodyLost),
  )
  assert_true(read_run_record(row) is Err(CustodyLost))
}
