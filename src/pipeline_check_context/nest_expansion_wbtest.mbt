///|
test "nest expansion minimum is exact without an overflowing intermediate product" {
  for cap in 0L..<25L {
    for parents in 0L..<25L {
      for per_parent in 0L..<25L {
        assert_eq(
          nest_min_product(cap, parents, per_parent),
          Int64::min(cap, parents * per_parent),
        )
      }
    }
  }
  let maximum = 9007199254740991L
  for
    (cap, parents, per_parent, expected) in [
      (maximum, maximum, maximum, maximum),
      (maximum / 2L, maximum / 2L, maximum, maximum / 2L),
      (maximum, 0L, maximum, 0L),
      (maximum, maximum, 0L, 0L),
      (maximum, 1L, maximum, maximum),
      (maximum, 2L, maximum / 2L, maximum - 1L),
    ] {
    assert_eq(nest_min_product(cap, parents, per_parent), expected)
  }
}
