///|
// The real Local read authorization preimage starts with these literal keys.
// Canonical UTF-16 order is independent of Core's length-first String order.
test "Local read original keys use canonical order rather than shortlex" {
  let previous = "account_configuration_cid"
  let name = "adoption_cid"
  // Exact original guard; this is a source-bound scalar reproduction, not a
  // running Native Host or an authorized read.
  let original_guard : Result[Unit, String] = if previous >= name {
    Err("Encoding")
  } else {
    Ok(())
  }
  assert_eq(original_guard, Err("Encoding"))
  let w = writer(61, 3, 1)
  begin_ordered_object(w)
  ordered_key(w, previous)
  string_value(w, "ctx")
  ordered_key(w, name)
  string_value(w, "adoption")
  end_object(w)
  assert_eq(
    finish_text_usage(w),
    (
      "{\"account_configuration_cid\":\"ctx\",\"adoption_cid\":\"adoption\"}", 61,
      3, 1,
    ),
  )
}

///|
test "Local read canonical keys preserve the original same-length lane" {
  let w = writer(32, 3, 1)
  begin_ordered_object(w)
  ordered_key(w, "a")
  string_value(w, "e\u0301\r\n")
  ordered_key(w, "b")
  string_value(w, "é")
  end_object(w)
  assert_eq(finish(w), "{\"a\":\"e\u0301\\r\\n\",\"b\":\"é\"}")
}

///|
test "Local read canonical original refuses an insufficient exact capacity" {
  let w = writer(60, 3, 1)
  assert_true(
    try {
      begin_ordered_object(w)
      ordered_key(w, "account_configuration_cid")
      string_value(w, "ctx")
      ordered_key(w, "adoption_cid")
      string_value(w, "adoption")
      end_object(w)
      false
    } catch {
      OutputLimit => true
      _ => false
    },
  )
  assert_true(w.closed)
}
