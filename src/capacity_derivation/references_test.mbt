///|
fn identity(n : Int) -> String {
  let digits = n.to_string()
  "sha256:" + "0".repeat(64 - digits.length()) + digits
}

///|
fn reference_node(
  n : Int,
  value : Int64,
  d : ReferencedDerivation,
) -> ReferencedNode {
  { cid: identity(n), unit: Rows, claimed: value, derivation: d, }
}

///|
test "CID references close forward shared repeated and detached arithmetic" {
  let refs = [identity(2), identity(3)]
  let nodes = [
    reference_node(0, 6L, AddReferences(identity(1), identity(1))),
    reference_node(1, 3L, MinimumReferences(refs)),
    reference_node(2, 3L, PreserveReference(identity(4))),
    reference_node(3, 9L, MultiplyReference(identity(4), 3L)),
    reference_node(4, 3L, Source),
    reference_node(5, 2L, ClampReference(Some(identity(0)), 2L)),
    reference_node(6, 7L, ClampReference(None, 7L)),
  ]
  let graph = link_references(nodes, { max_nodes: 7, max_edges: 7, }).unwrap()
  let arithmetic = linked_arithmetic(graph)
  assert_eq(edge_count(arithmetic), 7)
  for i, value in [6L, 3L, 3L, 9L, 3L, 2L, 7L] {
    assert_eq(linked_index(graph, identity(i)), Some(i))
    assert_eq(linked_identity_at(graph, i), Some(identity(i)))
    assert_eq(value_at(arithmetic, i), Some(value))
  }
  assert_eq(linked_identity_at(graph, -1), None)
  assert_eq(linked_identity_at(graph, 7), None)
  assert_eq(linked_index(graph, identity(99)), None)
  assert_true(
    link_references(nodes, { max_nodes: 6, max_edges: 7, })
    is Err(ReferenceBudgetExceeded),
  )
  assert_true(
    link_references(nodes, { max_nodes: 7, max_edges: 6, })
    is Err(ReferenceBudgetExceeded),
  )
  refs.clear()
  nodes.clear()
  assert_eq(value_at(arithmetic, 0), Some(6L))
  assert_eq(linked_index(graph, identity(4)), Some(4))
}

///|
test "reference closure refuses invalid identities missing inputs and unused cycles" {
  let limits : Limits = { max_nodes: 10, max_edges: 10, }
  for
    id in [
      "",
      "sha256:" + "A".repeat(64),
      "sha256:" + "a".repeat(65),
      "bad:" + "a".repeat(67),
    ] {
    assert_true(
      link_references(
        [{ cid: id, unit: Rows, claimed: 1L, derivation: Source, }],
        limits,
      )
      is Err(InvalidIdentity(0)),
    )
    assert_true(
      link_references([reference_node(0, 1L, PreserveReference(id))], limits)
      is Err(InvalidReference(0)),
    )
  }
  let leaf = reference_node(0, 1L, Source)
  assert_true(
    link_references([leaf, leaf], limits) is Err(DuplicateIdentity(1)),
  )
  assert_true(
    link_references(
      [leaf, reference_node(1, 1L, PreserveReference(identity(2)))],
      limits,
    )
    is Err(MissingReference(1, _)),
  )
  assert_true(
    link_references(
      [leaf, reference_node(1, 1L, PreserveReference(identity(1)))],
      limits,
    )
    is Err(ArithmeticFailure(Cycle)),
  )
  assert_true(
    link_references(
      [
        reference_node(0, 1L, PreserveReference(identity(1))),
        reference_node(1, 1L, PreserveReference(identity(0))),
      ],
      limits,
    )
    is Err(ArithmeticFailure(Cycle)),
  )
  assert_true(
    link_references(
      [leaf, reference_node(1, 2L, PreserveReference(identity(0)))],
      limits,
    )
    is Err(ArithmeticFailure(ValueMismatch(1))),
  )
  assert_true(
    link_references([reference_node(0, 1L, MinimumReferences([]))], limits)
    is Err(ArithmeticFailure(EmptyMinimum(0))),
  )
  assert_true(
    link_references([], { max_nodes: -1, max_edges: 0, })
    is Err(InvalidReferenceLimits),
  )
  assert_eq(
    count(
      linked_arithmetic(
        link_references([], { max_nodes: 0, max_edges: 0, }).unwrap(),
      ),
    ),
    0,
  )
}

///|
test "reference closure handles a reversed ten thousand node chain iteratively" {
  let nodes : Array[ReferencedNode] = []
  for i = 9999; i >= 0; i = i - 1 {
    nodes.push(
      reference_node(
        i,
        1L,
        if i == 0 {
          Source
        } else {
          PreserveReference(identity(i - 1))
        },
      ),
    )
  }
  let graph = link_references(nodes, { max_nodes: 10000, max_edges: 9999, }).unwrap()
  assert_eq(linked_index(graph, identity(0)), Some(9999))
  assert_eq(value_at(linked_arithmetic(graph), 0), Some(1L))
}
