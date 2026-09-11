///|
fn node(n : Int64, derivation : Derivation) -> Node {
  { unit: Rows, claimed: n, derivation, }
}

///|
fn limits() -> Limits {
  { max_nodes: 20000, max_edges: 40000, }
}

///|
test "all derivations recompute forward references and repeated operands" {
  let nodes = [
    node(14L, Add(5, 5)),
    node(7L, Minimum([0, 5, 5])),
    node(21L, Multiply(1, 3L)),
    node(8L, Clamp(Some(2), 8L)),
    node(8L, Preserve(3)),
    node(7L, Leaf),
    node(0L, Clamp(None, 0L)),
  ]
  let checked = check(nodes, { max_nodes: 7, max_edges: 8, }).unwrap()
  assert_eq(count(checked), 7)
  assert_eq(edge_count(checked), 8)
  assert_eq(leaf_count(checked), 1)
  assert_eq(leaf_at(checked, 0), Some(5))
  assert_eq(leaf_at(checked, 1), None)
  for i = 0; i < nodes.length(); i = i + 1 {
    assert_eq(value_at(checked, i), Some(nodes[i].claimed))
    assert_eq(unit_at(checked, i), Some(Rows))
  }
  assert_true(
    check(nodes, { max_nodes: 6, max_edges: 8, }) is Err(BudgetExceeded),
  )
  assert_true(
    check(nodes, { max_nodes: 7, max_edges: 7, }) is Err(BudgetExceeded),
  )
  assert_eq(value_at(checked, -1), None)
  assert_eq(unit_at(checked, 7), None)
}

///|
test "arithmetic consistency never hides invalid or cyclic dependencies" {
  assert_true(
    check([node(1L, Preserve(1))], limits()) is Err(MissingDependency(0, 1)),
  )
  assert_true(
    check([node(1L, Preserve(-1))], limits()) is Err(MissingDependency(0, -1)),
  )
  assert_true(check([node(0L, Multiply(0, 0L))], limits()) is Err(Cycle))
  assert_true(check([node(0L, Clamp(Some(0), 0L))], limits()) is Err(Cycle))
  assert_true(
    check([node(1L, Preserve(1)), node(1L, Preserve(0))], limits())
    is Err(Cycle),
  )
  assert_true(
    check([node(1L, Leaf), node(1L, Preserve(1))], limits()) is Err(Cycle),
  )
  assert_true(
    check([node(1L, Leaf), node(0L, Multiply(2, 0L))], limits())
    is Err(MissingDependency(1, 2)),
  )
  assert_true(check([node(0L, Minimum([]))], limits()) is Err(EmptyMinimum(0)))
}

///|
test "claims factors and maxima are independently validated" {
  for invalid in [-1L, 9007199254740992L, 9223372036854775807L] {
    assert_true(check([node(invalid, Leaf)], limits()) is Err(InvalidValue(0)))
    assert_true(
      check([node(0L, Leaf), node(0L, Multiply(0, invalid))], limits())
      is Err(InvalidValue(1)),
    )
    assert_true(
      check([node(0L, Clamp(None, invalid))], limits()) is Err(InvalidValue(0)),
    )
  }
  assert_true(
    check([node(7L, Leaf), node(6L, Preserve(0))], limits())
    is Err(ValueMismatch(1)),
  )
  assert_true(
    check([node(7L, Leaf), node(13L, Add(0, 0))], limits())
    is Err(ValueMismatch(1)),
  )
  assert_true(
    check([node(7L, Leaf), node(6L, Minimum([0]))], limits())
    is Err(ValueMismatch(1)),
  )
  assert_true(
    check([node(7L, Leaf), node(15L, Multiply(0, 2L))], limits())
    is Err(ValueMismatch(1)),
  )
  assert_true(
    check([node(7L, Leaf), node(6L, Clamp(Some(0), 5L))], limits())
    is Err(ValueMismatch(1)),
  )
  assert_true(
    check([node(1L, Clamp(None, 2L))], limits()) is Err(ValueMismatch(0)),
  )
  assert_true(
    check([node(9007199254740991L, Leaf), node(0L, Add(0, 0))], limits())
    is Err(Overflow(1)),
  )
  assert_true(
    check([node(9007199254740991L, Leaf), node(0L, Multiply(0, 2L))], limits())
    is Err(Overflow(1)),
  )
}

///|
test "units agree except for a law-specific multiplication conversion" {
  let input : Node = { unit: Nodes, claimed: 2L, derivation: Leaf, }
  let derivations : Array[Derivation] = [
    Preserve(0),
    Minimum([0]),
    Add(0, 0),
    Clamp(Some(0), 2L),
  ]
  for derivation in derivations {
    assert_true(
      check([input, node(2L, derivation)], limits()) is Err(UnitMismatch(1, 0)),
    )
  }
  let checked = check([input, node(6L, Multiply(0, 3L))], limits()).unwrap()
  assert_eq(unit_at(checked, 0), Some(Nodes))
  assert_eq(unit_at(checked, 1), Some(Rows))
  assert_eq(value_at(checked, 1), Some(6L))
}

///|
test "deep derivations use bounded iterative traversal and detached results" {
  let nodes = [node(5L, Leaf)]
  for i = 1; i < 10000; i = i + 1 {
    nodes.push(node(5L, Preserve(i - 1)))
  }
  let checked = check(nodes, { max_nodes: 10000, max_edges: 9999, }).unwrap()
  nodes[0] = node(9L, Leaf)
  assert_eq(value_at(checked, 0), Some(5L))
  assert_eq(value_at(checked, 9999), Some(5L))
  assert_eq(edge_count(checked), 9999)
  assert_true(
    check(nodes, { max_nodes: 10000, max_edges: 9998, }) is Err(BudgetExceeded),
  )
  let inputs = [0, 0]
  let small = check([node(2L, Leaf), node(2L, Minimum(inputs))], limits()).unwrap()
  inputs[0] = 99
  assert_eq(value_at(small, 1), Some(2L))
}

///|
test "empty closure is not confused with a finite capacity candidate" {
  let checked = check([], { max_nodes: 0, max_edges: 0, }).unwrap()
  assert_eq(count(checked), 0)
  assert_eq(leaf_count(checked), 0)
  assert_eq(edge_count(checked), 0)
  assert_true(check([], { max_nodes: -1, max_edges: 0, }) is Err(InvalidLimits))
  assert_true(check([], { max_nodes: 0, max_edges: -1, }) is Err(InvalidLimits))
}

///|
test "permuted arithmetic graphs match independent integer expectations" {
  for seed = 0; seed < 300; seed = seed + 1 {
    let a = (seed * 17 % 997).to_int64()
    let b = (seed * 31 % 541).to_int64()
    let factor = (seed % 7).to_int64()
    let sum = a + b
    let product = sum * factor
    let cap = 200L
    let bounded = if product < cap { product } else { cap }
    let nodes = [
      node(bounded, Clamp(Some(4), cap)),
      node(b, Leaf),
      node(sum, Add(3, 1)),
      node(a, Leaf),
      node(product, Multiply(2, factor)),
      node(if a < b { a } else { b }, Minimum([1, 3])),
    ]
    let checked = check(nodes, limits()).unwrap()
    for i = 0; i < nodes.length(); i = i + 1 {
      assert_eq(value_at(checked, i), Some(nodes[i].claimed))
    }
    nodes[0] = node(bounded + 1L, Clamp(Some(4), cap))
    assert_true(check(nodes, limits()) is Err(ValueMismatch(0)))
  }
}
