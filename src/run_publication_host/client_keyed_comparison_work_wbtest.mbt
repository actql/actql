///|
test "keyed canonical comparison charges only actual length and UTF16 reads before exposing order" {
  let (lookup, cleanup, _) = keyed_work_original_fixture(
    keyed_work_rows(1),
    1,
    1000000,
  )
  defer cleanup() |> ignore
  // Literal independent outcomes preserve LENGTH-first String.compare,
  // including non-normalized Unicode, prefix and different-length cases.
  for
    (left, right, order, units) in [
      ("", "", 0, 1),
      ("b", "aa", -1, 1),
      ("ab", "ac", -1, 5),
      ("aaaXsuffix", "aaaYsuffix", -1, 9),
      ("😀x", "😀y", -1, 7),
      ("é", "é", -1, 1),
    ] {
    let before = client_keyed_lookup_input_work(lookup)
    assert_eq(keyed_lookup_order_compare(lookup, left, right).unwrap(), order)
    assert_eq(client_keyed_lookup_input_work(lookup) - before, units.to_int64())
  }
  assert_true(lookup.known.is_empty())
  assert_true(cleanup())
}

///|
test "keyed canonical comparison refuses one-short inspected pair without exposing order" {
  let (lookup, cleanup, _) = keyed_work_original_fixture(
    keyed_work_rows(1),
    1,
    1000000,
  )
  defer cleanup() |> ignore
  // Exact cost9; leave only8. Three equal pairs and the length step spend7,
  // then the last two-unit pair is refused BEFORE either unit is read.
  let before = client_keyed_lookup_input_work(lookup).to_int()
  assert_true(charge_keyed_lookup_input_work(lookup, 1000000 - before - 8))
  let spent = client_keyed_lookup_input_work(lookup)
  assert_true(
    keyed_lookup_order_compare(lookup, "aaaXsuffix", "aaaYsuffix")
    is Err(LookupLimit("work")),
  )
  assert_eq(client_keyed_lookup_input_work(lookup), spent + 7L)
  assert_true(lookup.known.is_empty())
  assert_true(cleanup())
}
