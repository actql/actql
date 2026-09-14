///|
fn temporal_policy_top_k_claim(step : Int) -> @wire.ProgramProofClaim {
  let reference = "checked-step:" + step.to_string()
  let body = "{\"inputs\":[],\"law_id\":\"actql.bound.top-k\",\"semantic_ref\":\"" +
    reference +
    "\",\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-proof/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(body))
  let witness_body = "{\"dependencies\":[\"" +
    id +
    "\"],\"derivation\":{\"maximum\":1,\"op\":\"clamp\"},\"law_id\":\"actql.bound.top-k\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    id +
    "\",\"semantic_ref\":\"" +
    reference +
    "\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(witness_body))
  let limits : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(
      witness_body[0:witness_body.length() - 1].to_owned() +
      ",\"witness_cid\":\"" +
      cid +
      "\"}",
    ),
    cid,
    limits,
  ).unwrap()
  @wire.bind_program_proof(@utf8.encode(body), witness, limits).unwrap()
}

///|
test "SourceView temporal publication retains both contributors and search bounds" {
  for asof in [false, true] {
    for
      kind in (if asof {
        ["inner", "left"]
      } else {
        ["inner", "left", "semi", "anti"]
      }) {
      for
        direction in (if asof {
          ["backward", "forward", "nearest"]
        } else {
          [""]
        }) {
        let name = if asof { "asof_join" } else { "interval_join" }
        let options = if asof {
          ",\"by\":[],\"left_id\":\"id\",\"left_time\":\"id\",\"right_time\":\"id\",\"direction\":\"" +
          direction +
          "\",\"tolerance\":1"
        } else {
          ",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"id\"}"
        }
        let program = checked_direct_program_fixture(
          temporal_step="{\"from\":\"left_rows\",\"" +
            name +
            "\":{\"with\":\"right_rows\",\"kind\":\"" +
            kind +
            "\"" +
            options +
            ",\"select\":{\"id\":\"left.id\"}}}",
        )
        let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
        assert_eq(publication_policy_source_count(policy), 2)
        assert_eq(publication_policy_temporal_join_count(policy), 1)
        let retained = publication_policy_temporal_join_at(policy, 0).unwrap()
        assert_eq(retained.step, 4)
        assert_eq(retained.unknown_provenance, asof)
        let original = @pipeline.step_at(program.units[0].pipeline, 4).unwrap().operation
        match (original, retained.operation) {
          (IntervalJoin(checked=a, ..), IntervalJoin(checked=b, ..)) =>
            assert_true(physical_equal(a, b))
          (AsOfJoin(checked=a, ..), AsOfJoin(checked=b, ..)) =>
            assert_true(physical_equal(a, b))
          _ => fail("temporal operation changed")
        }
        assert_eq(
          unit_interval_search_limit_count(program, 0),
          Some(if asof { 0 } else { 1 }),
        )
        assert_eq(
          unit_asof_search_limit_count(program, 0),
          Some(if asof { 1 } else { 0 }),
        )
        assert_true(publication_policy_temporal_join_at(policy, -1) is None)
        assert_true(publication_policy_temporal_join_at(policy, 1) is None)
      }
    }
  }
}
