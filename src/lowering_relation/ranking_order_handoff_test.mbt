///|
// The independent installed fixture has two scored Relation inputs and no
// grouping key. ORDER consumes the ranking output, not either input score.
test "ranking ORDER handoff preserves the declared two-input score contract" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let carrier = @carrier.relation(@carrier.rows(
    [(@schema.Unqualified("id"), Some(number)),
     (@schema.Unqualified("s"), Some(number))],
    field_set=@carrier.Closed, max_fields=2, max_name_bytes=3,
  ).unwrap())
  let score = "{\"domain\":\"Relevance\",\"normalization\":\"Identity\",\"range\":[0,1]}"
  let ranking = @vector.declare_ranking_score(
    cursor(score), carrier, @schema.Unqualified("s"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for policy in ["\"max\"", "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"] {
    let text = "[{\"merge_rankings\":{\"with\":\"right\",\"by\":[],\"candidate\":\"id\",\"score\":\"s\",\"k\":3,\"score_policy\":" + policy + ",\"score_contract\":" + score + "},\"as\":\"fused\"},{\"from\":\"fused\",\"sort\":[{\"field\":\"rank\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"score\",\"rank\"]}]"
    let checked = @pipeline.check_with_evidence(
      cursor(text), [("left", @pipeline.RankingInput(ranking)), ("right", @pipeline.RankingInput(ranking))],
      None, Some(cursor("\"left\"")),
      { max_steps: 10, max_work: 10000, max_text_bytes: 10000, max_nodes: 1000, max_tokens: 1000, max_depth: 100, },
    ).unwrap()
    let owner = @lowering_relation.bind_parameters(
      @lowering_relation.prepare(checked, limits()).unwrap(), None,
      max_parameters=0, max_name_bytes=100,
    ).unwrap()
    let prepared = @lowering_relation.bound_preparation(owner)
    let merge = @lowering_relation.node_at(prepared, 0).unwrap()
    let ordered = @lowering_relation.node_at(prepared, 1).unwrap()
    let selected = @lowering_relation.node_at(prepared, 2).unwrap()
    assert_eq(@lowering_relation.operation(merge), "VEC.merge_rankings")
    assert_eq(@lowering_relation.node_input_count(merge), 2)
    assert_eq(@lowering_relation.node_input_target(merge, 0), Some(@pipeline.Input(0)))
    assert_eq(@lowering_relation.node_input_target(merge, 1), Some(@pipeline.Input(1)))
    assert_eq(@lowering_relation.operation(ordered), "REL.orderByStable")
    assert_eq(@lowering_relation.node_input_target(ordered, 0), Some(@pipeline.Step(0)))
    assert_eq(@lowering_relation.node_input_target(selected, 0), Some(@pipeline.Step(1)))
    assert_true(@lowering_relation.node_supports_selected_managed_execution(merge))
    assert_true(@lowering_relation.node_accepts_managed_relation_view(ordered, 0))
    // Both existing Owners accept this exact checked port. No fabricated
    // ordering, alternative evaluator, or enlarged execution limit is needed.
    assert_true(@lowering_relation.node_supports_bounded_managed_prefix(merge, ordered))
  }
}
