///|
fn run_append_validate(
  row : ClientJournalPhysicalRow,
) -> Result[ClientRunJournalInspection, String] {
  let record = match decode_client_run_journal_row_with_local_policy(row.body) {
    Ok(value) => value
    Err(_) => return Err("custody")
  }
  // These independent fixtures have no nested publication/Effect/Checkpoint.
  // Production callers must use the full existing originals/custody validator.
  if record.0.publication_binding is Some(_) ||
    record.0.publication_policy_originals is Some(_) ||
    record.0.effect_material_originals is Some(_) ||
    record.0.checkpoint is Some(_) {
    return Err("custody")
  }
  if record.1 is Some(wire) {
    if validate_client_local_run_policy_original_run(
        @utf8.encode(wire),
        record.0.request,
        record.0.definition,
      )
      is Err(_) {
      return Err("custody")
    }
  }
  Ok({
    request: record.0.request,
    definition: record.0.definition,
    checkpoint: None,
    task_materials_cid: record.0.task_materials_cid,
  })
}

///|
fn run_append_plan(
  rows : Array[(String, ClientJournalPhysicalRow)],
  request? : ClientRequestIdentity = journal_encoding_original().request,
  definition? : @publication.PublicationContract = journal_encoding_original().definition,
  max_records? : Int = 1024,
) -> Result[ClientRunJournalAppendPlan, ClientRunJournalAppendIssue[String]] {
  prepare_client_run_journal_append(
    request,
    definition,
    max_records,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    run_append_validate,
    () => Ok(()),
    "custody",
  )
}

///|
fn run_append_existing_rows() -> Array[(String, ClientJournalPhysicalRow)] {
  [
    ("client_run_custody", inventory_row("issued", b"1", revision=17L)),
    (
      "client_runs",
      inventory_row(
        "sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6",
        client_run_journal_row_body(journal_encoding_original()).unwrap(),
        revision=9007199254740993L,
      ),
    ),
  ]
}

///|
test "Run append supplier projects fixed issued CAS and initial Run flags only" {
  let rows = [
    ("client_run_custody", inventory_row("issued", b"0", revision=17L)),
  ]
  guard run_append_plan(rows) is Ok(Append(plan)) else { fail("no candidate") }
  let (key, body, revision, count) = client_run_journal_append_rows(plan)
  assert_eq(
    key, "sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6",
  )
  assert_eq(revision, 17L)
  assert_eq(count, b"1")
  let (row, policy) = decode_client_run_journal_row_with_local_policy(body).unwrap()
  assert_eq(row.request, journal_encoding_original().request)
  assert_eq(
    @publication.publication_contract_json(row.definition),
    journal_encoding_definition,
  )
  assert_false(row.dispatch_reserved)
  assert_false(row.physical_start_claimed)
  assert_false(row.cancellation_requested)
  assert_true(
    row.publication_binding is None && row.checkpoint is None && policy is None,
  )
}

///|
test "Run retained lookup precedes inventory or policy issuance and preserves saved bytes revision" {
  let row = run_append_existing_rows()[1].1
  let calls : Array[String] = []
  let result = prepare_client_run_journal_append(
    journal_encoding_original().request,
    journal_encoding_original().definition,
    1,
    (_, _) => {
      calls.push("scan")
      Err("must-not-scan")
    },
    (table, key) => {
      calls.push(table)
      assert_eq(key, row.key) catch {
        _ => return Err("key")
      }
      Ok(Some(row))
    },
    run_append_validate,
    () => Err("must-not-cancel"),
    "custody",
  )
  guard result is Ok(Retained(retained)) else { fail("original rejected") }
  let saved = client_retained_run_journal_row(retained)
  assert_eq(saved.body, row.body)
  assert_eq(saved.revision, 9007199254740993L)
  assert_eq(calls, ["client_runs"])
}

///|
test "Run lookup query failure and confirmed NotFound remain distinct" {
  assert_true(
    read_client_retained_run_journal(
      journal_encoding_original().request,
      (_, _) => Err("sqlite-query"),
      run_append_validate,
      "custody",
    )
    is Err(Observation("sqlite-query")),
  )
  assert_true(
    read_client_retained_run_journal(
      journal_encoding_original().request,
      (_, _) => Ok(None),
      run_append_validate,
      "custody",
    )
    is Ok(None),
  )
}

///|
test "Run supplier rejects changed intent foreign retained key and incomplete originals" {
  let original = journal_encoding_original()
  let changed = {
    ..original.request,
    caller_input_intent_cid: "sha256:" + "e".repeat(64),
  }
  assert_true(
    run_append_plan(run_append_existing_rows(), request=changed)
    is Err(ChangedIntent),
  )
  for
    row in [
      inventory_row("foreign", client_run_journal_row_body(original).unwrap()),
      inventory_row(client_request_scope_cid(original.request), b"{}"),
      inventory_row(
        client_request_scope_cid(original.request),
        client_run_journal_row_body(original).unwrap(),
        revision=-1L,
      ),
    ] {
    assert_true(
      read_client_retained_run_journal(
        original.request,
        (_, _) => Ok(Some(row)),
        run_append_validate,
        "custody",
      )
      is Err(Observation("custody")),
    )
  }
}

