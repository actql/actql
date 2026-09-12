///|
fn[T] indexed_obligation_copy(
  values : Array[T],
  count : Int,
  at : (Int) -> T?,
  same : (T, T) -> Bool,
) -> Array[T] raise {
  assert_eq(count, values.length())
  for i in 0..<count {
    assert_true(same(values[i], at(i).unwrap()))
  }
  for i in [-1, count, 2147483647] {
    assert_true(at(i) is None)
  }
  let first = values.get(0)
  let detached = values.copy()
  values.clear()
  match (first, at(0)) {
    (Some(a), Some(b)) => assert_true(same(a, b))
    (None, None) => ()
    _ => fail("obligation source changed through copied array")
  }
  detached
}
