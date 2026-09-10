///|
fn nearest_rows(dimensions : Double) -> @carrier.Knowledge {
  @carrier.rows(
    [
      (Unqualified("id"), Some(@contract.primitive(NumberType, nullable=false))),
      (
        Unqualified("v"),
        Some(@contract.vector_contract(dimensions, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
}

///|
test "nearest admits both mixed Carrier directions with one shared budget" {
  let rows = nearest_rows(3.0)
  let relation = @carrier.relation(rows)
  let vectors = @carrier.vectors(
    rows,
    ids=[Unqualified("id")],
    components=Unqualified("v"),
    max_identity_fields=1,
  ).unwrap()
  let source = cursor(
    "{\"queries\":\"q\",\"k\":2,\"metric\":\"cosine\",\"candidate_id\":\"id\",\"query_id\":\"id\"}",
  )
  for
    (a, z) in [
      (relation, relation),
      (relation, vectors),
      (vectors, relation),
      (vectors, vectors),
    ] {
    let c = @vector_typing.check_nearest_pair(source, a, z, limits()).unwrap()
    let u = @vector_typing.nearest_pair_usage(c)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(@vector_typing.check_nearest_pair(source, a, z, exact) is Ok(_))
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @vector_typing.check_nearest_pair(source, a, z, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
    let pending = @vector_typing.nearest_pair_pending(c)
    assert_true(pending.contains(ValidateBothUniqueIdentities))
    assert_true(pending.contains(AssignContiguousOneBasedRanks))
    assert_eq(
      pending.contains(
        JournalVectorFieldCompletion(Candidates, Unqualified("v")),
      ),
      a is @carrier.Relation(_),
    )
    assert_eq(
      pending.contains(JournalVectorFieldCompletion(Queries, Unqualified("v"))),
      z is @carrier.Relation(_),
    )
  }
}

///|
test "nearest rejects known dimensions at query source without reading runtime values" {
  let source = cursor(
    "{\"queries\":\"q\",\"k\":1,\"metric\":\"l2\",\"candidate_id\":\"id\",\"candidate_vector\":\"v\",\"query_id\":\"id\",\"query_vector\":\"v\"}",
  )
  let c = @vector_typing.check_nearest_pair(
    source,
    @carrier.relation(nearest_rows(2)),
    @carrier.relation(nearest_rows(3)),
    limits(),
  ).unwrap_err()
  assert_eq(c.kind, DimensionMismatch(2, 3))
  assert_eq(c.path, [@source.Key("query_vector")])
  for metric in ["cosine", "dot", "l2"] {
    let c = @vector_typing.check_nearest_pair(
      cursor(
        "{\"queries\":\"q\",\"k\":1,\"metric\":\"" +
        metric +
        "\",\"candidate_id\":\"id\",\"query_id\":\"id\"}",
      ),
      @carrier.relation(nearest_rows(2)),
      @carrier.relation(nearest_rows(2)),
      limits(),
    ).unwrap()
    assert_true(
      @vector_typing.nearest_pair_pending(c).contains(
        EvaluateExactNearestScores,
      ),
    )
  }
}
