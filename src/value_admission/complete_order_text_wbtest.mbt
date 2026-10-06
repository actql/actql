///|
fn text_order_drain(
  cursor : CompleteOrder,
  quantum : Int,
) -> (String, Int, Int) raise {
  let mut total = 0
  for _ in 0..<10000 {
    match advance_complete_order(cursor, quantum) {
      OrderContinue(work~) => {
        assert_true(work > 0 && work <= quantum)
        total += work
      }
      OrderComplete(text, bytes~, work~) => {
        assert_true(work >= 0 && work <= quantum)
        return (text, bytes, total + work)
      }
      OrderFailed(_, ..) => abort("unexpected order failure")
    }
  }
  abort("order exceeded finite fixture steps")
}

///|
test "complete order long escaped Text has independent wire and quantum invariant work" {
  let contract = @contract.primitive(@contract.StringType, nullable=false)
  for
    (text, escaped, logical_bytes, chunks) in [
      ("x".repeat(4096), "x".repeat(4096), 4096, 64),
      ("\\\"\n".repeat(128), "\\\\\\\"\\n".repeat(128), 384, 6),
      (
        "a".repeat(63) + "😀" + "\\\"\n".repeat(64),
        "a".repeat(63) + "😀" + "\\\\\\\"\\n".repeat(64),
        259,
        4,
      ),
    ] {
    let checked : CheckedValue = { contract, value: Text(text), }
    let limits : Limits = {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: logical_bytes,
    }
    let expected = "[\"text\",\"" + escaped + "\"]"
    let expected_bytes = @utf8.encode(expected).length()
    // Each side has node/setup + fixed 64-unit chunks + terminal. The
    // boundary-crossing surrogate pair is consumed together in one chunk.
    let expected_work = 4 + 2 * chunks
    for quantum in [1, 7, 256] {
      let (_, nodes, bytes) = recheck_runtime_value_usage(
        checked.value,
        contract,
        limits,
      ).unwrap()
      assert_eq(nodes, 1)
      assert_eq(bytes, logical_bytes)
      let cursor = start_complete_order(
        checked,
        limits,
        max_output_bytes=Some(expected_bytes),
      ).unwrap()
      let (actual, bytes, work) = text_order_drain(cursor, quantum)
      assert_eq(actual, expected)
      assert_eq(bytes, expected_bytes)
      assert_eq(work, expected_work)
      assert_true(cursor.out is None && cursor.pending.is_empty())
      // No complete key is available at the independently derived one-short
      // control allowance, regardless of how the caller partitions it.
      let short_work = start_complete_order(checked, limits).unwrap()
      let mut remaining = expected_work - 1
      while remaining > 0 {
        let allowed = Int::min(remaining, quantum)
        match advance_complete_order(short_work, allowed) {
          OrderContinue(work~) => remaining -= work
          _ => abort("order completed before its exact control allowance")
        }
      }
      cancel_complete_order(short_work)
      assert_true(
        advance_complete_order(short_work, 1) is OrderFailed(_, work=0),
      )
      let short_bytes = start_complete_order(
        checked,
        limits,
        max_output_bytes=Some(expected_bytes - 1),
      ).unwrap()
      for _ in 0..<10000 {
        match advance_complete_order(short_bytes, quantum) {
          OrderContinue(..) => ()
          OrderFailed(CompleteOrderLimit, ..) => break
          _ => abort("one-short order wire quota was not refused")
        }
      } nobreak {
        abort("one-short order wire did not stop")
      }
      assert_true(short_bytes.out is None && short_bytes.pending.is_empty())
      // Force failure inside an unfinished string, after its frame is popped.
      // The owner must still close the same writer and discard pending work.
      let middle_chunk = start_complete_order(
        checked,
        limits,
        max_output_bytes=Some(100),
      ).unwrap()
      for _ in 0..<10000 {
        match advance_complete_order(middle_chunk, quantum) {
          OrderContinue(..) => ()
          OrderFailed(CompleteOrderLimit, ..) => break
          _ => abort("middle-chunk quota was not refused")
        }
      } nobreak {
        abort("middle-chunk quota did not stop")
      }
      assert_true(middle_chunk.out is None && middle_chunk.pending.is_empty())
      cancel_complete_order(middle_chunk)
      assert_true(
        advance_complete_order(middle_chunk, 1) is OrderFailed(_, work=0),
      )
      let short_value = start_complete_order(checked, {
        ..limits,
        max_text_bytes: logical_bytes - 1,
      }).unwrap()
      assert_true(
        advance_complete_order(short_value, 256) is OrderFailed(_, ..),
      )
    }
  }
}

