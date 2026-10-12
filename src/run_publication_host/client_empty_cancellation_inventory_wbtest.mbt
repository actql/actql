///|
fn empty_cancel_check(
  rows : Array[(String, ClientJournalPhysicalRow)],
) -> Result[Unit, String] {
  inspect_client_empty_cancellation_inventory(
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    "custody",
    "unsupported",
  )
}

///|
test "empty cancellation proof observes original issued metadata and both full scopes" {
  let rows = [("client_cancel_custody", inventory_row("issued", b"0"))]
  let visited : Array[String] = []
  assert_eq(
    inspect_client_empty_cancellation_inventory(
      1024,
      (table, cursor) => {
        visited.push(table)
        inventory_scan(rows, table, cursor)
      },
      (table, key) => inventory_read(rows, table, key),
      "custody",
      "unsupported",
    ),
    Ok(()),
  )
  assert_eq(visited, [
    "client_cancel_custody", "client_cancel_custody", "client_cancellations", "client_cancel_originals",
  ])
}

///|
test "missing malformed cancellation custody is not initialized or an empty scope" {
  assert_eq(empty_cancel_check([]), Err("custody"))
  for body in [b"01", b"-1", b"1025", b"0\n", b""] {
    assert_eq(
      empty_cancel_check([
        ("client_cancel_custody", inventory_row("issued", body)),
      ]),
      Err("custody"),
    )
  }
  assert_eq(
    empty_cancel_check([
      ("client_cancel_custody", inventory_row("issued", b"0", revision=1L)),
    ]),
    Err("custody"),
  )
  assert_eq(
    empty_cancel_check([
      ("client_cancel_custody", inventory_row("issued", b"1", revision=0L)),
    ]),
    Err("custody"),
  )
}

///|
test "nonempty valid issuance needs original cancellation validator rather than reduced scope success" {
  assert_eq(
    empty_cancel_check([
      ("client_cancel_custody", inventory_row("issued", b"1", revision=1L)),
    ]),
    Err("unsupported"),
  )
}

///|
test "zero issuance with orphan operation or witness is custody loss not success" {
  for
    table in [
      "client_cancel_custody", "client_cancellations", "client_cancel_originals",
    ] {
    assert_eq(
      empty_cancel_check([
        ("client_cancel_custody", inventory_row("issued", b"0")),
        (table, inventory_row("unknown", b"orphan")),
      ]),
      Err("custody"),
    )
  }
}

///|
test "cancellation physical query failure is distinct from confirmed missing or empty" {
  let rows = [("client_cancel_custody", inventory_row("issued", b"0"))]
  for
    failed in [
      "client_cancel_custody", "client_cancellations", "client_cancel_originals",
    ] {
    assert_eq(
      inspect_client_empty_cancellation_inventory(
        1024,
        (table, cursor) => {
          if table == failed {
            Err("query")
          } else {
            inventory_scan(rows, table, cursor)
          }
        },
        (table, key) => inventory_read(rows, table, key),
        "custody",
        "unsupported",
      ),
      Err("query"),
    )
  }
  assert_eq(
    inspect_client_empty_cancellation_inventory(
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (_, _) => Err("read-query"),
      "custody",
      "unsupported",
    ),
    Err("read-query"),
  )
}
