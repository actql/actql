///|
fn joined_pipeline(
  kind : String,
  suffix? : String = "",
) -> @pipeline.CheckedPipeline {
  @pipeline.check(
    cursor(
      "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"" +
      kind +
      "\",\"on\":\"id\"},\"as\":\"joined\"}" +
      suffix +
      "]",
    ),
    [
      ("l", @schema.from_object(input()).unwrap()),
      ("r", @schema.from_object(input()).unwrap()),
    ],
    None,
    None,
    {
      max_steps: 100,
      max_work: 1000000,
      max_text_bytes: 1000000,
      max_nodes: 1000000,
      max_tokens: 10000,
      max_depth: 1000,
    },
  ).unwrap()
}

///|
test "Results retain raw join provenance and order before projection for all kinds" {
  for kind in ["inner", "left", "full", "semi", "anti"] {
    let p = joined_pipeline(kind)
    let results = @relation_results.check(
      p,
      cursor(
        "{\"r\":{\"from\":\"joined\",\"fields\":[\"left.id\"],\"order_by\":[{\"left.score\":\"asc\"}]}}",
      ),
      limits(),
    ).unwrap()
    let r = @relation_results.result_at(results, 0).unwrap()
    let schema = @relation_results.output_schema(r)
    assert_true(@schema.as_object(schema) is None)
    assert_eq(
      @schema.lookup(schema, Qualified(Left, "id")).unwrap().nullable,
      kind == "full",
    )
    assert_eq(@relation_results.fields(r), ["left.id"])
    assert_eq(@relation_results.pending_validations(r), [
      TotalDeterministicOrder,
    ])
    assert_true(
      @relation_results.check(
        p,
        cursor("{\"r\":{\"from\":\"joined\",\"fields\":[\"id\"]}}"),
        limits(),
      )
      is Err({ kind: UnknownField("id"), .. }),
    )
  }
}

///|
test "Result projection and ordering never fall back to the wrong join side" {
  let p = joined_pipeline("left")
  let results = @relation_results.check(
    p,
    cursor(
      "{\"r\":{\"from\":\"joined\",\"fields\":[\"right.id\",\"left.id\"],\"order_by\":[{\"field\":\"left.id\",\"dir\":\"desc\",\"nulls\":\"first\"}]}}",
    ),
    limits(),
  ).unwrap()
  let r = @relation_results.result_at(results, 0).unwrap()
  let schema = @relation_results.output_schema(r)
  assert_true(@schema.lookup(schema, Qualified(Right, "id")).unwrap().nullable)
  assert_true(!@schema.lookup(schema, Qualified(Left, "id")).unwrap().nullable)
  assert_eq(@relation_results.fields(r), ["right.id", "left.id"])
  for
    text in [
      "{\"r\":{\"from\":\"joined\",\"fields\":[\"left.id\",\"left.id\"]}}", "{\"r\":{\"from\":\"joined\",\"fields\":[\"left.id\"],\"order_by\":[{\"left.ref\":\"asc\"}]}}",
      "{\"r\":{\"from\":\"joined\",\"fields\":[{\"id\":\"left.id\"}]}}",
    ] {
    assert_true(@relation_results.check(p, cursor(text), limits()) is Err(_))
  }
}

///|
test "Results accept explicitly flattened join output and enforce qualified schema budgets" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"select\":[{\"id\":\"left.id\"},{\"score\":\"right.score\"}],\"as\":\"flat\"}",
  )
  let text = "{\"r\":{\"from\":\"flat\",\"fields\":[\"id\",\"score\"]},\"raw\":{\"from\":\"joined\",\"fields\":[\"right.id\"]}}"
  let results = @relation_results.check(p, cursor(text), limits()).unwrap()
  assert_true(
    @schema.as_object(
      @relation_results.output_schema(
        @relation_results.result_at(results, 0).unwrap(),
      ),
    )
    is Some(_),
  )
  let u = @relation_results.usage(results)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@relation_results.check(p, cursor(text), exact) is Ok(_))
  for
    l in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @relation_results.check(p, cursor(text), l)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}
