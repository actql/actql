///|
fn cancellation_lookup_observe(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
  cancel_id : String,
  revision : Int,
  current? : () -> Bool = () => true,
) -> Result[@host.ClientCancellationJournalLookup, Int] {
  submission_cancellation_lookup_original(
    Some(targeted_original(rows)),
    "scope",
    cancel_id,
    revision,
    (table, cursor) => targeted_row_scan(rows, table, cursor),
    (table, key) => targeted_row_read(rows, table, key),
    current,
  )
}

///|
test "saved cancellation lookup returns the original result and exact public reference" {
  let rows = cancellation_saved_rows()
  let observed = cancellation_lookup_observe(rows, "saved-cancel", 19).unwrap()
  guard observed is @host.OriginalCancellation(record) else {
    fail("original cancellation was lost")
  }
  assert_eq(record.action, @host.AlreadyTerminal)
  assert_eq(record.observed_revision, 19L)
  let actual = submission_cancellation_lookup_view(
    "scope",
    "sha256:" + "b".repeat(64),
    "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
    "saved-cancel",
    19,
    observed,
  ).unwrap()
  let expected =
    #|{"kind":"found","cancellation":{"ref":{"namespaceId":"scope","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runDefinitionCid":"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc"},"cancelRef":{"namespaceId":"scope","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runDefinitionCid":"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc","cancelId":"saved-cancel","expectedRevision":19},"kind":"already_terminal","revision":19}}
  assert_eq(actual, @utf8.encode(expected))
}

///|
test "missing cancellation remains unknown and changed original intent refuses" {
  let rows = cancellation_saved_rows()
  let observed = cancellation_lookup_observe(rows, "not-recorded", 19).unwrap()
  assert_true(observed is @host.UnresolvedCancellationHistory)
  let actual = submission_cancellation_lookup_view(
    "scope",
    "sha256:" + "b".repeat(64),
    "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
    "not-recorded",
    19,
    observed,
  ).unwrap()
  let expected =
    #|{"kind":"unknown","cancelRef":{"namespaceId":"scope","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runDefinitionCid":"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc","cancelId":"not-recorded","expectedRevision":19}}
  assert_eq(actual, @utf8.encode(expected))
  assert_true(cancellation_lookup_observe(rows, "saved-cancel", 20) is Err(-32))
}

///|
test "lookup preserves current and physical failure without issuing or preparing a Run" {
  let rows = cancellation_saved_rows()
  assert_true(
    cancellation_lookup_observe(rows, "saved-cancel", 19, current=() => false)
    is Err(-32),
  )
  assert_true(
    cancellation_lookup_observe(
      rows.filter(pair => pair.0 != "client_cancel_originals"),
      "saved-cancel",
      19,
    )
    is Err(-31),
  )
  assert_true(
    submission_cancellation_lookup_original(
      Some(targeted_original(rows)),
      "scope",
      "saved-cancel",
      19,
      (table, cursor) => targeted_row_scan(rows, table, cursor),
      (_, _) => Err(-41),
      () => true,
    )
    is Err(-41),
  )
}
