///|
let append_request_id : String = "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267"

///|
fn append_original_record() -> ClientSubmittedJournalEncoding {
  decode_client_submitted_journal_row(@utf8.encode(saved_submission_preparing)).unwrap()
}

///|
fn append_plan(
  rows : Array[(String, ClientJournalPhysicalRow)],
  intent? : ClientSubmittedIntent = append_original_record().intent,
  validity? : SubmissionEpochValidity = @request_scope.Admissible,
  max_records? : Int = 1024,
) -> Result[
  ClientSubmittedJournalAppendPlan,
  ClientSubmittedJournalAppendIssue[String],
] {
  prepare_client_submitted_journal_append(
    append_original_record().reference,
    intent,
    validity,
    max_records,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    row => decode_client_submitted_journal_row(row.body).map_err(_ => "custody"),
    _ => Err("unexpected-Run-validation"),
    "custody",
  )
}

///|
test "fresh original preparing append preserves fixed row and issued CAS without Run" {
  let rows = [
    (
      "client_submitted_intent_custody",
      inventory_row("issued", b"0", revision=17L),
    ),
  ]
  guard append_plan(rows) is Ok(Append(plan)) else { fail("missing append") }
  let (key, body, revision, count) = client_submitted_journal_append_rows(plan)
  assert_eq(key, append_request_id)
  assert_eq(body, @utf8.encode(saved_submission_preparing))
  assert_eq(revision, 17L)
  assert_eq(count, b"1")
}

///|
test "retained preparing identity survives expiry without a new candidate" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    (
      "client_submitted_intents",
      inventory_row(
        append_request_id,
        @utf8.encode(saved_submission_preparing),
        revision=6L,
      ),
    ),
  ]
  guard append_plan(rows, validity=@request_scope.Expired)
    is Ok(Retained(snapshot)) else {
    fail("retained original rejected")
  }
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_true(client_saved_submission_record(snapshot).run_admission is None)
}

///|
test "changed intent cannot replace original preparing row" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    (
      "client_submitted_intents",
      inventory_row(append_request_id, @utf8.encode(saved_submission_preparing)),
    ),
  ]
  let changed = prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 2 AS n\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  assert_true(append_plan(rows, intent=changed) is Err(ChangedIntent))
}

///|
test "missing custody and partial inventory cannot issue append" {
  assert_true(append_plan([]) is Err(Observation("custody")))
  assert_true(
    append_plan([
      ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    ])
    is Err(Observation("custody")),
  )
}

///|
test "missing original after epoch expiry is not insertion or resend permission" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"0")),
  ]
  assert_true(
    append_plan(rows, validity=@request_scope.Expired)
    is Err(EpochRejected(@request_scope.Expired)),
  )
  assert_true(
    append_plan(rows, validity=@request_scope.NotYetValid)
    is Err(EpochRejected(@request_scope.NotYetValid)),
  )
}

///|
test "query failure remains observation error rather than missing original" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"0")),
  ]
  let result = prepare_client_submitted_journal_append(
    append_original_record().reference,
    append_original_record().intent,
    @request_scope.Admissible,
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => {
      if table == "client_submitted_intents" {
        Err("query-failure")
      } else {
        inventory_read(rows, table, key)
      }
    },
    row => decode_client_submitted_journal_row(row.body).map_err(_ => "custody"),
    _ => Err("unexpected-Run-validation"),
    "custody",
  )
  assert_true(result is Err(Observation("query-failure")))
}

///|
test "full inventory refuses a different fresh reference but preserves retained ready identity" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let reference = append_original_record().reference
  let decide = reference => {
    prepare_client_submitted_journal_append(
      reference,
      append_original_record().intent,
      @request_scope.Admissible,
      1,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      row => {
        decode_client_submitted_journal_row(row.body).map_err(_ => "custody")
      },
      _ => Ok(saved_snapshot_run()),
      "custody",
    )
  }
  guard decide(reference) is Ok(Retained(snapshot)) else {
    fail("retained ready original must not append")
  }
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_eq(
    client_saved_submission_record(snapshot).run_admission.unwrap().2,
    9007199254740993L,
  )
  let another = prepare_client_submission_reference_record(
    client_submission_reference_record_epoch(reference),
    "other-submission",
  ).unwrap()
  assert_true(decide(another) is Err(CapacityExceeded))
}

///|
test "selected nested Run validator failure is preserved without validating unrelated submissions" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let later_validations : Array[Int] = []
  let result = prepare_client_submitted_journal_append(
    append_original_record().reference,
    append_original_record().intent,
    @request_scope.Admissible,
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    _ => Err("original-validator-failure"),
    _ => {
      later_validations.push(1)
      Err("selected-original-validator-failure")
    },
    "custody",
  )
  assert_true(result is Err(Observation("selected-original-validator-failure")))
  assert_eq(later_validations, [1])
}

