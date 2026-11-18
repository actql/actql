///|
test "retained task materials preserve the logical cap across bounded UTF8 chunks" {
  let key = "sha256:" + "a".repeat(64)
  let wire = "a".repeat(131071) + "😀" + "b".repeat(131068) + "x"
  let cid = client_task_material_original_cid(wire).unwrap()
  let chunks = client_task_material_original_chunks(key, wire).unwrap()
  assert_eq(chunks.length(), 3)
  // The physical copy bound is UTF-8 Bytes, including a multibyte seam;
  // String code units are not a substitute for the observed SQLite extent.
  assert_eq(chunks.map(chunk => @utf8.encode(chunk.1).length()), [
    131071, 131072, 1,
  ])
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

///|
test "single-pass materials retain independent raw Unicode CID vectors" {
  // Independently SHA256-hashed raw UTF8 preimages, not product output.
  assert_eq(
    client_task_material_original_cid("original task materials").unwrap(),
    "sha256:999ffd0893e091d256f0094891b3a4e04c5a0ee224d42139336bf403a970c170",
  )
  assert_eq(
    client_task_material_original_cid("é\r\n😀").unwrap(),
    "sha256:91f2dd4a4804cafa6fccf3d25d73607f80a4e9f2e3edf83640f7dcdd04c57bd5",
  )
  assert_true(client_task_material_original_cid("") is Err(CapacityExceeded))
  assert_true(
    client_task_material_original_chunks("foreign", "") is Err(Encoding),
  )
}

///|
test "single-pass fresh reader hashes once per read and retains every physical probe" {
  let key = "sha256:" + "a".repeat(64)
  let wire = "original task materials"
  let cid = "sha256:999ffd0893e091d256f0094891b3a4e04c5a0ee224d42139336bf403a970c170"
  let reads : Array[String] = []
  let hashes = Ref(0)
  let changed = Ref(false)
  let read = (table, name) => {
    if table != "client_task_run_materials" {
      return Err("foreign table")
    }
    reads.push(name)
    if name == key + ":0" {
      Ok(
        Some(
          inventory_row(
            name,
            if changed.val {
              b"changed task materials"
            } else {
              @utf8.encode(wire)
            },
          ),
        ),
      )
    } else {
      Ok(None)
    }
  }
  let digest = bytes => {
    hashes.val += 1
    @sha.hex(bytes)
  }
  for _ in 0..<2 {
    let details = read_task_material_original_details(
      key,
      cid,
      read,
      "custody",
      digest~,
    ).unwrap()
    assert_eq(details.0, wire)
    assert_eq(details.1, [(key + ":0", wire)])
  }
  assert_eq(hashes.val, 2)
  assert_eq(reads, [
    key + ":0",
    key + ":1",
    key + ":2",
    key + ":3",
    key + ":0",
    key + ":1",
    key + ":2",
    key + ":3",
  ])
  changed.val = true
  assert_true(
    read_task_material_original_details(key, cid, read, "custody", digest~)
    is Err("custody"),
  )
  assert_eq(hashes.val, 3)
  assert_eq(reads.length(), 12)
}

///|
test "single-pass reader rejects foreign revised malformed and noncanonical chunks" {
  let key = "sha256:" + "a".repeat(64)
  let cid = "sha256:999ffd0893e091d256f0094891b3a4e04c5a0ee224d42139336bf403a970c170"
  // Identical concatenated bytes/CID do not authorize a different split.
  let split = [
    ("client_task_run_materials", inventory_row(key + ":0", b"original ")),
    ("client_task_run_materials", inventory_row(key + ":1", b"task materials")),
  ]
  assert_true(
    read_client_task_material_original(
      key,
      cid,
      (table, name) => inventory_read(split, table, name),
      "custody",
    )
    is Err("custody"),
  )
  for
    row in [
      inventory_row(
        "sha256:" + "b".repeat(64) + ":0",
        b"original task materials",
      ),
      inventory_row(key + ":0", b"original task materials", revision=1L),
      inventory_row(key + ":0", b"\xff"),
    ] {
    assert_true(
      read_client_task_material_original(
        key,
        cid,
        (_, name) => if name == key + ":0" { Ok(Some(row)) } else { Ok(None) },
        "custody",
      )
      is Err("custody"),
    )
  }
}
