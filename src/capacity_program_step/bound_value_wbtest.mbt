///|
fn bound_calculation(
  rule : Rule,
  inputs : Array[Int64],
) -> Result[Int64, Issue] {
  let admitted = inputs.map(n => @numeric.read(n).unwrap())
  calculate_bound_value(rule, inputs.length(), i => admitted[i], None)
}

///|
test "bound calculation preserves arithmetic limits and operation-specific empty cases" {
  let maximum = 9007199254740991L
  assert_eq(bound_calculation(One, []), Ok(1L))
  assert_eq(bound_calculation(Constant(0L), []), Ok(0L))
  assert_eq(bound_calculation(Preserve, [maximum]), Ok(maximum))
  assert_eq(bound_calculation(Sum, [maximum, 0L]), Ok(maximum))
  assert_eq(bound_calculation(Sum, [maximum, 1L]), Err(BoundOverflow))
  assert_eq(bound_calculation(Multiply(0L), [maximum]), Ok(0L))
  assert_eq(bound_calculation(Multiply(2L), [maximum]), Err(BoundOverflow))
  assert_eq(bound_calculation(Clamp(3L), []), Ok(3L))
  assert_eq(bound_calculation(Clamp(3L), [0L]), Ok(0L))
  assert_eq(bound_calculation(Clamp(3L), [5L]), Ok(3L))
  assert_eq(
    bound_calculation(PropertyGraphMeasure(@arithmetic.Nodes, 0, 0), []),
    Ok(0L),
  )
  assert_eq(
    bound_calculation(PropertyGraphMeasure(@arithmetic.Edges, 2, 0), []),
    Ok(0L),
  )
  assert_eq(
    bound_calculation(PropertyGraphMeasure(@arithmetic.Nodes, 0, 2), [
      maximum, 1L,
    ]),
    Err(BoundOverflow),
  )
  assert_eq(
    bound_calculation(PropertyGraphMeasure(@arithmetic.Edges, 2, 2), [2L, 2L]),
    Ok(4L),
  )
  assert_eq(
    bound_calculation(PropertyGraphMeasure(@arithmetic.Edges, 2, 3), [
      1L, 1L, 2L,
    ]),
    Ok(4L),
  )
  assert_eq(
    bound_calculation(
      GraphMeasure(@arithmetic.Rows, @arithmetic.Nodes, 0, 2L),
      [3L],
    ),
    Ok(6L),
  )
  assert_eq(bound_calculation(Ranking(2, Some(3L)), [maximum, maximum]), Ok(3L))
  assert_eq(
    bound_calculation(Ranking(2, None), [maximum, maximum]),
    Err(BoundOverflow),
  )
  assert_eq(bound_calculation(QueryTopK(3L), [2L]), Ok(6L))
  assert_eq(bound_calculation(QueryTopK(3L), [1L, 2L]), Ok(2L))
}

///|
test "join count calculation distinguishes matched pairs from preserved occurrences" {
  for left in 0..<5 {
    for right in 0..<5 {
      let l = left.to_int64()
      let r = right.to_int64()
      let product = l * r
      let full = if product > l + r { product } else { l + r }
      assert_eq(bound_calculation(Join(@join.Inner), [l, r]), Ok(product))
      assert_eq(
        bound_calculation(Join(@join.Left), [l, r]),
        Ok(if r == 0L { l } else { product }),
      )
      assert_eq(bound_calculation(Join(@join.Full), [l, r]), Ok(full))
      assert_eq(
        bound_calculation(Join(@join.Semi), [l, r]),
        Ok(if r == 0L { 0L } else { l }),
      )
      assert_eq(bound_calculation(Join(@join.Anti), [l, r]), Ok(l))
    }
  }
}
