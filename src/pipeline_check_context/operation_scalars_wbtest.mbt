///|
test "numeric operation domains reject rounding negative zero and nonfinite numbers" {
  for n in [0.0, 1.0, 9007199254740991.0] {
    assert_true(
      operation_scalar_number(n, @pipeline.SafeInteger("n", minimum=0L))
      is Some(_),
    )
  }
  for n in [-1.0, 0.5, 9007199254740992.0, -0.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(
      operation_scalar_number(n, @pipeline.SafeInteger("n", minimum=0L)) is None,
    )
  }
  assert_true(
    operation_scalar_number(0.0, @pipeline.SafeInteger("n", minimum=1L)) is None,
  )
  for n in [0.0, 0.5, 1.0] {
    assert_eq(
      operation_scalar_number(n, @pipeline.Fraction("n")),
      Some(Fraction(n)),
    )
  }
  for n in [-0.001, 1.001, -0.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(operation_scalar_number(n, @pipeline.Fraction("n")) is None)
  }
  assert_eq(
    operation_scalar_number(-0.25, @pipeline.Finite("n")),
    Some(Finite(-0.25)),
  )
  for n in [-0.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(operation_scalar_number(n, @pipeline.Finite("n")) is None)
  }
  assert_true(operation_scalar_number(1000.0, @pipeline.Duration("n")) is None)
}