///|
test "retained submission target does not scan unrelated Run or Effect history" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let calls : Array[String] = []
  let result = prepare_client_submitted_journal_append(
    append_original_record().reference,
    append_original_record().intent,
    @request_scope.Expired,
    1024,
    (table, _) => {
      calls.push("scan:" + table)
      Err("unexpected-inventory")
    },
    (table, key) => {
      calls.push("read:" + table + ":" + key)
      inventory_read(rows, table, key)
    },
    _ => Err("unexpected-submission-inventory"),
    _ => {
      calls.push("validate-selected-run")
      Ok(saved_snapshot_run())
    },
    "custody",
  )
  guard result is Ok(Retained(snapshot)) else {
    fail("selected original refused")
  }
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_eq(calls.filter(value => value.has_prefix("scan:")).length(), 0)
  assert_eq(calls.filter(value => value == "validate-selected-run").length(), 1)
  assert_eq(
    calls.filter(value => value.has_prefix("read:client_runs:")).length(),
    1,
  )
  assert_eq(
    calls
    .filter(value => value.has_prefix("read:client_submitted_intents:"))
    .length(),
    1,
  )
}

///|
test "indexed fresh intents use fixed target and quota work across unrelated history" {
  for count in [0, 1, 10, 100, 1000] {
    let calls : Array[String] = []
    let bytes = count.to_int64() * 100L
    let rows = [
      (
        "client_submitted_intent_custody",
        inventory_row("issued", @utf8.encode(count.to_string())),
      ),
      ("client_runs", inventory_row("unrelated", b"not this target")),
    ]
    let result = prepare_client_submitted_journal_append(
      append_original_record().reference,
      append_original_record().intent,
      @request_scope.Admissible,
      1024,
      (_, _) => Err("ordinary append must not scan"),
      (table, key) => {
        calls.push(table + ":" + key)
        inventory_read(rows, table, key)
      },
      _ => Err("ordinary append must not validate unrelated intent"),
      _ => Err("ordinary append must not validate unrelated Run"),
      "custody",
      usage=Some(() => {
        calls.push("usage")
        Ok(
          Some(
            inventory_row(
              "retained",
              client_submitted_journal_usage_body(count, bytes, 1024).unwrap(),
              revision=9L,
            ),
          ),
        )
      }),
    )
    guard result is Ok(Append(plan)) else { fail("fresh append rejected") }
    assert_eq(calls, [
      "client_submitted_intent_custody:issued",
      "client_submitted_intents:" + append_request_id,
      "usage",
    ])
    let (revision, body) = client_submitted_journal_append_usage(plan).unwrap()
    assert_eq(revision, 9L)
    assert_eq(
      body,
      client_submitted_journal_usage_body(
        count + 1,
        bytes +
        @utf8.encode(
          client_submitted_intent_wire(append_original_record().intent),
        )
        .length()
        .to_int64(),
        1024,
      ).unwrap(),
    )
  }
}

///|
test "indexed append refuses missing stale noncanonical and exhausted quota without scan" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"1")),
  ]
  let decide = usage => {
    prepare_client_submitted_journal_append(
      append_original_record().reference,
      append_original_record().intent,
      @request_scope.Admissible,
      1024,
      (_, _) => Err("no compatibility sweep during ordinary append"),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("no unrelated validation"),
      _ => Err("no unrelated validation"),
      "custody",
      usage=Some(() => Ok(usage)),
    )
  }
  assert_true(decide(None) is Err(Observation("custody")))
  for
    body in [
      b"0:0", b"1:01", b"1:", b"1:-1", b"1:9223372036854775808", b"1:999999999999999999999",
    ] {
    assert_true(
      decide(Some(inventory_row("retained", body)))
      is Err(Observation("custody")),
    )
  }
  assert_true(
    decide(Some(inventory_row("retained", b"1:67108865")))
    is Err(CapacityExceeded),
  )
  assert_true(
    decide(Some(inventory_row("retained", b"1:67108864")))
    is Err(CapacityExceeded),
  )
}

///|
test "original intent encoding retains exact canonical byte inventory for Journal callers" {
  for text in ["ASCII", "日本語😀", "é\\r\\n", "\\\"\\\\"] {
    let original = "{\"parameters\":null,\"kind\":\"program\",\"input\":{\"value\":\"" +
      text +
      "\"}}"
    let intent = prepare_client_submitted_intent(original, 4096, 64, 8).unwrap()
    let expected = "{\"input\":{\"value\":\"" +
      text +
      "\"},\"kind\":\"program\",\"parameters\":null}"
    assert_eq(intent.wire, expected)
    assert_eq(intent.wire_bytes, @utf8.encode(expected).length())
    let restored = prepare_client_submitted_intent(expected, 4096, 64, 8).unwrap()
    assert_eq(restored, intent)
    assert_eq(
      client_submitted_intent_cid(restored),
      client_submitted_intent_cid(intent),
    )
  }
}

