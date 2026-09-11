///|
test "capacity values admit only nonnegative safe integers" {
  for
    n in [
      -9223372036854775807L - 1L,
      -1L,
      9007199254740992L,
      9223372036854775807L,
    ] {
    assert_eq(read(n), Err(InvalidValue))
  }
  for n in [0L, 1L, 9007199254740990L, 9007199254740991L] {
    assert_eq(value(read(n).unwrap()), n)
  }
}

///|
test "small capacity arithmetic matches exact integer arithmetic" {
  for a = 0; a <= 64; a = a + 1 {
    for b = 0; b <= 64; b = b + 1 {
      let x = read(a.to_int64()).unwrap()
      let y = read(b.to_int64()).unwrap()
      assert_eq(value(add(x, y).unwrap()), (a + b).to_int64())
      assert_eq(value(multiply(x, y).unwrap()), (a * b).to_int64())
      assert_eq(value(minimum(x, y)), (if a < b { a } else { b }).to_int64())
      assert_eq(clamp(Some(x), y), minimum(x, y))
      assert_eq(clamp(None, y), y)
    }
  }
}

///|
test "capacity addition rejects the first unsafe integer in either order" {
  let max = 9007199254740991L
  for n = 0; n <= 4096; n = n + 1 {
    let left = read(max - n.to_int64()).unwrap()
    let right = read(n.to_int64()).unwrap()
    assert_eq(value(add(left, right).unwrap()), max)
    assert_eq(add(left, right), add(right, left))
    let excess = read(n.to_int64() + 1L).unwrap()
    assert_eq(add(left, excess), Err(Overflow))
    assert_eq(add(excess, left), Err(Overflow))
  }
}

///|
test "capacity multiplication uses exact quotient boundaries" {
  let max = 9007199254740991L
  for n = 2; n <= 4096; n = n + 1 {
    let factor = n.to_int64()
    let quotient = max / factor
    let x = read(quotient).unwrap()
    let y = read(factor).unwrap()
    assert_eq(value(multiply(x, y).unwrap()), quotient * factor)
    assert_eq(multiply(x, y), multiply(y, x))
    let excess = read(quotient + 1L).unwrap()
    assert_eq(multiply(excess, y), Err(Overflow))
    assert_eq(multiply(y, excess), Err(Overflow))
  }
  let largest = read(max).unwrap()
  let zero = read(0L).unwrap()
  let one = read(1L).unwrap()
  assert_eq(multiply(largest, zero), Ok(zero))
  assert_eq(multiply(zero, largest), Ok(zero))
  assert_eq(multiply(largest, one), Ok(largest))
  assert_eq(multiply(largest, largest), Err(Overflow))
}
