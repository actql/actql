///|
fn number(
  value : Result[@execution_relation.Value, @execution_relation.ScalarIssue],
) -> Double {
  match value.unwrap() {
    Number(n) => n
    _ => abort("expected numeric test result")
  }
}

///|
test "finite binary64 arithmetic and exact comparisons" {
  assert_eq(
    number(@execution_relation.binary(@lower.Add, Number(2), Number(3))),
    5.0,
  )
  assert_eq(
    number(@execution_relation.binary(@lower.Subtract, Number(2), Number(3))),
    -1.0,
  )
  assert_eq(
    number(@execution_relation.binary(@lower.Multiply, Number(2), Number(3))),
    6.0,
  )
  assert_eq(
    number(@execution_relation.binary(@lower.Divide, Number(3), Number(2))),
    1.5,
  )
  assert_eq(
    number(@execution_relation.binary(@lower.Modulo, Number(-7), Number(3))),
    -1.0,
  )
  assert_true(
    @execution_relation.binary(@lower.Equal, Number(1.0), Number(1.00000000001)).unwrap()
    is Boolean(false),
  )
  assert_true(
    @execution_relation.binary(@lower.Less, Number(1.0), Number(1.00000000001)).unwrap()
    is Boolean(true),
  )
  assert_true(
    @execution_relation.binary(@lower.Equal, Number(-0.0), Number(0.0)).unwrap()
    is Boolean(true),
  )
  assert_true(
    @execution_relation.binary(@lower.Divide, Number(1), Number(0))
    is Err(@execution_relation.ArithmeticFailure),
  )
  assert_true(
    @execution_relation.binary(
      @lower.Multiply,
      Number(1.0e308),
      Number(1.0e308),
    )
    is Err(@execution_relation.ArithmeticFailure),
  )
}

///|
test "three-valued eager boolean combination uses the complete truth table" {
  let operands : Array[@execution_relation.Value] = [
    Boolean(false),
    Boolean(true),
    Null,
  ]
  let ands : Array[@execution_relation.Value] = [
    Boolean(false),
    Boolean(false),
    Boolean(false),
    Boolean(false),
    Boolean(true),
    Null,
    Boolean(false),
    Null,
    Null,
  ]
  let ors : Array[@execution_relation.Value] = [
    Boolean(false),
    Boolean(true),
    Null,
    Boolean(true),
    Boolean(true),
    Boolean(true),
    Null,
    Boolean(true),
    Null,
  ]
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      let a = @execution_relation.boolean_pair(
        @lower.And,
        operands[i],
        operands[j],
      ).unwrap()
      let o = @execution_relation.boolean_pair(
        @lower.Or,
        operands[i],
        operands[j],
      ).unwrap()
      assert_true(same(a, ands[i * 3 + j]))
      assert_true(same(o, ors[i * 3 + j]))
    }
  }
}

///|
fn same(a : @execution_relation.Value, b : @execution_relation.Value) -> Bool {
  match (a, b) {
    (Null, Null) => true
    (Boolean(a), Boolean(b)) => a == b
    _ => false
  }
}

///|
test "null comparison and nullif preserve the normative distinction" {
  assert_true(
    @execution_relation.binary(@lower.Equal, Null, Null).unwrap() is Null,
  )
  assert_true(
    @execution_relation.binary(@lower.IsDistinctFrom, Null, Null).unwrap()
    is Boolean(false),
  )
  assert_true(
    @execution_relation.binary(@lower.IsDistinctFrom, Null, Number(7)).unwrap()
    is Boolean(true),
  )
  assert_true(
    @execution_relation.binary(@lower.IsDistinctFrom, Number(7), Null).unwrap()
    is Boolean(true),
  )
  assert_true(
    @execution_relation.binary(@lower.IsDistinctFrom, Number(7), Number(7)).unwrap()
    is Boolean(false),
  )
  assert_true(
    @execution_relation.binary(@lower.NullIf, Number(7), Null).unwrap()
    is Number(7.0),
  )
  assert_true(
    @execution_relation.binary(@lower.NullIf, Number(7), Number(7)).unwrap()
    is Null,
  )
  assert_true(
    @execution_relation.unary(@lower.IsUnknown, Null).unwrap() is Boolean(true),
  )
  assert_true(
    @execution_relation.unary(@lower.IsTrue, Null).unwrap() is Boolean(false),
  )
  assert_true(@execution_relation.unary(@lower.Not, Null).unwrap() is Null)
}
