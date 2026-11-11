///|
// Fixed physical rows are fixture observations, not public admission or Store
// ACK evidence. Identity fixtures are the independently authored original rows.
fn inventory_row(
  key : String,
  body : Bytes,
  revision? : Int64 = 0L,
) -> ClientJournalPhysicalRow {
  { key, body, revision, }
}

///|
fn inventory_scan(
  rows : Array[(String, ClientJournalPhysicalRow)],
  table_name : String,
  cursor : String,
) -> Result[ClientJournalPhysicalRow?, String] {
  let mut result : ClientJournalPhysicalRow? = None
  for (table, row) in rows {
    if table == table_name &&
      row.key > cursor &&
      (result is None || row.key < result.unwrap().key) {
      result = Some(row)
    }
  }
  Ok(result)
}

///|
fn inventory_read(
  rows : Array[(String, ClientJournalPhysicalRow)],
  table_name : String,
  key : String,
) -> Result[ClientJournalPhysicalRow?, String] {
  for (table, row) in rows {
    if table == table_name && row.key == key {
      return Ok(Some(row))
    }
  }
  Ok(None)
}

///|
fn inventory_run_original() -> ClientRunJournalInspection {
  let original = journal_encoding_original()
  {
    request: original.request,
    definition: original.definition,
    checkpoint: None,
    task_materials_cid: None,
  }
}

///|
fn inventory_run_rows() -> Array[(String, ClientJournalPhysicalRow)] {
  [
    (
      "client_run_custody",
      inventory_row("issued", b"1", revision=9007199254740993L),
    ),
    (
      "client_runs",
      inventory_row(
        "sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6",
        b"original-run",
      ),
    ),
  ]
}

///|
fn inventory_check(
  rows : Array[(String, ClientJournalPhysicalRow)],
  original? : ClientRunJournalInspection = inventory_run_original(),
) -> Result[(Int, Int64), String] {
  inspect_client_run_journal_inventory(
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    _ => Ok(original),
    () => Ok(()),
    "custody",
  )
}

///|
test "complete original Run inventory visits every scope and original cancellation validator" {
  let rows = inventory_run_rows()
  let visited : Array[String] = []
  let cancellations : Array[Int] = []
  let result = inspect_client_run_journal_inventory(
    1024,
    (table, cursor) => {
      visited.push(table)
      inventory_scan(rows, table, cursor)
    },
    (table, key) => inventory_read(rows, table, key),
    row => {
      assert_eq(row.body, b"original-run") catch {
        _ => return Err("run")
      }
      Ok(inventory_run_original())
    },
    () => {
      cancellations.push(1)
      Ok(())
    },
    "custody",
  )
  assert_eq(result, Ok((1, 9007199254740993L)))
  assert_eq(cancellations, [1])
  for
    table in [
      "client_run_custody", "client_runs", "client_effect_custody", "client_effect_response_meta",
      "client_effect_response_bytes", "client_effect_row_receipt",
    ] {
    assert_true(visited.contains(table))
  }
}

///|
test "complete empty inventory requires issued record and all remaining scopes" {
  assert_eq(
    inventory_check([("client_run_custody", inventory_row("issued", b"0"))]),
    Ok((0, 0L)),
  )
  assert_eq(inventory_check([]), Err("custody"))
  for
    table in [
      "client_runs", "client_effect_custody", "client_effect_response_meta", "client_effect_response_bytes",
      "client_effect_row_receipt",
    ] {
    assert_eq(
      inventory_check([
        ("client_run_custody", inventory_row("issued", b"0")),
        (table, inventory_row("orphan", b"unattached")),
      ]),
      Err("custody"),
    )
  }
}

///|
test "original issuance metadata refuses omitted extra malformed and unmatched rows" {
  for body in [b"0", b"2", b"01", b"-1", b"1025", b" 1", b"1\n"] {
    let rows = inventory_run_rows()
    rows[0] = ("client_run_custody", inventory_row("issued", body))
    assert_eq(inventory_check(rows), Err("custody"))
  }
  let rows = inventory_run_rows()
  rows.push(("client_run_custody", inventory_row("other", b"1")))
  assert_eq(inventory_check(rows), Err("custody"))
  let rows = inventory_run_rows()
  rows[1] = ("client_runs", inventory_row("foreign-scope", b"original-run"))
  assert_eq(inventory_check(rows), Err("custody"))
}

///|
test "original Run inventory preserves query failures instead of confirmed end" {
  let rows = inventory_run_rows()
  for
    failed in [
      "client_run_custody", "client_runs", "client_effect_custody", "client_effect_response_meta",
      "client_effect_response_bytes", "client_effect_row_receipt",
    ] {
    assert_eq(
      inspect_client_run_journal_inventory(
        1024,
        (table, cursor) => {
          if table == failed {
            Err("query")
          } else {
            inventory_scan(rows, table, cursor)
          }
        },
        (table, key) => inventory_read(rows, table, key),
        _ => Ok(inventory_run_original()),
        () => Ok(()),
        "custody",
      ),
      Err("query"),
    )
  }
  assert_eq(
    inspect_client_run_journal_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (_, _) => Err("read-query"),
      _ => Ok(inventory_run_original()),
      () => Ok(()),
      "custody",
    ),
    Err("read-query"),
  )
}

