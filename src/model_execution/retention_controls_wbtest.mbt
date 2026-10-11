///|
test "Model retention inventory: map backing survives logical cleanup" {
  // Independent boundary vectors for the actual pinned builtin Map: initial
  // eight slots and floor(13 * capacity / 16) growth. The separately named
  // HashMap has different thresholds and is not the Model state's Map type.
  // These are structural counts, not allocator byte measurements.
  for
    (rows, slots) in [
      (0, 8),
      (1, 8),
      (6, 8),
      (7, 16),
      (13, 16),
      (14, 32),
      (26, 32),
      (27, 64),
    ] {
    let values : Map[Int, Int] = Map([])
    for ordinal in 0..<rows {
      values[ordinal] = ordinal
    }
    assert_eq(values.length(), rows)
    assert_eq(values.capacity(), slots)
    if rows > 0 {
      values[0] = -1
      assert_eq(values.length(), rows)
      assert_eq(values.capacity(), slots)
    }
    values.clear()
    assert_eq(values.length(), 0)
    assert_eq(values.capacity(), slots)
    for ordinal in 0..<rows {
      assert_true(values.get(ordinal) is None)
    }
    // Retired entries do not imply retirement of their FixedArray. Reusing
    // the same original owner does not create a new eight-slot map.
    for ordinal in 0..<rows {
      values[ordinal] = ordinal + 1
    }
    assert_eq(values.length(), rows)
    assert_eq(values.capacity(), slots)
  }
}

///|
test "Model retention inventory: retired owned arrays have no backing slots" {
  let original = Ref(17)
  let values = [original, Ref(23), Ref(41)]
  assert_eq(values.length(), 3)
  assert_true(values.capacity() >= 3)
  let same_owner_array = values
  retire_model_owned_array(values)
  assert_true(physical_equal(values, same_owner_array))
  assert_eq(values.length(), 0)
  assert_eq(values.capacity(), 0)
  // Dropping this owner's references does not mutate an escaped original.
  assert_eq(original.val, 17)
  retire_model_owned_array(values)
  assert_eq(values.capacity(), 0)
}
