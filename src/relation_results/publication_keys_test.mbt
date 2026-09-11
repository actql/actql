///|
test "publication candidate key can precede projection and close authored ties" {
  let rows = @carrier.relation(
    @carrier.typed_rows(@schema.from_object(input()).unwrap()),
  )
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline.check_with_evidence(
    cursor("[]"),
    [("rows", @pipeline.KeyedInput(key))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  for
    (body, strategy) in [
      (
        "{\"out\":{\"from\":\"rows\",\"fields\":[\"data\"]}}",
        @relation_results.CandidateKey,
      ),
      (
        "{\"out\":{\"from\":\"rows\",\"fields\":[\"data\"],\"order_by\":[{\"id\":\"desc\"}]}}",
        @relation_results.Authored,
      ),
    ] {
    let results = @relation_results.check(p, cursor(body), limits()).unwrap()
    let order = resolve(results)
    assert_eq(@relation_results.publication_strategy(order), strategy)
    assert_eq(@relation_results.publication_term_count(order), 1)
    let term = @relation_results.publication_term_at(order, 0).unwrap()
    assert_eq(term.field, Unqualified("id"))
    assert_eq(term.authored, strategy == Authored)
    assert_eq(term.direction, if strategy == Authored { Desc } else { Asc })
    assert_eq(
      @evidence.key_pending(@relation_results.publication_key(order).unwrap()),
      @evidence.key_pending(key),
    )
    assert_true(@relation_results.publication_term_at(order, 1) is None)
    assert_eq(
      @relation_results.resolve_publication_order(
        results,
        0,
        max_work=-1,
        max_text_bytes=100,
      ).unwrap_err().kind,
      InvalidLimits,
    )
    assert_eq(
      @relation_results.resolve_publication_order(
        results,
        -1,
        max_work=100,
        max_text_bytes=100,
      ).unwrap_err().kind,
      InvalidBody,
    )
  }
}
