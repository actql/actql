///|
test "one original Array push quotes only additional backing and keeps existing capacity separate" {
  let values : Array[Int] = []
  for i in 0..<33 {
    let length = values.length()
    let capacity = values.capacity()
    let q = reference_array_push_construction_extent(length, capacity).unwrap()
    if length < capacity {
      assert_eq(q.record_headers, 0L)
      assert_eq(q.reference_slots, 0L)
    } else {
      assert_eq(q.record_headers, 1L)
      assert_true(q.reference_slots >= (length + 1).to_int64())
    }
    values.push(i)
    assert_true(
      values.capacity().to_int64() <= capacity.to_int64() + q.reference_slots,
    )
  }
  assert_eq(
    reference_array_push_construction_extent(0, 1024).unwrap().reference_slots,
    0L,
  )
  assert_true(reference_array_push_construction_extent(2, 1) is None)
  assert_true(reference_array_push_construction_extent(-1, 0) is None)
}
