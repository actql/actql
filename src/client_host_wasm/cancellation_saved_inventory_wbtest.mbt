///|
// Fixed physical rows exercise the actual shared Saved/cancellation callee.
// No physical Host import, authentication, write, stop or ACK is supplied.
fn cancellation_saved_rows() -> Array[(String, @host.ClientJournalPhysicalRow)] {
  let rows = indexed_targeted_rows()
  let original = original_rows_identity(rows)
  let identity = @host.prepare_client_cancellation_identity(
    "scope",
    @host.client_request_authority_scope_cid(original.0),
    "saved-cancel",
    original.1,
    19,
  ).unwrap()
  let body = @host.client_cancellation_journal_row_body({
    namespace_id: "scope",
    cancel_id: "saved-cancel",
    expected_revision: 19,
    request: original.0,
    definition: original.1,
    identity,
    action: @host.AlreadyTerminal,
    observed_revision: 19L,
  }).unwrap()
  let key = @host.client_cancellation_journal_index(
    "scope",
    @host.client_request_authority_scope_cid(original.0),
    "saved-cancel",
  ).unwrap()
  let actual : Array[(String, @host.ClientJournalPhysicalRow)] = rows.map(pair => {
    if pair.0 == "client_cancel_custody" {
      (pair.0, { key: "issued", revision: 1L, body: b"1", })
    } else {
      pair
    }
  })
  actual.push(("client_cancellations", { key, revision: 0L, body, }))
  actual.push(
    (
      "client_cancel_originals",
      { key, revision: 0L, body: @utf8.encode(@sha.hex(body)), },
    ),
  )
  actual
}

///|
fn cancellation_saved_observe(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
  original : @host.ClientSavedSubmissionSnapshot?,
) -> Result[@host.ClientSavedSubmissionSnapshot?, Int] {
  submission_run_reference_snapshot(
    "scope",
    "sha256:" + "b".repeat(64),
    "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
    original,
    (table, key) => targeted_row_read(rows, table, key),
    submission_append_run_inspection,
    () => {
      submission_cancellation_inventory(
        (table, cursor) => targeted_row_scan(rows, table, cursor),
        (table, key) => targeted_row_read(rows, table, key),
      )
    },
  )
}

///|
test "Saved source retains complete original rows with valid nonempty cancellation history" {
  let rows = cancellation_saved_rows()
  let original = targeted_original(rows)
  for saved in [None, Some(original)] {
    guard cancellation_saved_observe(rows, saved) is Ok(Some(actual)) else {
      fail("valid original Saved rows refused")
    }
    assert_eq(
      original_row_fields(@host.client_saved_submission_row(actual)),
      original_row_fields(@host.client_saved_submission_row(original)),
    )
    assert_eq(
      @host.client_saved_submission_run_row(actual).map(original_row_fields),
      @host.client_saved_submission_run_row(original).map(original_row_fields),
    )
  }
}

///|
test "completed Saved cannot bypass missing cancellation witness or physical query failure" {
  let rows = cancellation_saved_rows()
  let original = targeted_original(rows)
  assert_true(
    cancellation_saved_observe(
      rows.filter(pair => pair.0 != "client_cancel_originals"),
      Some(original),
    )
    is Err(-31),
  )
  assert_eq(
    submission_cancellation_inventory(
      (table, cursor) => targeted_row_scan(rows, table, cursor),
      (table, key) => {
        if table == "client_cancel_originals" {
          Err(-41)
        } else {
          targeted_row_read(rows, table, key)
        }
      },
    ),
    Err(-41),
  )
}

///|
test "nonempty cancellation retains the full existing nested Run validation frontier" {
  let rows = cancellation_saved_rows().map(pair => {
    let (table, row) = pair
    if table == "client_runs" {
      let run = @host.decode_client_run_journal_row(row.body).unwrap()
      (
        table,
        {
          ..row,
          body: @host.client_run_journal_row_body({
            ..run,
            checkpoint: Some("{}"),
          }).unwrap(),
        },
      )
    } else {
      pair
    }
  })
  assert_eq(
    submission_cancellation_inventory(
      (table, cursor) => targeted_row_scan(rows, table, cursor),
      (table, key) => targeted_row_read(rows, table, key),
    ),
    Err(-42),
  )
}