///|
test "Run supplier rejects retained different definition without replacing original" {
  assert_true(
    run_append_plan(
      run_append_existing_rows(),
      definition=local_run_policy_packet_definition(),
    )
    is Err(ForeignRun),
  )
}

///|
test "Run supplier closes complete custody before fresh capacity and duplicate decisions" {
  let original = journal_encoding_original().request
  let other = derive_client_request_identity(
    {
      program_definition_cid: original.program_definition_cid,
      parameter_values_cid: original.parameter_values_cid,
    },
    original.authority_scope_cid,
    "other",
    original.caller_input_intent_cid,
  ).unwrap()
  assert_true(
    run_append_plan(run_append_existing_rows(), request=other, max_records=1)
    is Err(CapacityExceeded),
  )
  assert_true(
    run_append_plan(run_append_existing_rows(), request=other, max_records=2)
    is Err(ForeignRun),
  )
  for
    rows in [
      [],
      [("client_run_custody", inventory_row("issued", b"1"))],
      [
        ("client_run_custody", inventory_row("issued", b"0")),
        ("client_effect_response_bytes", inventory_row("orphan", b"bytes")),
      ],
    ] {
    assert_true(run_append_plan(rows) is Err(Observation("custody")))
  }
}

///|
test "Run supplier retains cancellation and saved original validation failures" {
  assert_true(
    prepare_client_run_journal_append(
      journal_encoding_original().request,
      journal_encoding_original().definition,
      1024,
      (table, cursor) => {
        inventory_scan(
          [("client_run_custody", inventory_row("issued", b"0"))],
          table,
          cursor,
        )
      },
      (table, key) => {
        inventory_read(
          [("client_run_custody", inventory_row("issued", b"0"))],
          table,
          key,
        )
      },
      run_append_validate,
      () => Err("cleanup-pending"),
      "custody",
    )
    is Err(Observation("cleanup-pending")),
  )
  assert_true(
    read_client_retained_run_journal(
      journal_encoding_original().request,
      (_, _) => Ok(Some(run_append_existing_rows()[1].1)),
      _ => Err("original-publication-custody"),
      "custody",
    )
    is Err(Observation("original-publication-custody")),
  )
}

///|
test "Run append initial transaction carries exact nominal finite policy original" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let request = local_run_policy_packet_request()
  let definition = local_run_policy_packet_definition()
  let original = admit_client_local_run_policy_original(
    @utf8.encode(local_run_policy_packet_fixture),
    profile,
    local_run_policy_packet_reference(),
    request,
    definition,
    "sha256:" + "a".repeat(64),
    "sha256:" + "f".repeat(64),
  ).unwrap()
  let rows = [
    ("client_run_custody", inventory_row("issued", b"0", revision=23L)),
  ]
  let prepare = (request, definition) => {
    prepare_client_run_journal_append(
      request,
      definition,
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      run_append_validate,
      () => Ok(()),
      "custody",
      local_policy_original=Some(original),
    )
  }
  guard prepare(request, definition) is Ok(Append(plan)) else {
    fail("no original candidate")
  }
  let (_, body, revision, count) = client_run_journal_append_rows(plan)
  assert_eq(revision, 23L)
  assert_eq(count, b"1")
  let (_, packet) = decode_client_run_journal_row_with_local_policy(body).unwrap()
  assert_eq(packet, Some(local_run_policy_packet_fixture))
  assert_true(
    prepare(journal_encoding_original().request, definition)
    is Err(InvalidOriginal),
  )
  assert_true(
    prepare(request, journal_encoding_original().definition)
    is Err(InvalidOriginal),
  )
}

///|
test "Run append refuses negative issued revision and preserves query failure" {
  assert_true(
    run_append_plan([
      ("client_run_custody", inventory_row("issued", b"0", revision=-1L)),
    ])
    is Err(Observation("custody")),
  )
  assert_true(
    prepare_client_run_journal_append(
      journal_encoding_original().request,
      journal_encoding_original().definition,
      1024,
      (_, _) => Err("scan-query"),
      (_, _) => Ok(None),
      run_append_validate,
      () => Ok(()),
      "custody",
    )
    is Err(Observation("scan-query")),
  )
}

///|
test "Run append refuses changing physical scan instead of accepting partial candidate" {
  let rows = run_append_existing_rows()
  let second = Ref(false)
  let result = prepare_client_run_journal_append(
    local_run_policy_packet_request(),
    local_run_policy_packet_definition(),
    1024,
    (table, cursor) => {
      if second.val && table == "client_runs" {
        return Ok(None)
      }
      inventory_scan(rows, table, cursor)
    },
    (table, key) => inventory_read(rows, table, key),
    run_append_validate,
    () => {
      second.val = true
      Ok(())
    },
    "custody",
  )
  assert_true(result is Err(Observation("custody")))
}
