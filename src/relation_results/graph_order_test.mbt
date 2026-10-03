///|
fn current_trail_query(emit? : String = "paths") -> String {
  let identity = "{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[1,\"a\"],\"key_types\":[{\"kind\":\"number\"},{\"kind\":\"string\"}]}"
  "{\"traverse\":{\"start\":{\"ids\":[" +
  identity +
  "]},\"hops\":[{\"direction\":\"out\"}],\"path_mode\":\"trail\",\"emit\":\"" +
  emit +
  "\"}}"
}

///|
test "current MATCH and TRAIL orders retain their producer through take and structured Result projection" {
  for
    (body, field) in [
      (property_query_body(false, "[\"element\",\"score\"]"), "element"),
      (property_query_body(true, "[\"element\",\"src\",\"dst\"]"), "element"),
      (current_trail_query(), "edge_ids"),
      (current_trail_query(emit="nodes"), "node_id"),
    ] {
    let p = @pipeline.check_carriers(
      cursor("[" + body + ",{\"take\":1,\"as\":\"rows\"}]"),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(p, Input(0)) is None)
    assert_eq(
      @pipeline.order_origin(@pipeline.logical_order(p, Step(0)).unwrap()),
      Step(0),
    )
    assert_eq(
      @pipeline.order_origin(@pipeline.take_order(p, 1).unwrap()),
      Step(0),
    )
    let result = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"rows\",\"fields\":[\"" + field + "\"]}}"),
      limits(),
    ).unwrap()
    let order = resolve(result)
    assert_eq(@relation_results.publication_strategy(order), Inherited)
    assert_eq(
      @pipeline.order_origin(
        @relation_results.publication_inherited_order(order).unwrap(),
      ),
      Step(0),
    )
    assert_eq(@relation_results.publication_term_count(order), 0)
    let plain = @pipeline.check_carriers(
      cursor("[]"),
      [("rows", @pipeline.output_carrier(p).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(plain, Input(0)) is None)
  }
}

///|
test "current Graph row Bridge retains canonical producer order through structured projection" {
  for operation in ["\"node_rows\":true", "\"edge_rows\":true"] {
    let checked = @pipeline.check_carriers(
      cursor(
        "[{" + operation + "},{\"select\":[\"id\",\"labels\"],\"as\":\"rows\"}]",
      ),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.candidate_key(checked, Step(0)) is None)
    assert_eq(
      @pipeline.order_origin(@pipeline.logical_order(checked, Step(1)).unwrap()),
      Step(0),
    )
    let result = @relation_results.check(
      checked,
      cursor("{\"out\":{\"from\":\"rows\",\"fields\":[\"id\",\"labels\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(
      @relation_results.publication_strategy(resolve(result)),
      Inherited,
    )
    let bare = @pipeline.check_carriers(
      cursor("[]"),
      [("rows", @pipeline.output_carrier(checked).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(bare, Input(0)) is None)
  }
  assert_true(
    @pipeline.check_carriers(
      cursor("[{\"degree\":{\"direction\":\"out\"}}]"),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    )
    is Err({ kind: Graph(@graph.UnsupportedGraphOperation), .. }),
  )
}

///|
test "nullable business properties remain ordinary projected scalars not Graph label identities" {
  let matched = @pipeline.check_carriers(
    cursor("[" + property_query_body(true, "[\"element\",\"score\"]") + "]"),
    [("g", property_query_graph())],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let plain = @pipeline.check_carriers(
    cursor("[]"),
    [("rows", @pipeline.output_carrier(matched).unwrap())],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    plain,
    cursor("{\"out\":{\"from\":\"rows\",\"fields\":[\"score\"]}}"),
    limits(),
  ).unwrap()
  let order = resolve(results)
  assert_eq(@relation_results.publication_strategy(order), ProjectedFields)
  assert_true(@relation_results.publication_key(order) is None)
  assert_eq(@relation_results.publication_term_count(order), 1)
  let term = @relation_results.publication_term_at(order, 0).unwrap()
  assert_eq(term.field, Unqualified("score"))
  assert_eq(term.direction, Asc)
  assert_eq(term.nulls, Last)
}

///|
test "authored property order retains MATCH sequence for ties but cannot turn JSON identity into scalar key" {
  for
    suffix in [
      "", ",{\"select\":[{\"id\":\"element\"},\"score\"],\"as\":\"aliased\"}",
    ] {
    let renamed = suffix != ""
    let p = @pipeline.check_carriers(
      cursor(
        "[" +
        property_query_body(true, "[\"element\",\"score\"]") +
        suffix +
        "]",
      ),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let from = if renamed { "aliased" } else { "out" }
    let field = if renamed { "id" } else { "element" }
    let body = "{\"out\":{\"from\":\"" +
      from +
      "\",\"fields\":[\"" +
      field +
      "\",\"score\"],\"order_by\":[{\"field\":\"score\",\"dir\":\"desc\",\"nulls\":\"last\"}]}}"
    let result = @relation_results.check(p, cursor(body), limits()).unwrap()
    let order = resolve(result)
    assert_eq(@relation_results.publication_strategy(order), Authored)
    assert_true(@relation_results.publication_key(order) is None)
    assert_eq(
      @pipeline.order_origin(
        @relation_results.publication_inherited_order(order).unwrap(),
      ),
      Step(0),
    )
    assert_eq(@relation_results.publication_term_count(order), 1)
    assert_eq(
      @relation_results.publication_term_at(order, 0).unwrap().direction,
      Desc,
    )
    assert_true(
      @relation_results.publication_term_at(order, 0).unwrap().authored,
    )
    let plain = @pipeline.check_carriers(
      cursor("[]"),
      [(from, @pipeline.output_carrier(p).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let plain_result = @relation_results.check(plain, cursor(body), limits()).unwrap()
    assert_eq(
      @relation_results.resolve_publication_order(
        plain_result,
        0,
        max_work=10000,
        max_text_bytes=10000,
      ).unwrap_err().kind,
      UnresolvedOrder,
    )
  }
}

///|
test "dropping independent identity loses its key but retains checked MATCH sequence" {
  let p = @pipeline.check_carriers(
    cursor(
      "[" +
      property_query_body(true, "[\"element\",\"src\",\"dst\",\"score\"]") +
      ",{\"drop\":[\"element\"],\"as\":\"rows\"}]",
    ),
    [("g", property_query_graph())],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  assert_true(@pipeline.candidate_key(p, Step(1)) is None)
  let result = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"rows\",\"fields\":[\"src\",\"dst\",\"score\"]}}",
    ),
    limits(),
  ).unwrap()
  let order = resolve(result)
  assert_eq(@relation_results.publication_strategy(order), Inherited)
  assert_eq(
    @pipeline.order_origin(
      @relation_results.publication_inherited_order(order).unwrap(),
    ),
    Step(0),
  )
}