///|
test "Saved rebind observes the fresh cancellation witness on every invocation" {
  let rows = cancellation_saved_rows()
  let snapshot = targeted_original(rows)
  let retained : StoredSavedResultRead = {
    snapshot,
    result_name: "answer",
    fences: [],
    source: None,
    policy_capacity: None,
    selection_capacity: None,
    coordinates_capacity: None,
    selection: None,
    finite: None,
    owner: None,
    view: None,
    commit_observation: true,
    advances_remaining: 1,
  }
  let scan = (table, cursor) => targeted_row_scan(rows, table, cursor)
  let witness_reads = Ref(0)
  let rebind = witness_available => {
    rebind_saved_result_originals(retained, 1, scan, (table, key) => {
      if table == "client_cancel_originals" {
        witness_reads.val += 1
        if !witness_available {
          return Err(-71)
        }
      }
      targeted_row_read(rows, table, key)
    })
  }
  assert_eq(rebind(true), Ok(()))
  assert_eq(rebind(false), Err(-71))
  assert_eq(witness_reads.val, 2)
  assert_true(physical_equal(retained.snapshot, snapshot))
}

///|
test "Saved input reuses checked fence rows only within the same proven reader" {
  let rows = cancellation_saved_rows()
  let retained : StoredSavedResultRead = {
    snapshot: targeted_original(rows),
    result_name: "answer",
    fences: [("publication_attempt", "original", 7L, b"first")],
    source: None,
    policy_capacity: None,
    selection_capacity: None,
    coordinates_capacity: None,
    selection: None,
    finite: None,
    owner: None,
    view: None,
    commit_observation: true,
    advances_remaining: 0,
  }
  let scans = Ref(0)
  let selected_reads = Ref(0)
  let fence_reads = Ref(0)
  let body = Ref(b"first")
  let proof_ticket = Ref(0)
  let run = (ticket, proof, reuse) => {
    rebind_saved_result_originals(
      retained,
      1,
      (table, cursor) => {
        scans.val += 1
        targeted_row_scan(rows, table, cursor)
      },
      (table, key) => {
        if table == "publication_attempt" && key == "original" {
          fence_reads.val += 1
          return Ok(Some({ key, revision: 7L, body: body.val, }))
        }
        if table == "client_submitted_intents" || table == "client_runs" {
          selected_reads.val += 1
        }
        targeted_row_read(rows, table, key)
      },
      census_ticket=ticket,
      census_current=actual => {
        proof_ticket.val = actual
        proof
      },
      reuse_proven_fence_rows=reuse,
    )
  }
  // An initial observation always reads the fence and performs the census.
  assert_eq(run(0, -41L, true), Ok(()))
  assert_eq(fence_reads.val, 1)
  assert_eq(proof_ticket.val, 0)
  let first_scans = scans.val
  let first_selected_reads = selected_reads.val
  assert_true(first_scans > 0 && first_selected_reads > 0)

  // Only the selected caller also reuses its proven physical fence reads.
  assert_eq(run(17, 1L, true), Ok(()))
  assert_eq(proof_ticket.val, 17)
  assert_eq(fence_reads.val, 1)
  assert_eq(scans.val, first_scans)
  assert_true(selected_reads.val > first_selected_reads)
  assert_eq(run(17, 1L, false), Ok(()))
  assert_eq(fence_reads.val, 2)
  assert_eq(scans.val, first_scans)

  body.val = b"other"
  // A failed proof returns the original physical refusal without a requery.
  assert_eq(run(17, -41L, true), Err(-41))
  assert_eq(fence_reads.val, 2)
  assert_eq(scans.val, first_scans)
  // A physical effect or unsupported supplier requires the full checks.
  assert_eq(run(17, 0L, true), Err(-32))
  assert_eq(fence_reads.val, 3)
  assert_eq(scans.val, first_scans * 2)
}
