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
test "a same-reader Task range count replaces only the second body census" {
  let original = inventory_run_original()
  let key = client_request_scope_cid(original.request)
  let wire = "verified Task chunks"
  let cid = client_task_material_original_cid(wire).unwrap()
  let chunk = inventory_row(key + ":0", @utf8.encode(wire))
  let rows = inventory_run_rows()
  rows.push(("client_task_run_materials", chunk))
  let task_original : ClientTaskMaterialsOriginal[Unit]? = None
  let calls : Array[String] = []
  let run = (contents, fact) => {
    calls.clear()
    inspect_client_run_journal_inventory_with_task_original(
      8,
      (table, cursor) => {
        if table == "client_task_run_materials" {
          calls.push("scan")
        }
        inventory_scan(contents, table, cursor)
      },
      (table, name) => {
        if table == "client_task_run_materials" {
          calls.push(name)
        }
        inventory_read(contents, table, name)
      },
      _ => Ok({ ..original, task_materials_cid: Some(cid), }),
      () => {
        calls.push("cancellation")
        Ok(())
      },
      "custody",
      task_original,
      task_material_count=Some(expected => {
        if expected != 1 {
          return Err("unexpected count")
        }
        calls.push("count")
        fact
      }),
    )
  }
  let exact = [
    key + ":0",
    key + ":1",
    key + ":2",
    key + ":3",
    "count",
    "cancellation",
  ]
  assert_true(run(rows, Ok(Some(true))) is Ok(_))
  assert_eq(calls, exact)
  assert_true(run(rows, Ok(None)) is Ok(_))
  assert_eq(calls[4:8].to_owned(), ["count", "scan", "scan", "cancellation"])
  assert_eq(run(rows, Err("physical query")), Err("physical query"))
  assert_eq(calls[4:].to_owned(), ["count"])
  assert_eq(run(rows, Ok(Some(false))), Err("custody"))
  assert_eq(calls[4:].to_owned(), ["count", "scan", "scan"])
  let orphan = rows.copy()
  orphan.push(
    ("client_task_run_materials", inventory_row(key + ":4", b"extra")),
  )
  assert_eq(run(orphan, Ok(Some(false))), Err("custody"))
  assert_eq(calls[4:].to_owned(), ["count", "scan", "scan"])
  let changed = inventory_run_rows()
  changed.push(("client_task_run_materials", { ..chunk, revision: 1L, }))
  assert_eq(run(changed, Ok(Some(true))), Err("custody"))
  assert_eq(calls, [key + ":0"])
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
test "exact saved material skips the fresh hash only after every canonical row probe" {
  let key = "sha256:" + "a".repeat(64)
  let first = "a".repeat(131070)
  let tail = "😀\u{feff}z"
  let wire = first + tail
  let cid = client_task_material_original_cid(wire).unwrap()
  let keys = [key + ":0", key + ":1", key + ":2", key + ":3"]
  let reads : Array[String] = []
  let hashed : Array[Int] = []
  let digest = (bytes : Bytes) => {
    hashed.push(bytes.length())
    @sha.hex(bytes)
  }
  let reobserve = (first, tail, fourth) => {
    reads.clear()
    read_saved_task_material_original(
      key,
      cid,
      Some(wire),
      (slot, name) => {
        if slot != reads.length() || slot >= keys.length() || name != keys[slot] {
          return Err("foreign slot")
        }
        reads.push(name)
        if name == keys[0] {
          Ok(Some(inventory_row(name, first)))
        } else if name == keys[1] {
          Ok(Some(inventory_row(name, tail)))
        } else if name == keys[3] {
          fourth
        } else {
          Ok(None)
        }
      },
      "custody",
      digest~,
    )
  }
  assert_eq(
    reobserve(@utf8.encode(first), @utf8.encode(tail), Ok(None)),
    Ok(wire),
  )
  assert_eq(reads, keys)
  assert_true(hashed.is_empty())
  // The same wire split one scalar too early must go through the original
  // validator and reject, even though its complete SHA is unchanged.
  assert_eq(
    reobserve(
      @utf8.encode("a".repeat(131069)),
      @utf8.encode("a" + tail),
      Ok(None),
    ),
    Err("custody"),
  )
  assert_eq(reads, keys)
  assert_eq(hashed, [131078])
  assert_eq(
    reobserve(@utf8.encode(first), @utf8.encode("😀\u{feff}x"), Ok(None)),
    Err("custody"),
  )
  assert_eq(reads, keys)
  assert_eq(hashed, [131078, 131078])
  assert_eq(
    reobserve(
      @utf8.encode(first),
      @utf8.encode(tail),
      Err("fourth physical query"),
    ),
    Err("fourth physical query"),
  )
  assert_eq(reads, keys)
  assert_eq(hashed, [131078, 131078])
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

///|
test "retained material original skips codec work only after fresh complete bytes" {
  let key = "sha256:" + "a".repeat(64)
  let wire = "original task materials"
  let original = capture_client_task_materials_original(
    (),
    key,
    wire,
    () => Ok("policy"),
    _ => "encoding",
  ).unwrap()
  let cid = client_task_materials_original_cid(original)
  let reads = Ref(0)
  let hashes = Ref(0)
  let changed = Ref(false)
  let read = (_, name) => {
    reads.val += 1
    if name == key + ":0" {
      Ok(
        Some(
          inventory_row(
            name,
            if changed.val {
              b"changed"
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
    assert_eq(
      read_task_material_original_details_with_original(
        key,
        cid,
        read,
        "custody",
        Some(original),
        digest~,
      ).unwrap().0,
      wire,
    )
  }
  assert_eq(reads.val, 8)
  assert_eq(hashes.val, 0)
  let foreign = capture_client_task_materials_original(
    (),
    "sha256:" + "b".repeat(64),
    wire,
    () => Ok("policy"),
    _ => "encoding",
  ).unwrap()
  assert_eq(
    read_task_material_original_details_with_original(
      key,
      cid,
      read,
      "custody",
      Some(foreign),
      digest~,
    ).unwrap().0,
    wire,
  )
  assert_eq(hashes.val, 1)
  let cold : ClientTaskMaterialsOriginal[Unit]? = None
  assert_eq(
    read_task_material_original_details_with_original(
      key,
      cid,
      read,
      "custody",
      cold,
      digest~,
    ).unwrap().0,
    wire,
  )
  assert_eq(hashes.val, 2)
  changed.val = true
  assert_true(
    read_task_material_original_details_with_original(
      key,
      cid,
      read,
      "custody",
      Some(original),
      digest~,
    )
    is Err("custody"),
  )
  assert_eq(hashes.val, 3)
  assert_eq(reads.val, 20)
}

///|
test "retained material original keeps corruption canonical and current refusals" {
  let key = "sha256:" + "a".repeat(64)
  let wire = "original task materials"
  let original = capture_client_task_materials_original(
    (),
    key,
    wire,
    () => Ok("policy"),
    _ => "encoding",
  ).unwrap()
  let cid = client_task_materials_original_cid(original)
  let split = [
    ("client_task_run_materials", inventory_row(key + ":0", b"original ")),
    ("client_task_run_materials", inventory_row(key + ":1", b"task materials")),
  ]
  assert_true(
    read_client_task_material_with_original(
      key,
      cid,
      (table, name) => inventory_read(split, table, name),
      "custody",
      Some(original),
    )
    is Err("custody"),
  )
  for
    row in [
      inventory_row(key + ":0", b"changed"),
      { key: key + ":0", revision: 1L, body: @utf8.encode(wire), },
      inventory_row(key + ":0", b"\xff"),
    ] {
    assert_true(
      read_client_task_material_with_original(
        key,
        cid,
        (_, name) => Ok(if name == key + ":0" { Some(row) } else { None }),
        "custody",
        Some(original),
      )
      is Err("custody"),
    )
  }
  assert_eq(
    read_client_task_material_with_original(
      key,
      cid,
      (_, _) => Err("current changed"),
      "custody",
      Some(original),
    ),
    Err("current changed"),
  )
  assert_eq(
    read_client_task_material_with_original(
      key,
      cid,
      (_, _) => Err("cancelled"),
      "custody",
      Some(original),
    ),
    Err("cancelled"),
  )
  let copy = client_task_materials_original_chunks(original)
  copy[0] = (key + ":0", "foreign")
  assert_eq(client_task_materials_original_chunks(original), [
    (key + ":0", wire),
  ])
}

///|
test "retained material constructor preserves extent hash chunks then policy refusal" {
  let calls = Ref(0)
  let policy = () => {
    calls.val += 1
    Err("original policy")
  }
  assert_true(
    capture_client_task_materials_original((), "bad", "", policy, _ => "extent")
    is Err("extent"),
  )
  assert_eq(calls.val, 0)
  assert_true(
    capture_client_task_materials_original((), "bad", "wire", policy, _ => "key")
    is Err("key"),
  )
  assert_eq(calls.val, 0)
  assert_true(
    capture_client_task_materials_original(
      (),
      "sha256:" + "a".repeat(64),
      "wire",
      policy,
      _ => "encoding",
    )
    is Err("original policy"),
  )
  assert_eq(calls.val, 1)
}

///|
test "retained material inventory repeats full scopes and cancellation with original" {
  let current = inventory_run_original()
  let key = client_request_scope_cid(current.request)
  let wire = "original task materials"
  let original = capture_client_task_materials_original(
    (),
    key,
    wire,
    () => Ok("policy"),
    _ => "encoding",
  ).unwrap()
  let pointed = {
    ..current,
    task_materials_cid: Some(client_task_materials_original_cid(original)),
  }
  let rows = inventory_run_rows()
  for (name, body) in client_task_materials_original_chunks(original) {
    rows.push(
      ("client_task_run_materials", inventory_row(name, @utf8.encode(body))),
    )
  }
  let seen : Array[String] = []
  let chunk_reads = Ref(0)
  let cancellations = Ref(0)
  let reject = Ref(false)
  let inspect = () => {
    inspect_client_run_journal_inventory_with_task_original(
      1024,
      (table, cursor) => {
        seen.push(table)
        inventory_scan(rows, table, cursor)
      },
      (table, name) => {
        if table == "client_task_run_materials" {
          chunk_reads.val += 1
        }
        inventory_read(rows, table, name)
      },
      _ => Ok(pointed),
      () => {
        cancellations.val += 1
        if reject.val {
          Err("cancel-current")
        } else {
          Ok(())
        }
      },
      "custody",
      Some(original),
    )
  }
  assert_true(inspect() is Ok(_))
  assert_true(inspect() is Ok(_))
  assert_eq(chunk_reads.val, 8)
  assert_eq(cancellations.val, 2)
  for
    table in [
      "client_runs", "client_task_run_materials", "client_effect_custody", "client_effect_response_meta",
      "client_effect_response_bytes", "client_effect_row_receipt",
    ] {
    assert_true(seen.contains(table))
  }
  reject.val = true
  assert_eq(inspect(), Err("cancel-current"))
  assert_eq(cancellations.val, 3)
  rows.push(("client_task_run_materials", inventory_row(key + ":4", b"orphan")))
  reject.val = false
  assert_eq(inspect(), Err("custody"))
}