///|
test "Run inventory requires original semantic and cancellation custody validators" {
  let rows = inventory_run_rows()
  assert_eq(
    inspect_client_run_journal_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("nested-originals"),
      () => Ok(()),
      "custody",
    ),
    Err("nested-originals"),
  )
  assert_eq(
    inspect_client_run_journal_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      _ => Ok(inventory_run_original()),
      () => Err("cancel-custody"),
      "custody",
    ),
    Err("cancel-custody"),
  )
}

///|
test "Run inventory retains count bound for nonadvancing physical scans and duplicate definitions" {
  let rows = inventory_run_rows()
  assert_eq(
    inspect_client_run_journal_inventory(
      1,
      (table, cursor) => {
        if table == "client_runs" {
          Ok(Some(rows[1].1))
        } else {
          inventory_scan(rows, table, cursor)
        }
      },
      (table, key) => inventory_read(rows, table, key),
      _ => Ok(inventory_run_original()),
      () => Ok(()),
      "custody",
    ),
    Err("custody"),
  )
  let second = decode_client_submitted_journal_row(
      @utf8.encode(saved_submission_ready),
    ).unwrap().run_admission.unwrap().0
  let rows = inventory_run_rows()
  rows[0] = ("client_run_custody", inventory_row("issued", b"2"))
  rows.push(
    (
      "client_runs",
      inventory_row(
        "sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918",
        b"second-run",
      ),
    ),
  )
  assert_eq(
    inspect_client_run_journal_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      row => {
        Ok(
          if row.body == b"second-run" {
            { ..inventory_run_original(), request: second, }
          } else {
            inventory_run_original()
          },
        )
      },
      () => Ok(()),
      "custody",
    ),
    Err("custody"),
  )
}

///|
test "checkpoint custody scope is complete without unattached witnesses" {
  let original = { ..inventory_run_original(), checkpoint: Some([]), }
  let rows = inventory_run_rows()
  assert_eq(inventory_check(rows, original~), Err("custody"))
  rows.push(
    (
      "client_effect_custody",
      inventory_row(
        "sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6",
        b"witness",
      ),
    ),
  )
  assert_eq(inventory_check(rows, original~), Ok((1, 9007199254740993L)))
  rows.push(("client_effect_custody", inventory_row("foreign", b"witness")))
  assert_eq(inventory_check(rows, original~), Err("custody"))
}

///|
fn inventory_effect_entry() -> @effect.EffectLedgerEntry {
  let scope = @effect.prepare_logical_request_scope(
    "sha256:" + "a".repeat(64),
    "original-caller",
    128,
  ).unwrap()
  let key = @effect.prepare_effect_dispatch_key(
    scope,
    "sha256:" + "b".repeat(64),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = @effect.prepare_logical_item_locator(
    scope, "original-program", "original-node", "WriteOne", "{\"row\":\"row-1\"}",
    128, 128, 8, 3,
  ).unwrap()
  let basis = @effect.prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "sha256:" + "e".repeat(64),
    "sha256:" + "f".repeat(64),
    "sha256:" + "0".repeat(64),
    "unavailable",
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
  ).unwrap()
  let pending = @effect.issue_prepared_effect_ledger_entry(basis, 4096, 64, 3).unwrap()
  @effect.issue_next_effect_ledger_entry(
    pending,
    "dispatching",
    None,
    4096,
    64,
    3,
  ).unwrap()
}

///|
fn inventory_checkpoint_rows() -> Array[(String, ClientJournalPhysicalRow)] {
  let rows = inventory_run_rows()
  rows.push(
    (
      "client_effect_custody",
      inventory_row(
        "sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6",
        b"witness",
      ),
    ),
  )
  rows
}

///|
test "dispatch response inventory retains paired bytes identity and revision" {
  let entry = inventory_effect_entry()
  let cid = @effect.effect_ledger_entry_cid(entry)
  let original = { ..inventory_run_original(), checkpoint: Some([entry]), }
  assert_eq(
    inventory_check(inventory_checkpoint_rows(), original~),
    Ok((1, 9007199254740993L)),
  )
  let rows = inventory_checkpoint_rows()
  rows.push(("client_effect_response_meta", inventory_row(cid, b"metadata")))
  assert_eq(inventory_check(rows, original~), Err("custody"))
  rows.push(
    ("client_effect_response_bytes", inventory_row(cid, b"raw-response")),
  )
  assert_eq(inventory_check(rows, original~), Ok((1, 9007199254740993L)))
  rows[3] = (
    "client_effect_response_meta",
    inventory_row(cid, b"metadata", revision=1L),
  )
  assert_eq(inventory_check(rows, original~), Err("custody"))
}

