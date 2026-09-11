///|
test "session order crosses Events watermark and explicit Relation exposure" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(number)), (Unqualified("time"), Some(number))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=6,
    ).unwrap(),
  )
  let unknown = @pipeline.check_carriers(
    cursor(
      "[{\"to_events\":{\"id\":\"id\",\"time\":\"time\"}},{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\"}},{\"events\":true}]",
    ),
    [("rows", rows)],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  for i = 0; i < 3; i = i + 1 {
    assert_true(@pipeline.logical_order(unknown, Step(i)) is None)
  }
  for as_events in [false, true] {
    let before = if as_events {
      "{\"to_events\":{\"id\":\"id\",\"time\":\"time\"}},"
    } else {
      ""
    }
    let roles = if as_events { "" } else { "\"id\":\"id\",\"time\":\"time\"," }
    let after = if as_events {
      ",{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"drop\"}},{\"events\":true}"
    } else {
      ""
    }
    let p = @pipeline.check_carriers(
      cursor(
        "[" +
        before +
        "{\"session\":{" +
        roles +
        "\"by\":[],\"gap\":1}}" +
        after +
        ",{\"select\":[\"session_id\"]},{\"take\":1,\"as\":\"sessions\"}]",
      ),
      [("rows", rows)],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let r = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"sessions\",\"fields\":[\"session_id\"]}}"),
      limits(),
    ).unwrap()
    let order = resolve(r)
    assert_eq(@relation_results.publication_strategy(order), Inherited)
    let origin = @relation_results.publication_inherited_order(order).unwrap()
    assert_eq(
      @pipeline.order_origin(origin),
      Step(if as_events { 1 } else { 0 }),
    )
    assert_true(@pipeline.order_producer(origin).operation is Event(_))
  }
}

///|
test "dedupe partition order supports publication without sorting opaque payloads" {
  for by in ["[]", "[\"id\"]"] {
    let p = @pipeline.check(
      cursor(
        "[{\"dedupe_rows\":{\"by\":" +
        by +
        ",\"order_by\":[{\"score\":\"desc\"}]} ,\"as\":\"deduped\"}]",
      ),
      [("rows", @schema.from_object(input()).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let r = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"deduped\",\"fields\":[\"data\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
  }
}
