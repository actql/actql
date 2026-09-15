///|
test "temporal searches demand both operands without a published join output" {
  let (text, _, environment, evidence, limits) = public_input_fixture(
    temporal_join_step=Some(2),
  )
  for kind in ["asof_join", "interval_join"] {
    let body = if kind == "asof_join" {
      "\"by\":[],\"left_id\":\"id\",\"left_time\":\"id\",\"right_time\":\"id\",\"direction\":\"nearest\",\"tolerance\":1"
    } else {
      "\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"value\"}"
    }
    let source = text
      .replace(
        old="{\"take\":1,\"as\":\"selected\"}",
        new="{\"take\":3,\"as\":\"right_rows\"},{\"from\":\"rows\",\"take\":2},{\"" +
          kind +
          "\":{\"with\":\"right_rows\",\"kind\":\"inner\"," +
          body +
          ",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}},\"as\":\"joined\"}",
      )
      .replace(old="\"from\":\"selected\"", new="\"from\":\"rows\"")
    let program = public_checked(
      @program_check.check_document_with_evidence(
        source,
        environment,
        None,
        evidence,
        limits,
        format=Json,
      ),
    )
    let out = @encode.writer(100000, 10000, 100)
    if kind == "asof_join" {
      let retained = @program_check.unit_asof_search_limit_at(program, 1, 0).unwrap()
      assert_true(@program_check.asof_search_limit_proof_count(retained, 0) > 0)
      assert_true(@program_check.asof_search_limit_proof_count(retained, 1) > 0)
      @program_check.emit_asof_search_limit(retained, out)
    } else {
      let retained = @program_check.unit_interval_search_limit_at(program, 1, 0).unwrap()
      assert_true(
        @program_check.interval_search_limit_proof_count(retained, 0) > 0,
      )
      assert_true(
        @program_check.interval_search_limit_proof_count(retained, 1) > 0,
      )
      @program_check.emit_interval_search_limit(retained, out)
    }
    assert_true(@encode.finish(out).contains("\"maximum\":6"))
  }
}
