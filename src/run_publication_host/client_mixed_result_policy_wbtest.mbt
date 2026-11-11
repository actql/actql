///|
// The original upstream Result is a subset. The later Model Result already
// owns the complete checked policy; no new union policy or authority is made.
test "mixed Result policies select the existing complete policy independent of root order" {
  for
    roots in [
      "{\"a_original\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}},\"z_reviewed\":{\"from\":{\"stage\":\"confirm\",\"result\":\"rows\"}}}",
      "{\"a_reviewed\":{\"from\":{\"stage\":\"confirm\",\"result\":\"rows\"}},\"z_original\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}",
    ] {
    let prepared = mixed_whole_infer_test_program(roots=Some(roots))
    let program = @strategy.graph_program(prepared.graph)
    let original = @checked.publication_source_policy(
      @checked.unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    let complete = @checked.publication_source_policy(
      @checked.unit_publication_at(program, 2, 0).unwrap(),
    ).unwrap()
    assert_false(
      client_publication_policy_covers_source_responses(program, original),
    )
    assert_true(
      client_publication_policy_covers_source_responses(program, complete),
    )
    assert_eq(
      prepared_client_publication_data_policy_cid(prepared),
      Some(complete.cid),
    )
    let bodies = prepared_client_publication_policy_bodies(
      prepared, 100000, 10000, 100,
    ).unwrap()
    assert_eq(bodies[0].1, complete.cid)
  }
}

///|
test "mixed Result policies without an existing complete representative stay refused" {
  let prepared = mixed_whole_infer_test_program(
    roots=Some(
      "{\"original\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}",
    ),
  )
  assert_eq(prepared_client_publication_data_policy_cid(prepared), None)
}

///|
test "mixed Result policies preserve unknown and reject equal CID foreign contributors" {
  let (original, limited) = publication_policy_join_pair(
    multi_source_prepared(publication_policy_join_program),
  )
  let (foreign_original, foreign_limited) = publication_policy_join_pair(
    multi_source_prepared(publication_policy_join_program),
  )
  assert_true(client_publication_policy_contains_result(limited, original))
  assert_false(client_publication_policy_contains_result(original, limited))
  assert_eq(original.cid, foreign_original.cid)
  assert_eq(limited.cid, foreign_limited.cid)
  assert_false(
    client_publication_policy_contains_result(limited, foreign_original),
  )
  assert_false(
    client_publication_policy_contains_result(limited, foreign_limited),
  )
  let prepared = multi_source_prepared(publication_policy_join_program)
  let program = @strategy.graph_program(prepared.graph)
  let partial = @checked.publication_source_policy(
    @checked.unit_publication_at(program, 0, 0).unwrap(),
  ).unwrap()
  let (complete, conservative) = publication_policy_join_pair(prepared)
  assert_true(client_publication_policy_contains_result(conservative, partial))
  assert_true(client_publication_policy_contains_result(complete, partial))
  assert_false(client_publication_policy_contains_result(partial, conservative))
}
