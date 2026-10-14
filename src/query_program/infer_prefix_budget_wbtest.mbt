///|
test "INFER prefix accounting charges exact UTF-8 bytes without renewing work" {
  let document = @origin.document("a😀", 5).unwrap()
  let origin = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let exact : InferPrefixBudget = { remaining_work: 5, }
  exact.spend_text("a😀", origin)
  assert_eq(exact.remaining_work, 0)
  let exhausted = try {
    exact.spend(1, origin)
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(exhausted)
  assert_eq(exact.remaining_work, 0)
  let short : InferPrefixBudget = { remaining_work: 4, }
  let rejected = try {
    short.spend_text("a😀", origin)
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(rejected)
  // The ASCII byte stays charged; the refused scalar neither partly spends
  // its four-byte unit nor restores work already consumed by earlier units.
  assert_eq(short.remaining_work, 3)
  let invalid = try {
    short.spend(-1, origin)
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(invalid)
  assert_eq(short.remaining_work, 3)
}

///|
test "original prefix checks share one exact and one-short cumulative allowance" {
  let query = @query.parse_query("SELECT 1 AS id", mapping_syntax_limits()).unwrap()
  let document = @query.query_document(query)
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let construction : Construction = {
    builder,
    generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
    model_tasks: None,
    parameter_names: None,
    infer_labels: false,
    infer_budget: { remaining_work: 10000, },
  }
  let input = property_input(
    "rows",
    ["id"],
    (
      #|{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"rows"}
    ),
  )
  let at = match input.source {
    GeneratedValues(at) => at
    _ => abort("the fixed prefix has a generated Values input")
  }
  let nodes = [import_query_cursor(construction, at)]
  let check = fn(budget : InferPrefixBudget) -> Unit raise Abort {
    let pipeline = checked_query_prefix_pipeline(
      construction,
      query,
      mapping_context(),
      [],
      [],
      nodes,
      mapping_limits(),
      budget,
    )
    if @pipeline.step_count(pipeline) != 1 ||
      @pipeline.lookup(pipeline, "rows") != Some(@pipeline.Step(0)) {
      raise Abort(InvalidContext)
    }
  }
  // Measure the existing owners' successful usage, then use that complete
  // aggregate twice. This tests conservation, not an independent runtime
  // capacity estimate or physical retention/join-back acceptance.
  let measured : InferPrefixBudget = { remaining_work: 10000, }
  check(measured)
  let used = 10000 - measured.remaining_work
  assert_true(used > 0 && used < 5000)
  let exact : InferPrefixBudget = { remaining_work: used * 2, }
  check(exact)
  assert_eq(exact.remaining_work, used)
  check(exact)
  assert_eq(exact.remaining_work, 0)
  let short : InferPrefixBudget = { remaining_work: used * 2 - 1, }
  check(short)
  assert_eq(short.remaining_work, used - 1)
  let rejected = try {
    check(short)
    false
  } catch {
    Abort(_) => true
  }
  assert_true(rejected)
  assert_true(short.remaining_work < used)

  // Metadata pre-spends this same owner before Common receives the remaining
  // allowance. A new source origin shares it; no post-hoc debt or fresh cap.
  let check_labeled = fn(budget : InferPrefixBudget) -> Unit raise Abort {
    let labeled = { ..construction, infer_labels: true, infer_budget: budget, }
    let labels = seed_infer_key_labels(labeled, [], [("id", "id")])
    if labels != [("id", "id")] {
      raise Abort(InvalidContext)
    }
    let continued = {
      ..labeled,
      generated: @origin.range(document, 0, 1, kind=Generated).unwrap(),
    }
    let pipeline = checked_query_prefix_pipeline(
      continued,
      query,
      mapping_context(),
      [],
      [],
      nodes,
      mapping_limits(),
      continued.infer_budget,
    )
    if @pipeline.step_count(pipeline) != 1 {
      raise Abort(InvalidContext)
    }
  }
  let labeled_measure : InferPrefixBudget = { remaining_work: 10000, }
  check_labeled(labeled_measure)
  let labeled_used = 10000 - labeled_measure.remaining_work
  assert_true(labeled_used > used)
  let labeled_exact : InferPrefixBudget = { remaining_work: labeled_used, }
  check_labeled(labeled_exact)
  assert_eq(labeled_exact.remaining_work, 0)
  let labeled_short : InferPrefixBudget = { remaining_work: labeled_used - 1, }
  let labeled_rejected = try {
    check_labeled(labeled_short)
    false
  } catch {
    Abort(_) => true
  }
  assert_true(labeled_rejected)
  assert_true(labeled_short.remaining_work < labeled_used - 1)
  @builder.discard(builder)
}
