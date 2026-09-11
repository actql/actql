///|
test "candidate minima preserve role distinctions and strict author binding" {
  for a in 1..<25 {
    for b in 0..<25 {
      let graph = check(
        [
          { unit: Rows, claimed: a.to_int64(), derivation: Leaf, },
          { unit: Rows, claimed: b.to_int64(), derivation: Leaf, },
        ],
        { max_nodes: 2, max_edges: 0, },
      ).unwrap()
      let roles : Array[CandidateRole] = [
        ProvenUpperBound,
        ContractCeiling,
        LanguageCeiling,
        HostCeiling,
      ]
      for role in roles {
        for reversed in [false, true] {
          let candidates : Array[Candidate] = if reversed {
            [{ node: 1, role, }, { node: 0, role: AuthorGuard, }]
          } else {
            [{ node: 0, role: AuthorGuard, }, { node: 1, role, }]
          }
          let result = select_candidate_minimum(
            graph,
            candidates,
            Rows,
            max_candidates=2,
          ).unwrap()
          assert_eq(
            minimum_value(result),
            (if a < b { a } else { b }).to_int64(),
          )
          assert_eq(
            minimum_guard_binding(result),
            if a < b {
              Binding
            } else {
              CurrentlyNonBinding
            },
          )
          assert_eq(minimum_unit(result), Rows)
          assert_eq(minimum_candidate_count(result), 2)
          assert_eq(
            minimum_candidate_at(result, 0).unwrap().role,
            candidates[0].role,
          )
          candidates.clear()
          assert_eq(minimum_candidate_count(result), 2)
          assert_eq(count(minimum_graph(result)), 2)
        }
      }
    }
  }
}

///|
test "all candidates remain inspected even after a zero minimum" {
  let graph = check(
    [
      { unit: Rows, claimed: 0L, derivation: Leaf, },
      { unit: Rows, claimed: 9007199254740991L, derivation: Leaf, },
      { unit: Bytes, claimed: 1L, derivation: Leaf, },
    ],
    { max_nodes: 3, max_edges: 0, },
  ).unwrap()
  let zero : Candidate = { node: 0, role: ProvenUpperBound, }
  assert_eq(
    select_candidate_minimum(
      graph,
      [zero, { node: 8, role: HostCeiling, }],
      Rows,
      max_candidates=2,
    ).unwrap_err(),
    MissingNode(1),
  )
  assert_eq(
    select_candidate_minimum(
      graph,
      [zero, { node: -1, role: HostCeiling, }],
      Rows,
      max_candidates=2,
    ).unwrap_err(),
    MissingNode(1),
  )
  assert_eq(
    select_candidate_minimum(
      graph,
      [zero, { node: 2, role: HostCeiling, }],
      Rows,
      max_candidates=2,
    ).unwrap_err(),
    WrongUnit(1),
  )
  assert_eq(
    select_candidate_minimum(
      graph,
      [zero, { node: 0, role: AuthorGuard, }],
      Rows,
      max_candidates=2,
    ).unwrap_err(),
    NonpositiveGuard(1),
  )
  assert_eq(
    select_candidate_minimum(graph, [], Rows, max_candidates=0).unwrap_err(),
    EmptyCandidates,
  )
  assert_eq(
    select_candidate_minimum(graph, [], Rows, max_candidates=-1).unwrap_err(),
    InvalidLimit,
  )
  assert_eq(
    select_candidate_minimum(graph, [zero], Rows, max_candidates=0).unwrap_err(),
    BudgetExceeded,
  )
  let plain = select_candidate_minimum(graph, [zero], Rows, max_candidates=1).unwrap()
  assert_eq(minimum_guard_binding(plain), Absent)
  let guards = select_candidate_minimum(
    graph,
    [{ node: 1, role: AuthorGuard, }, { node: 1, role: AuthorGuard, }],
    Rows,
    max_candidates=2,
  ).unwrap()
  assert_eq(minimum_value(guards), 9007199254740991L)
  assert_eq(minimum_guard_binding(guards), Binding)
  assert_eq(minimum_candidate_count(guards), 2)
  assert_true(minimum_candidate_at(guards, -1) is None)
  assert_true(minimum_candidate_at(guards, 2) is None)
}

///|
test "derived candidates and multiple author guards use the complete minimum" {
  let graph = check(
    [
      { unit: Rows, claimed: 10L, derivation: Leaf, },
      { unit: Rows, claimed: 20L, derivation: Add(0, 0), },
      { unit: Rows, claimed: 15L, derivation: Clamp(Some(1), 15L), },
      { unit: Rows, claimed: 12L, derivation: Leaf, },
    ],
    { max_nodes: 4, max_edges: 3, },
  ).unwrap()
  let result = select_candidate_minimum(
    graph,
    [
      { node: 1, role: ProvenUpperBound, },
      { node: 2, role: AuthorGuard, },
      { node: 3, role: AuthorGuard, },
    ],
    Rows,
    max_candidates=3,
  ).unwrap()
  assert_eq(minimum_value(result), 12L)
  assert_eq(minimum_guard_binding(result), Binding)
  // An additional non-author bound changes binding, not retention of the guards.
  let restricted = select_candidate_minimum(
    graph,
    [
      { node: 1, role: ProvenUpperBound, },
      { node: 2, role: AuthorGuard, },
      { node: 3, role: AuthorGuard, },
      { node: 0, role: HostCeiling, },
    ],
    Rows,
    max_candidates=4,
  ).unwrap()
  assert_eq(minimum_value(restricted), 10L)
  assert_eq(minimum_guard_binding(restricted), CurrentlyNonBinding)
  assert_eq(minimum_candidate_count(restricted), 4)
}
