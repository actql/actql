///|
// Independently authored existing Native row/preimage with Python hashlib.
// These bytes are never obtained from an encoder under test.
let cancellation_journal_fixture = "{\"action\":\"accepted\",\"cancel_id\":\"cancel-é\",\"expected_revision\":\"19\",\"intent_cid\":\"sha256:a60cc3b23787ba7444084bbf8a28d77f0fae37b5371d3be214886813b7829028\",\"namespace_id\":\"namespace-a\",\"observed_revision\":\"20\",\"request\":\"{\\\"authority_scope_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"caller_input_intent_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"caller_request_id\\\":\\\"caller-é\\\",\\\"intent_fingerprint_cid\\\":\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\",\\\"logical_request_scope_cid\\\":\\\"sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6\\\",\\\"parameter_values_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"program_definition_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"run_definition\":\"{\\\"authorization_context_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"compiled_plan_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"created_at\\\":\\\"2026-09-18T00:00:00.000Z\\\",\\\"input_artifact_set_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"invocation_template_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"run_definition_cid\\\":\\\"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc\\\",\\\"run_id\\\":\\\"run\\\",\\\"scope_id\\\":\\\"scope\\\",\\\"valid_until\\\":\\\"2099-01-01T00:00:00.000Z\\\",\\\"version\\\":\\\"actql-run-definition/0.1\\\"}\",\"version\":\"actql-native-client-cancellation-row/0.1\"}"

///|
let cancellation_journal_key_fixture = "3ec097f4b1602404e88a04cfe7da4c13504e50a5358aae9e3841039c77f6ebcd"

///|
fn cancellation_journal_original() -> ClientCancellationJournalEncoding {
  let run = journal_encoding_original()
  {
    namespace_id: "namespace-a",
    cancel_id: "cancel-é",
    expected_revision: 19,
    request: run.request,
    definition: run.definition,
    identity: prepare_client_cancellation_identity(
      "namespace-a",
      client_request_authority_scope_cid(run.request),
      "cancel-é",
      run.definition,
      19,
    ).unwrap(),
    action: AcceptCancellation,
    observed_revision: 20L,
  }
}

///|
fn cancellation_journal_rows() -> Array[(String, ClientJournalPhysicalRow)] {
  let run = { ..journal_encoding_original(), cancellation_requested: true, }
  [
    ("client_cancel_custody", inventory_row("issued", b"1", revision=1L)),
    (
      "client_cancellations",
      inventory_row(
        cancellation_journal_key_fixture,
        @utf8.encode(cancellation_journal_fixture),
      ),
    ),
    (
      "client_cancel_originals",
      inventory_row(
        cancellation_journal_key_fixture, b"dbe2a9daeaf7784ad3f98517e092e9ddb9b066e9f8af676fa169073c6ca096af",
      ),
    ),
    (
      "client_runs",
      inventory_row(
        client_request_scope_cid(run.request),
        client_run_journal_row_body(run).unwrap(),
        revision=20L,
      ),
    ),
  ]
}

///|
fn cancellation_journal_inspect(
  rows : Array[(String, ClientJournalPhysicalRow)],
) -> Result[(Int, Int64), String] {
  inspect_client_cancellation_journal_inventory(
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    row => {
      let run = match decode_client_run_journal_row(row.body) {
        Ok(value) => value
        Err(_) => return Err("custody")
      }
      // This fixture deliberately has no nested publication/checkpoint. The
      // production Native callback retains its complete original validators.
      if run.publication_binding is Some(_) ||
        run.publication_policy_originals is Some(_) ||
        run.effect_material_originals is Some(_) ||
        run.task_materials_cid is Some(_) ||
        run.checkpoint is Some(_) {
        return Err("custody")
      }
      Ok({
        request: run.request,
        definition: run.definition,
        cancellation_requested: run.cancellation_requested,
      })
    },
    "custody",
  )
}

///|
test "shared cancellation codec preserves exact Native bytes and independent identities" {
  let original = cancellation_journal_original()
  assert_eq(
    client_cancellation_journal_row_body(original),
    Some(@utf8.encode(cancellation_journal_fixture)),
  )
  assert_eq(
    client_cancellation_journal_index(
      "namespace-a",
      client_request_authority_scope_cid(original.request),
      "cancel-é",
    ),
    Some(cancellation_journal_key_fixture),
  )
  let restored = decode_client_cancellation_journal_row(
    inventory_row(
      cancellation_journal_key_fixture,
      @utf8.encode(cancellation_journal_fixture),
    ),
  ).unwrap()
  assert_eq(
    client_cancellation_identity_relation(original.identity, restored.identity),
    SameOperation,
  )
  assert_eq(restored.observed_revision, 20L)
  assert_eq(restored.action, AcceptCancellation)
}

