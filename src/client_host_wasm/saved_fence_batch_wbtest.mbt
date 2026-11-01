///|
// Actual pure saved-reader coordinator with explicit physical ports. These
// ports do not assert Host/current/Account/FD or normal runtime acceptance.
fn saved_fence_batch_fixture() -> Array[(String, String, Int64, Bytes)] {
  [
    ("public_index", "scope", 0L, b"original-index"),
    ("publication_contract", "first", 1L, b"{\"x\":1}"),
    ("publication_contract", "second", 2L, b"original\r\n"),
    ("publication_contract", "third", 3L, b""),
  ]
}

///|
test "saved fence batch keeps exact original fields and one physical packet" {
  let fences = saved_fence_batch_fixture()
  let expected = "[[\"first\",\"1\",\"{\\\"x\\\":1}\"],[\"second\",\"2\",\"original\\r\\n\"],[\"third\",\"3\",\"\"]]"
  assert_eq(saved_result_fence_packet(fences, 1), Some((expected, 4)))
  let mut scalar = 0
  let mut packets = 0
  let actual = validate_saved_result_fences(
    fences,
    (table, key) => {
      scalar += 1
      if table == "public_index" && key == "scope" {
        Ok(Some({ key, revision: 0L, body: b"original-index", }))
      } else {
        Err(-97)
      }
    },
    wire => {
      packets += 1
      if wire == expected {
        Ok(Some(true))
      } else {
        Err(-98)
      }
    },
  )
  assert_eq(actual, Ok(()))
  assert_eq(scalar, 1)
  assert_eq(packets, 1)
}

///|
test "saved fence batch refuses mismatch and original error without scalar fallback" {
  let fences = saved_fence_batch_fixture()[1:].to_array()
  for result in [Ok(Some(false)), Err(-74)] {
    let mut scalar = 0
    let actual = validate_saved_result_fences(
      fences,
      (_, _) => {
        scalar += 1
        Err(-97)
      },
      _ => result,
    )
    assert_eq(
      actual,
      match result {
        Err(code) => Err(code)
        _ => Err(-32)
      },
    )
    assert_eq(scalar, 0)
  }
}

///|
test "saved fence batch keeps scalar adapter and unbatchable byte semantics" {
  let fences = saved_fence_batch_fixture()
  let mut scalar = 0
  let mut packets = 0
  let actual = validate_saved_result_fences(
    fences,
    (table, key) => {
      scalar += 1
      match fences.find(item => item.0 == table && item.1 == key) {
        Some((_, key, revision, body)) => Ok(Some({ key, revision, body, }))
        None => Ok(None)
      }
    },
    _ => {
      packets += 1
      Ok(None)
    },
  )
  assert_eq(actual, Ok(()))
  assert_eq(scalar, 4)
  assert_eq(packets, 1)
  let binary = [("publication_contract", "binary", 0L, b"\xff")]
  assert_eq(saved_result_fence_packet(binary, 0), None)
  let large = [
    ("publication_contract", "large", 0L, @utf8.encode("a".repeat(4096))),
  ]
  assert_eq(saved_result_fence_packet(large, 0), None)
  assert_eq(saved_result_fence_packet(fences, 0), None)
}