///|
test "selected journal count above 1024 preserves usage wire and exact append exhaustion" {
  for maximum in [1023, 1024, 1025, 2147483647] {
    let body = client_submitted_journal_usage_body(maximum, 67108864L, maximum).unwrap()
    assert_eq(body, @utf8.encode(maximum.to_string() + ":67108864"))
    assert_eq(
      client_submitted_journal_usage(
        inventory_row("retained", body),
        maximum,
        maximum,
      ),
      Ok(67108864L),
    )
  }
  for
    bytes in [
      b"1025:00", b"1025:-1", b"1025:", b"01025:0", b"1025:9223372036854775808",
    ] {
    assert_eq(
      client_submitted_journal_usage(
        inventory_row("retained", bytes),
        1025,
        1025,
      ),
      Err(CustodyLost),
    )
  }
  for count in [1023, 1024, 1025] {
    let original = append_original_record()
    let rows = [
      (
        "client_submitted_intent_custody",
        inventory_row(
          "issued",
          @utf8.encode(count.to_string()),
          revision=count.to_int64(),
        ),
      ),
    ]
    let decide = maximum => {
      prepare_client_submitted_journal_append(
        original.reference,
        original.intent,
        @request_scope.Admissible,
        maximum,
        (_, _) => Err("indexed append must not scan"),
        (table, key) => inventory_read(rows, table, key),
        _ => Err("unrelated intent"),
        _ => Err("unrelated Run"),
        "custody",
        usage=Some(() => {
          Ok(
            Some(
              inventory_row(
                "retained",
                client_submitted_journal_usage_body(count, 1000L, maximum).unwrap(),
                revision=9L,
              ),
            ),
          )
        }),
      )
    }
    assert_true(decide(count) is Err(CapacityExceeded))
    guard decide(count + 1) is Ok(Append(plan)) else {
      fail("selected next record refused")
    }
    let (_, _, revision, issued) = client_submitted_journal_append_rows(plan)
    assert_eq(revision, count.to_int64())
    assert_eq(issued, @utf8.encode((count + 1).to_string()))
  }
  let rows = [
    (
      "client_submitted_intent_custody",
      inventory_row("issued", b"1025", revision=1025L),
    ),
    (
      "client_submitted_intents",
      inventory_row(
        append_request_id,
        @utf8.encode(saved_submission_preparing),
        revision=6L,
      ),
    ),
  ]
  // Retained originals precede expiry and capacity. Neither scan nor a new
  // preparing row is allowed merely because the selected issuance is full.
  guard append_plan(rows, validity=@request_scope.Expired, max_records=1025)
    is Ok(Retained(retained)) else {
    fail("retained original lost above old internal ceiling")
  }
  assert_eq(client_saved_submission_revision(retained), 6L)
  assert_true(client_saved_submission_record(retained).run_admission is None)
}

///|
test "selected retained byte budget governs fresh append while canonical usage remains history" {
  for bytes in [67108863L, 67108864L, 67108865L, 9223372036854775807L] {
    let wire = @utf8.encode("1:" + bytes.to_string())
    assert_eq(client_submitted_journal_usage_body(1, bytes, 8), Ok(wire))
    assert_eq(
      client_submitted_journal_usage(inventory_row("retained", wire), 1, 8),
      Ok(bytes),
    )
  }
  let original = append_original_record()
  let amount = @utf8.encode(saved_submission_intent).length().to_int64()
  let previous = 67108865L
  let decide = (budget, rows) => {
    prepare_client_submitted_journal_append(
      original.reference,
      original.intent,
      @request_scope.Admissible,
      8,
      (_, _) => Err("indexed append must not scan"),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("no unrelated validation"),
      _ => Err("no unrelated validation"),
      "custody",
      usage=Some(() => {
        Ok(
          Some(
            inventory_row(
              "retained",
              @utf8.encode("1:" + previous.to_string()),
              revision=17L,
            ),
          ),
        )
      }),
      max_retained_intent_bytes=budget,
    )
  }
  let rows = [
    (
      "client_submitted_intent_custody",
      inventory_row("issued", b"1", revision=1L),
    ),
  ]
  assert_true(decide(previous + amount - 1L, rows) is Err(CapacityExceeded))
  guard decide(previous + amount, rows) is Ok(Append(plan)) else {
    fail("exact selected byte policy refused")
  }
  assert_eq(
    client_submitted_journal_append_usage(plan),
    Some((17L, @utf8.encode("2:" + (previous + amount).to_string()))),
  )
  assert_true(decide(0L, rows) is Err(CapacityExceeded))
  assert_true(decide(-1L, rows) is Err(CapacityExceeded))
  // No giant intent is allocated. The trusted inventory port supplies only its
  // existing cumulative usage metadata; the incoming original is unchanged.
  let retained_rows = [
    ..rows,
    (
      "client_submitted_intents",
      inventory_row(
        append_request_id,
        @utf8.encode(saved_submission_preparing),
        revision=6L,
      ),
    ),
  ]
  guard decide(0L, retained_rows) is Ok(Retained(retained)) else {
    fail("lower selection hid retained history")
  }
  assert_eq(client_saved_submission_revision(retained), 6L)
}