///|
test "complete order long object name yields with independent wire work and cleanup" {
  let name = "n\"\\".repeat(128)
  let escaped_name = "n\\\"\\\\".repeat(128)
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let contract = @contract.object_contract(
    [(name, number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=384,
  ).unwrap()
  let checked : CheckedValue = {
    contract,
    value: Object({ values: [(name, Number(1.0))], }),
  }
  let limits : Limits = { max_nodes: 2, max_depth: 1, max_text_bytes: 384, }
  let expected = "[\"object\",[[\"" + escaped_name + "\",[\"number\",1]]]]"
  for quantum in [1, 7, 256] {
    let (_, nodes, bytes) = recheck_runtime_value_usage(
      checked.value,
      contract,
      limits,
    ).unwrap()
    assert_eq(nodes, 2)
    assert_eq(bytes, 384)
    let cursor = start_complete_order(checked, limits).unwrap()
    let (actual, bytes, work) = text_order_drain(cursor, quantum)
    assert_eq(actual, expected)
    assert_eq(bytes, @utf8.encode(expected).length())
    // Recheck: root + two field visits + six 64-unit name fragments
    // + Number + terminal = 11.
    // Emit: two values + two field visits + entry/aggregate closes + terminal
    // + six fixed name chunks = 13. Logical two-node/384-byte usage is unchanged.
    assert_eq(work, 24)
  }
  let cursor = start_complete_order(checked, limits).unwrap()
  while cursor.recheck is Some(_) {
    assert_true(advance_complete_order(cursor, 1) is OrderContinue(work=1))
  }
  // Object frame, field setup, then one of six name chunks.
  assert_true(advance_complete_order(cursor, 3) is OrderContinue(work=3))
  assert_true(
    cursor.pending[cursor.pending.length() - 1] is OrderText(_, false),
  )
  cancel_complete_order(cursor)
  cancel_complete_order(cursor)
  assert_true(cursor.out is None && cursor.pending.is_empty())
  assert_true(advance_complete_order(cursor, 1) is OrderFailed(_, work=0))
  guard checked.value is Object(fields) else { abort("object expected") }
  assert_eq(element_count(fields), 1)
}

///|
test "typed JSON order preserves its domain with bounded Text emission" {
  let payload = "a".repeat(63) + "😀" + "b".repeat(4031)
  let checked : CheckedValue = {
    contract: @contract.primitive(@contract.JsonType, nullable=false),
    value: JsonData(Text(payload)),
  }
  let limits : Limits = { max_nodes: 1, max_depth: 0, max_text_bytes: 4098, }
  let expected = "[\"json\",[\"text\",\"" + payload + "\"]]"
  let expected_bytes = @utf8.encode(expected).length()
  // Recheck uses 64 chunks and setup/terminal. Emission has the same 64
  // chunks plus payload read, wrapper read/close and terminal: 134 total.
  for quantum in [1, 7, 256] {
    let cursor = start_complete_order(
      checked,
      limits,
      max_output_bytes=Some(expected_bytes),
    ).unwrap()
    let (actual, bytes, work) = text_order_drain(cursor, quantum)
    assert_eq(actual, expected)
    assert_eq(bytes, expected_bytes)
    assert_eq(work, 134)
    assert_true(cursor.out is None && cursor.pending.is_empty())
    let cancelled = start_complete_order(checked, limits).unwrap()
    assert_true(advance_complete_order(cancelled, 70) is OrderContinue(work=70))
    cancel_complete_order(cancelled)
    assert_true(cancelled.out is None && cancelled.pending.is_empty())
    assert_true(
      advance_complete_order(cancelled, quantum) is OrderFailed(_, work=0),
    )
  }
}

///|
test "typed JSON order separates SQL null and nested JSON payloads" {
  let contract = @contract.primitive(@contract.JsonType, nullable=true)
  let limits : Limits = { max_nodes: 20, max_depth: 5, max_text_bytes: 100, }
  let sql_null = order_checked(contract, "null")
  assert_eq(complete_order_key(sql_null, limits).unwrap(), "[\"null\"]")
  for
    (source, expected) in [
      ("null", "[\"json\",[\"null\"]]"),
      ("[null,1]", "[\"json\",[\"array\",[[\"null\"],[\"number\",1]]]]"),
      (
        "{\"x\":[true]}", "[\"json\",[\"object\",[[\"x\",[\"array\",[[\"boolean\",true]]]]]]]",
      ),
    ] {
    let (checked, _, _) = admit_json_literal(source, limits).unwrap()
    for quantum in [1, 7, 256] {
      let cursor = start_complete_order(checked, limits).unwrap()
      let (actual, bytes, _) = text_order_drain(cursor, quantum)
      assert_eq(actual, expected)
      assert_eq(bytes, @utf8.encode(expected).length())
      assert_true(cursor.out is None && cursor.pending.is_empty())
    }
  }
}
