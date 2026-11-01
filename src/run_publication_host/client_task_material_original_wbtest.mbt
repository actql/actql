///|
test "retained task materials preserve the logical cap across bounded UTF8 chunks" {
  let key = "sha256:" + "a".repeat(64)
  let wire = "a".repeat(131071) + "😀" + "b".repeat(131068) + "x"
  let cid = client_task_material_original_cid(wire).unwrap()
  let chunks = client_task_material_original_chunks(key, wire).unwrap()
  assert_eq(chunks.length(), 3)
  let rows = chunks.map(chunk => {
    ("client_task_run_materials", inventory_row(chunk.0, @utf8.encode(chunk.1)))
  })
  for (_, row) in rows {
    assert_true(row.body.length() <= 131072)
  }
  assert_eq(
    read_client_task_material_original(
      key,
      cid,
      (table, name) => inventory_read(rows, table, name),
      "custody",
    ),
    Ok(wire),
  )
  assert_true(
    client_task_material_original_chunks(key, wire + "x")
    is Err(CapacityExceeded),
  )
  for missing in 0..<3 {
    let incomplete : Array[(String, ClientJournalPhysicalRow)] = []
    for index in 0..<rows.length() {
      if index != missing {
        incomplete.push(rows[index])
      }
    }
    assert_eq(
      read_client_task_material_original(
        key,
        cid,
        (table, name) => inventory_read(incomplete, table, name),
        "custody",
      ),
      Err("custody"),
    )
  }
  let extra = rows.copy()
  extra.push(("client_task_run_materials", inventory_row(key + ":3", b"x")))
  assert_eq(
    read_client_task_material_original(
      key,
      cid,
      (table, name) => inventory_read(extra, table, name),
      "custody",
    ),
    Err("custody"),
  )
}

///|
test "whole Run inventory requires every original task chunk and rejects unattached rows" {
  let original = inventory_run_original()
  let key = client_request_scope_cid(original.request)
  let wire = "original task materials"
  let cid = client_task_material_original_cid(wire).unwrap()
  let rows = inventory_run_rows()
  for (name, body) in client_task_material_original_chunks(key, wire).unwrap() {
    rows.push(
      ("client_task_run_materials", inventory_row(name, @utf8.encode(body))),
    )
  }
  let pointed = { ..original, task_materials_cid: Some(cid), }
  assert_true(inventory_check(rows, original=pointed) is Ok(_))
  assert_eq(
    inventory_check(inventory_run_rows(), original=pointed),
    Err("custody"),
  )
  assert_eq(inventory_check(rows), Err("custody"))
  rows.push(("client_task_run_materials", inventory_row(key + ":4", b"extra")))
  assert_eq(inventory_check(rows, original=pointed), Err("custody"))
}

///|
test "Run task-material pointer is optional exact DATA and rejects null malformed CIDs" {
  let original = journal_encoding_original()
  let cid = "sha256:" + "a".repeat(64)
  let wire = client_run_journal_row_body({
    ..original,
    task_materials_cid: Some(cid),
  }).unwrap()
  assert_eq(
    decode_client_run_journal_row(wire).unwrap().task_materials_cid,
    Some(cid),
  )
  assert_eq(
    client_run_journal_row_body(decode_client_run_journal_row(wire).unwrap()).unwrap(),
    wire,
  )
  let text = @utf8.decode(wire)
  for replacement in ["null", "\"invalid\""] {
    assert_true(
      decode_client_run_journal_row(
        @utf8.encode(text.replace(old="\"" + cid + "\"", new=replacement)),
      )
      is Err(CustodyLost),
    )
  }
}
