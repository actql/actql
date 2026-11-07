///|
test "GCS fixed facts quote uses original identifiers and actual eight decimal slots" {
  let cid = "sha256:" + "a".repeat(64)
  let values = [100L, 200L, 2L, 3L, 4000000L, 30000L, 1024L, 1000000L]
  let two = source_facts_construction_capacity(2, cid, cid, cid, cid, values).unwrap()
  let three = source_facts_construction_capacity(3, cid, cid, cid, cid, values).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(three)
  println("GCS fixed facts three_views peak_bytes=\{peak}")
  assert_true(peak < 1000000L)
  assert_true(peak > @execution.execution_capacity_execution_bytes(two))
  assert_eq(@execution.execution_capacity_retained_bytes(three), peak)
  let wide = source_facts_construction_capacity(3, cid, cid, cid, cid, [
    9007199254740991L, 9007199254740991L, 9007199254740991L, 9007199254740991L, 9007199254740991L,
    9007199254740991L, 9007199254740991L, 9007199254740991L,
  ]).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(wide) > peak)
  // Malformed CID text can allocate canonical output before later refusal.
  let escaped = source_facts_construction_capacity(
    3,
    "\"\\\n".repeat(100),
    cid,
    cid,
    cid,
    values,
  ).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(escaped) > peak)
}

///|
test "GCS fixed facts rejects unsupported geometry without changing operator limits" {
  assert_true(
    source_facts_construction_capacity(4, "", "", "", "", [
      1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L,
    ])
    is None,
  )
  assert_true(
    source_facts_construction_capacity(3, "", "", "", "", [1L]) is None,
  )
  assert_true(
    source_facts_construction_capacity(3, "", "", "", "", [
      1L, 1L, 1L, 1L, 1L, 1L, 1L, -1L,
    ])
    is None,
  )
  assert_true(
    source_facts_construction_capacity(3, "", "", "", "", [
      1L, 1L, 1L, 1L, 1L, 1L, 1L, 9007199254740992L,
    ])
    is None,
  )
}