///|
test "completed ledger receipt inventory requires original receipt and zero revision" {
  let sending = inventory_effect_entry()
  let entry = @effect.issue_next_effect_ledger_entry(
    sending,
    "applied",
    Some("sha256:" + "3".repeat(64)),
    4096,
    64,
    3,
  ).unwrap()
  let original = { ..inventory_run_original(), checkpoint: Some([entry]), }
  let rows = inventory_checkpoint_rows()
  assert_eq(inventory_check(rows, original~), Err("custody"))
  rows.push(
    (
      "client_effect_row_receipt",
      inventory_row("sha256:" + "3".repeat(64), b"receipt"),
    ),
  )
  assert_eq(inventory_check(rows, original~), Ok((1, 9007199254740993L)))
  rows[3] = (
    "client_effect_row_receipt",
    inventory_row("sha256:" + "3".repeat(64), b"receipt", revision=1L),
  )
  assert_eq(inventory_check(rows, original~), Err("custody"))
  assert_eq(
    inventory_check(rows, original={
      ..original,
      checkpoint: Some([entry, entry]),
    }),
    Err("custody"),
  )
}

///|
fn inventory_submission_rows(
  body : String,
) -> Array[(String, ClientJournalPhysicalRow)] {
  [
    (
      "client_submitted_intent_custody",
      inventory_row("issued", b"1", revision=9007199254740993L),
    ),
    (
      "client_submitted_intents",
      inventory_row(
        "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
        @utf8.encode(body),
      ),
    ),
  ]
}

///|
fn inventory_submission_check(
  rows : Array[(String, ClientJournalPhysicalRow)],
) -> Result[(Int, Int64, Int64), String] {
  inspect_client_submitted_journal_inventory(
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    row => {
      decode_client_submitted_journal_row(row.body).map_err(_ => "original-row")
    },
    "custody",
  )
}

///|
test "submitted inventory preserves preparing and ready original intent byte accounting" {
  for body in [saved_submission_preparing, saved_submission_ready] {
    assert_eq(
      inventory_submission_check(inventory_submission_rows(body)),
      Ok(
        (
          1,
          @utf8.encode(saved_submission_intent).length().to_int64(),
          9007199254740993L,
        ),
      ),
    )
  }
  assert_eq(
    inventory_submission_check([
      ("client_submitted_intent_custody", inventory_row("issued", b"0")),
    ]),
    Ok((0, 0L, 0L)),
  )
}

///|
test "submitted inventory rejects count omissions foreign request and malformed original row" {
  let rows = inventory_submission_rows(saved_submission_ready)
  rows[0] = ("client_submitted_intent_custody", inventory_row("issued", b"2"))
  assert_eq(inventory_submission_check(rows), Err("custody"))
  let rows = inventory_submission_rows(saved_submission_ready)
  rows[1] = (
    "client_submitted_intents",
    inventory_row("foreign-request", @utf8.encode(saved_submission_ready)),
  )
  assert_eq(inventory_submission_check(rows), Err("custody"))
  let rows = inventory_submission_rows(saved_submission_ready + " ")
  assert_eq(inventory_submission_check(rows), Err("original-row"))
}

///|
test "submitted inventory propagates original retained relationship failure and physical query failure" {
  let rows = inventory_submission_rows(saved_submission_ready)
  assert_eq(
    inspect_client_submitted_journal_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("retained-relationship"),
      "custody",
    ),
    Err("retained-relationship"),
  )
  for failed in ["client_submitted_intent_custody", "client_submitted_intents"] {
    assert_eq(
      inspect_client_submitted_journal_inventory(
        1024,
        (table, cursor) => {
          if table == failed {
            Err("query")
          } else {
            inventory_scan(rows, table, cursor)
          }
        },
        (table, key) => inventory_read(rows, table, key),
        row => {
          decode_client_submitted_journal_row(row.body).map_err(_ => {
            "original-row"
          })
        },
        "custody",
      ),
      Err("query"),
    )
  }
}

///|
test "empty original journal inventory accepts large selected policy without policy-sized Maps" {
  let rows = [
    ("client_run_custody", inventory_row("issued", b"0", revision=0L)),
  ]
  for maximum in [1023, 1024, 1025, 2147483647] {
    assert_eq(
      inspect_client_run_journal_inventory(
        maximum,
        (table, cursor) => inventory_scan(rows, table, cursor),
        (table, key) => inventory_read(rows, table, key),
        _ => Err("empty inventory has no Run"),
        () => Ok(()),
        "custody",
      ),
      Ok((0, 0L)),
    )
  }
}

///|
test "retained intent byte sum is actual checked metadata beyond the compatibility policy" {
  assert_eq(journal_retained_intent_bytes_add(67108864L, 1), Some(67108865L))
  assert_eq(
    journal_retained_intent_bytes_add(9223372036854775806L, 1),
    Some(9223372036854775807L),
  )
  assert_eq(journal_retained_intent_bytes_add(9223372036854775807L, 1), None)
  assert_eq(journal_retained_intent_bytes_add(-1L, 0), None)
  assert_eq(journal_retained_intent_bytes_add(0L, -1), None)
}
