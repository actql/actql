///|
fn ordered_graph_source(operation : String) -> String {
  "[{\"values\":{\"schema\":{\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"src\":1,\"dst\":2} ]},\"as\":\"edges\"},{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{" +
  operation +
  "}]"
}

///|
test "ordered graph queries retain their origin through take and nonorderable Result projection" {
  for
    (operation, field) in [
      (
        "\"match_nodes\":{\"where\":\"true\",\"fields\":[\"node_id\"]}", "node_id",
      ),
      ("\"match_edges\":{\"where\":\"true\",\"fields\":[\"src\"]}", "src"),
      (
        "\"reach\":{\"start\":1,\"direction\":\"out\",\"max_depth\":2}", "node_id",
      ),
      (
        "\"traverse\":{\"start\":{\"ids\":[1]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"nodes\"}",
        "node_id",
      ),
      (
        "\"traverse\":{\"start\":{\"ids\":[1]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"paths\"}",
        "edge_ids",
      ),
      (
        "\"shortest_path\":{\"source\":1,\"target\":2,\"direction\":\"out\",\"max_hops\":2}",
        "node_ids",
      ),
      ("\"components\":{\"kind\":\"weak\"}", "component_id"),
      ("\"components\":{\"kind\":\"strong\"}", "component_id"),
      ("\"graph_bounds\":{\"max_nodes\":0,\"max_degree\":0}", "kind"),
    ] {
    let source = ordered_graph_source(
      operation + "},{\"take\":1,\"as\":\"query\"",
    )
    let p = @pipeline.check_carriers(
      cursor(source),
      [],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(p, Step(1)) is None)
    let order = @pipeline.logical_order(p, Step(2)).unwrap()
    assert_eq(@pipeline.order_origin(order), Step(2))
    assert_eq(
      @pipeline.order_origin(@pipeline.take_order(p, 3).unwrap()),
      Step(2),
    )
    let results = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"query\",\"fields\":[\"" + field + "\"]}}"),
      limits(),
    ).unwrap()
    let published = resolve(results)
    assert_eq(@relation_results.publication_strategy(published), Inherited)
    assert_eq(
      @pipeline.order_origin(
        @relation_results.publication_inherited_order(published).unwrap(),
      ),
      Step(2),
    )
    assert_eq(@relation_results.publication_term_count(published), 0)
    // Same shape without the checked query producer has no inherited order.
    let plain = @pipeline.check_carriers(
      cursor("[]"),
      [("query", @pipeline.output_carrier(p).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(plain, Input(0)) is None)
  }
}

///|
test "graph row projection alone does not claim canonical logical order" {
  for
    operation in [
      "\"node_rows\":true", "\"edge_rows\":true", "\"degree\":{\"direction\":\"out\"}",
    ] {
    let p = @pipeline.check_carriers(
      cursor(ordered_graph_source(operation)),
      [],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(p, Step(2)) is None)
  }
}

///|
test "nullable Graph edge labels use projected Result order" {
  let p = @pipeline.check_carriers(
    cursor(ordered_graph_source("\"edge_rows\":true,\"as\":\"out\"")),
    [],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"src\",\"dst\",\"rel\"]}}"),
    limits(),
  ).unwrap()
  let order = resolve(results)
  assert_eq(@relation_results.publication_strategy(order), ProjectedFields)
  assert_true(@relation_results.publication_key(order) is None)
  for (index, name) in [(0, "src"), (1, "dst"), (2, "rel")] {
    let term = @relation_results.publication_term_at(order, index).unwrap()
    assert_eq(@relation_results.publication_term_field(term), Unqualified(name))
    assert_eq(@relation_results.publication_term_direction(term), Asc)
    assert_eq(@relation_results.publication_term_nulls(term), Last)
  }
}

///|
test "authored edge Result order retains the Graph identity without a non-null key" {
  for
    suffix in [
      "", "},{\"select\":[{\"source\":\"src\"},{\"target\":\"dst\"},{\"label\":\"rel\"}],\"as\":\"aliased\"",
    ] {
    let renamed = suffix != ""
    let p = @pipeline.check_carriers(
      cursor(ordered_graph_source("\"edge_rows\":true,\"as\":\"out\"" + suffix)),
      [],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let from = if renamed { "aliased" } else { "out" }
    let src = if renamed { "source" } else { "src" }
    let dst = if renamed { "target" } else { "dst" }
    let rel = if renamed { "label" } else { "rel" }
    for complete in [false, true] {
      let order = if complete {
        "[{\"" +
        src +
        "\":\"desc\"},{\"" +
        dst +
        "\":\"asc\"},{\"" +
        rel +
        "\":\"asc\"}]"
      } else {
        "[{\"" + src + "\":\"desc\"}]"
      }
      let results = @relation_results.check(
        p,
        cursor(
          "{\"out\":{\"from\":\"" +
          from +
          "\",\"fields\":[\"" +
          src +
          "\",\"" +
          dst +
          "\",\"" +
          rel +
          "\"],\"order_by\":" +
          order +
          "}}",
        ),
        limits(),
      ).unwrap()
      let resolved = resolve(results)
      assert_eq(@relation_results.publication_strategy(resolved), Authored)
      assert_eq(@relation_results.publication_term_count(resolved), 3)
      let first = @relation_results.publication_term_at(resolved, 0).unwrap()
      assert_eq(first.field, Unqualified(src))
      assert_eq(first.direction, Desc)
      assert_true(first.authored)
      let identity = @relation_results.publication_key(resolved).unwrap()
      assert_eq(@evidence.key_origin(identity), GraphProjectionResult)
      assert_eq(@evidence.key_pending(identity), [ValidateKeyProducer])
      for usage in [@evidence.CanonicalOrder, @evidence.ScalarIdentity] {
        assert_true(
          @evidence.select_key(
            cursor("null"),
            @evidence.singleton_key(identity),
            usage,
            { max_work: 1000, max_name_bytes: 1000, },
          ).unwrap().key
          is None,
        )
      }
    }
    // The same shape, without the producer, cannot authorize completion.
    let plain = @pipeline.check_carriers(
      cursor("[]"),
      [(from, @pipeline.output_carrier(p).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let results = @relation_results.check(
      plain,
      cursor(
        "{\"out\":{\"from\":\"" +
        from +
        "\",\"fields\":[\"" +
        src +
        "\"],\"order_by\":[{\"" +
        src +
        "\":\"asc\"}]}}",
      ),
      limits(),
    ).unwrap()
    assert_eq(
      @relation_results.resolve_publication_order(
        results,
        0,
        max_work=10000,
        max_text_bytes=10000,
      ).unwrap_err().kind,
      UnresolvedOrder,
    )
  }
}

///|
test "dropping a Graph identity component refuses authored edge order" {
  let p = @pipeline.check_carriers(
    cursor(
      ordered_graph_source(
        "\"edge_rows\":true},{\"drop\":[\"rel\"],\"as\":\"out\"",
      ),
    ),
    [],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"out\",\"fields\":[\"src\",\"dst\"],\"order_by\":[{\"src\":\"asc\"},{\"dst\":\"asc\"}]}}",
    ),
    limits(),
  ).unwrap()
  assert_eq(
    @relation_results.resolve_publication_order(
      results,
      0,
      max_work=10000,
      max_text_bytes=10000,
    ).unwrap_err().kind,
    UnresolvedOrder,
  )
}
