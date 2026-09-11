///|
test "repeated fusion preserves positional key domains through every surviving alias" {
  for by in ["[]", "[\"query_id\",\"query_id\"]"] {
    let selected = if by == "[]" { "" } else { ",\"query_id\"" }
    let source = cursor(
      "[{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":10},\"as\":\"n\"}," +
      "{\"merge_rankings\":{\"with\":[\"n\",\"n\"],\"by\":" +
      by +
      ",\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":5,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,0,2],\"rank_window\":10}}}}," +
      "{\"select\":[{\"x\":\"candidate_id\"},{\"y\":\"candidate_id\"},\"rank\"" +
      selected +
      "]},{\"drop\":[\"x\"],\"as\":\"out\"}," +
      "{\"merge_rankings\":{\"with\":\"out\",\"by\":" +
      by +
      ",\"candidate\":\"y\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1],\"rank_window\":5}}}}]",
    )
    let vectors = key_vectors(true)
    let inputs = [("v", vectors)]
    let p = @pipeline_typing.check_carriers(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    for step in [1, 3, 4] {
      let keys = @pipeline_typing.candidate_keys(p, Step(step)).unwrap()
      let key = @evidence.key_witness_at(keys, 0).unwrap()
      assert_eq(@evidence.key_origin(key), RankingResult)
      assert_eq(@evidence.key_field_count(key), if by == "[]" { 1 } else { 2 })
      let producer = @evidence.key_ranking_producer(key).unwrap()
      assert_eq(
        @vector.merged_ranking_input_count(producer),
        if step == 4 {
          2
        } else {
          3
        },
      )
      assert_true(
        @vector.merged_ranking_pending(producer).contains(
          ValidateUniqueQueryCandidatePerInput,
        ),
      )
      for i in 0..<@evidence.key_field_count(key) {
        let domain = @evidence.key_field_at(key, i).unwrap().positional_identity.unwrap()
        assert_eq(
          @carrier.vector_identity_at(domain, 0).unwrap().name,
          Unqualified("b"),
        )
        assert_eq(
          @carrier.vector_identity_at(domain, 1).unwrap().name,
          Unqualified("a"),
        )
      }
      assert_true(
        @evidence.select_key(source, keys, CanonicalOrder, {
          max_work: 1000,
          max_name_bytes: 1000,
        }).unwrap().key
        is Some(_),
      )
      assert_true(
        @evidence.select_key(source, keys, ScalarIdentity, {
          max_work: 1000,
          max_name_bytes: 1000,
        }).unwrap().key
        is None,
      )
    }
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, {
        ..exact,
        max_work: u.work - 1,
      })
      is Err(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, {
        ..exact,
        max_text_bytes: u.text_bytes - 1,
      })
      is Err(_),
    )
  }
}