///|
test "shared cancellation codec refuses a false intent CID and noncanonical original bytes" {
  for
    body in [
      cancellation_journal_fixture.replace(
        old="sha256:a60cc3b23787ba7444084bbf8a28d77f0fae37b5371d3be214886813b7829028",
        new="sha256:a60cc3b23787ba7444084bbf8a28d77f0fae37b5371d3be214886813b7829029",
      ),
      " " + cancellation_journal_fixture,
      cancellation_journal_fixture.replace(
        old="\"observed_revision\":\"20\"",
        new="\"observed_revision\":\"19\"",
      ),
      cancellation_journal_fixture.replace(
        old="\"cancel_id\":\"cancel-é\"",
        new="\"cancel_id\":\"foreign\"",
      ),
      cancellation_journal_fixture.replace(
        old="\"action\":\"accepted\"",
        new="\"extra\":true,\"action\":\"accepted\"",
      ),
    ] {
    assert_true(
      decode_client_cancellation_journal_row(
        inventory_row(cancellation_journal_key_fixture, @utf8.encode(body)),
      )
      is Err(CustodyLost),
    )
  }
  assert_true(
    decode_client_cancellation_journal_row(
      inventory_row(
        cancellation_journal_key_fixture,
        @utf8.encode(cancellation_journal_fixture),
        revision=1L,
      ),
    )
    is Err(CustodyLost),
  )
}

///|
test "nonempty cancellation census retains same original Run witness and issued count" {
  assert_eq(
    cancellation_journal_inspect(cancellation_journal_rows()),
    Ok((1, 1L)),
  )
  assert_eq(
    cancellation_journal_inspect([
      ("client_cancel_custody", inventory_row("issued", b"0")),
    ]),
    Ok((0, 0L)),
  )
  assert_eq(cancellation_journal_inspect([]), Err("custody"))
}

///|
test "nonempty cancellation census refuses lost witness stale Run and count corruption" {
  let rows = cancellation_journal_rows()
  assert_eq(
    cancellation_journal_inspect(
      rows.filter(pair => pair.0 != "client_cancel_originals"),
    ),
    Err("custody"),
  )
  for broken in ["witness", "run", "issued"] {
    let changed = rows.map(pair => {
      let (table, row) = pair
      if broken == "witness" && table == "client_cancel_originals" {
        (table, { ..row, body: b"changed", })
      } else if broken == "run" && table == "client_runs" {
        (table, { ..row, revision: 19L, })
      } else if broken == "issued" && table == "client_cancel_custody" {
        (table, { ..row, body: b"0", revision: 0L, })
      } else {
        pair
      }
    })
    assert_eq(cancellation_journal_inspect(changed), Err("custody"))
  }
}

///|
test "nonempty cancellation census propagates physical and full Run validator failure" {
  let rows = cancellation_journal_rows()
  assert_eq(
    inspect_client_cancellation_journal_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => {
        if table == "client_cancel_originals" {
          Err("physical")
        } else {
          inventory_read(rows, table, key)
        }
      },
      _ => Err("validator"),
      "custody",
    ),
    Err("physical"),
  )
  assert_eq(
    inspect_client_cancellation_journal_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("validator"),
      "custody",
    ),
    Err("validator"),
  )
}

///|
test "cancellation census reuses exact nested Run identities after observing the witness" {
  let rows = cancellation_journal_rows()
  let nested_decodes = Ref(0)
  let inspect = witness_available => {
    inspect_client_cancellation_journal_inventory_with_run_identity(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => {
        if !witness_available && table == "client_cancel_originals" {
          Err("physical")
        } else {
          inventory_read(rows, table, key)
        }
      },
      (row, request, definition) => {
        nested_decodes.val += 1
        let (run, _, _) = decode_client_run_journal_row_with_retained_identity(
          row.body,
          request,
          definition,
        ).unwrap()
        if !physical_equal(run.request, request) ||
          !physical_equal(run.definition, definition) {
          return Err("rebuilt identity")
        }
        Ok({
          request: run.request,
          definition: run.definition,
          cancellation_requested: run.cancellation_requested,
        })
      },
      "custody",
    )
  }
  assert_eq(inspect(false), Err("physical"))
  assert_eq(nested_decodes.val, 0)
  assert_eq(inspect(true), Ok((1, 1L)))
  assert_eq(nested_decodes.val, 1)
}
