///|
test "representation extent counts original Unicode keys values and containers" {
  let original = from_json(
    { "a": ["e\u0301", "😀", Json::null()], "b": { "x": true } },
    20,
    8,
    100,
    data_keys=true,
  )
  let before = stringify_value(original, 1024, 20, 8)
  let extent = representation_extent(original, 20, 8, 100).unwrap()
  assert_eq(extent.nodes, 7L)
  assert_eq(extent.strings, 5L)
  assert_eq(extent.text_utf16_units, 7L)
  assert_eq(extent.arrays, 1L)
  assert_eq(extent.objects, 2L)
  assert_true(extent.array_backing_slots >= 3L)
  assert_true(extent.object_backing_slots >= 3L)
  assert_eq(stringify_value(original, 1024, 20, 8), before)
  assert_true(representation_extent(original, 6, 8, 100) is Err(InputLimit))
  assert_true(representation_extent(original, 20, 1, 100) is Err(InputLimit))
  assert_true(representation_extent(original, 20, 8, 6) is Err(InputLimit))
}

///|
test "representation extent counts repeated shared values and refuses invalid limits" {
  let shared : CanonicalValue = String("e\u0301")
  let value : CanonicalValue = Array({ values: [shared, shared], })
  let extent = representation_extent(value, 3, 1, 4).unwrap()
  assert_eq(extent.nodes, 3L)
  assert_eq(extent.strings, 2L)
  assert_eq(extent.text_utf16_units, 4L)
  assert_true(representation_extent(value, 0, 1, 4) is Err(InputLimit))
  assert_true(representation_extent(value, 3, -1, 4) is Err(InputLimit))
  assert_true(representation_extent(value, 3, 1, -1) is Err(InputLimit))
}

///|
test "funded representation walk visits original frames rather than String units" {
  let short : CanonicalValue = Array({ values: [String("a"), String("b")], })
  let wide : CanonicalValue = Array({
    values: [String("a".repeat(16384)), String("b".repeat(16384))],
  })
  let short_spent : Ref[Int] = Ref(0)
  let short_extent = representation_extent_with_work(short, 3, 1, 32768, units => {
    short_spent.val += units
    true
  }).unwrap()
  let wide_spent : Ref[Int] = Ref(0)
  let wide_extent = representation_extent_with_work(wide, 3, 1, 32768, units => {
    wide_spent.val += units
    true
  }).unwrap()
  assert_true(short_spent.val > 0)
  assert_eq(wide_spent.val, short_spent.val)
  assert_eq(short_extent, representation_extent(short, 3, 1, 32768).unwrap())
  assert_eq(wide_extent, representation_extent(wide, 3, 1, 32768).unwrap())
  assert_eq(wide_extent.text_utf16_units, 32768L)
}

///|
test "funded representation walk preserves one receipt on refusal and original limits" {
  let value : CanonicalValue = Array({ values: [String("a"), String("b")], })
  let remaining : Ref[Int] = Ref(1)
  let calls : Ref[Int] = Ref(0)
  let work = fn(units : Int) {
    calls.val += 1
    if units > remaining.val {
      false
    } else {
      remaining.val -= units
      true
    }
  }
  assert_true(
    representation_extent_with_work(value, 3, 1, 2, work) is Err(InputLimit),
  )
  assert_eq(remaining.val, 0)
  let stopped = calls.val
  assert_true(
    representation_extent_with_work(value, 3, 1, 2, work) is Err(InputLimit),
  )
  assert_eq(remaining.val, 0)
  assert_eq(calls.val, stopped + 1)
  assert_eq(representation_extent(value, 3, 1, 2).unwrap().nodes, 3L)
  let observed : Ref[Bool] = Ref(false)
  assert_true(
    representation_extent_with_work(value, 0, 1, 2, _ => {
      observed.val = true
      true
    })
    is Err(InputLimit),
  )
  assert_false(observed.val)
  assert_true(
    representation_extent_with_work(value, 2, 1, 2, _ => true)
    is Err(InputLimit),
  )
  assert_true(
    representation_extent_with_work(value, 3, 0, 2, _ => true)
    is Err(InputLimit),
  )
  assert_true(
    representation_extent_with_work(value, 3, 1, 1, _ => true)
    is Err(InputLimit),
  )
}
