///|
fn limits() -> @relation_results.Limits {
  {
    max_results: 20000,
    max_work: 20000000,
    max_nodes: 1000000,
    max_text_bytes: 20000000,
    max_depth: 30000,
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 20000000, max_nodes: 1000000, max_depth: 40000, },
      source_path="results.aql",
    ).unwrap(),
    {
      max_nodes: 1000000,
      max_depth: 40000,
      max_string_bytes: 20000000,
      max_total_string_bytes: 20000000,
    },
  ).unwrap()
}

///|
fn input() -> @contract.Contract {
  @contract.read_author(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"score\":{\"type\":\"number\",\"nullable\":true},\"field\":{\"type\":\"string\",\"nullable\":false},\"data\":{\"type\":\"json\",\"nullable\":false},\"ref\":{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"Customer\"}}}",
    ),
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  ).unwrap()
}

///|
fn pipeline() -> @pipeline.CheckedPipeline {
  @pipeline.check(
    cursor(
      "[{\"select\":[\"id\"],\"as\":\"ids\"},{\"derive\":{},\"from\":\"rows\"}]",
    ),
    [("rows", @schema.from_object(input()).unwrap())],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn check(text : String) -> @relation_results.CheckedResults raise {
  match @relation_results.check(pipeline(), cursor(text), limits()) {
    Ok(v) => v
    Err(e) => fail(@debug.to_string(e.kind))
  }
}

///|
test "order domains follow AuthorOrderable rather than canonical ordering" {
  for
    (body, allowed) in [
      ("\"type\":\"boolean\"", true),
      ("\"type\":\"date\"", true),
      ("\"type\":\"timestamp\"", true),
      ("\"type\":\"decimal\",\"precision\":4,\"scale\":2", true),
      (
        "\"type\":\"array\",\"items\":{\"type\":\"string\",\"nullable\":false}",
        false,
      ),
      ("\"type\":\"object\",\"fields\":{}", false),
      ("\"type\":\"vector\",\"dimensions\":3", false),
      ("\"type\":\"artifact_ref\"", false),
    ] {
    let c = @contract.read_author(
      cursor(
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"v\":{" +
        body +
        ",\"nullable\":true}}}",
      ),
      { max_nodes: 100, max_depth: 20, max_text_bytes: 10000, },
    ).unwrap()
    let p = @pipeline.check(
      cursor("[]"),
      [("rows", @schema.from_object(c).unwrap())],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_tokens: 100,
        max_depth: 100,
      },
    ).unwrap()
    let r = @relation_results.check(
      p,
      cursor(
        "{\"r\":{\"from\":\"rows\",\"fields\":[\"v\"],\"order_by\":[{\"v\":\"asc\"}]}}",
      ),
      limits(),
    )
    if allowed {
      assert_true(r is Ok(_))
    } else {
      assert_true(r is Err({ kind: NotAuthorOrderable("v"), .. }))
    }
  }
}

///|
test "many results share a source and deep metadata is traversed without recursion" {
  let entries : Array[String] = []
  for i in 0..<3000 {
    entries.push(
      "\"r" + i.to_string() + "\":{\"from\":\"rows\",\"fields\":[\"id\"]}",
    )
  }
  let many = check("{" + entries.join(",") + "}")
  assert_eq(@relation_results.count(many), 3000)
  assert_eq(
    @relation_results.target(@relation_results.lookup(many, "r2999").unwrap()),
    Input(0),
  )
  let text = "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"meta\":{\"nested\":" +
    "[".repeat(10000) +
    "0" +
    "]".repeat(10000) +
    "}}}"
  let source = cursor(text)
  assert_true(@relation_results.check(pipeline(), source, limits()) is Ok(_))
  assert_true(
    @relation_results.check(pipeline(), source, {
      ..limits(),
      max_depth: 10002,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    @relation_results.check(pipeline(), source, {
      ..limits(),
      max_depth: 10003,
    })
    is Ok(_),
  )
}

///|
test "results resolve authored bindings and retain projection order separately from type order" {
  let p = check(
    "{\"rows\":{\"from\":\"ids\",\"fields\":[\"id\"]},\"response\":{\"from\":\"rows\",\"fields\":[\"score\",\"id\"],\"order_by\":[{\"field\":\"score\",\"dir\":\"desc\",\"nulls\":\"first\"}]}}",
  )
  assert_eq(@relation_results.count(p), 2)
  let r = @relation_results.lookup(p, "rows").unwrap()
  assert_eq(@relation_results.target(r), Step(0))
  let r = @relation_results.lookup(p, "response").unwrap()
  assert_eq(@relation_results.target(r), Input(0))
  assert_eq(@relation_results.fields(r), ["score", "id"])
  let order = @relation_results.order_by(r).unwrap()
  assert_eq(order[0].direction, Desc)
  assert_eq(order[0].nulls, First)
  assert_true(order[0].explicit_nulls)
  assert_eq(@relation_results.pending_validations(r), [TotalDeterministicOrder])
  assert_true(@relation_results.result_at(p, -1) is None)
  assert_true(@relation_results.result_at(p, 2) is None)
  assert_true(@relation_results.lookup(p, "missing") is None)
  assert_eq(@decode.cursor_path(@relation_results.definition_source(r)), [
    Key("response"),
  ])
  @relation_results.fields(r).clear()
  @relation_results.order_by(r).unwrap().clear()
  @relation_results.pending_validations(r).clear()
  assert_eq(@relation_results.fields(r), ["score", "id"])
  assert_eq(@relation_results.order_by(r).unwrap().length(), 1)
  assert_eq(@relation_results.pending_validations(r).length(), 1)
  assert_eq(@pipeline.current(@relation_results.pipeline(p)), Step(1))
}

///|
test "order precedes projection and shorthand null placement is direction independent" {
  for dir in ["asc", "desc"] {
    let p = check(
      "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"score\":\"" +
      dir +
      "\"}]}}",
    )
    let r = @relation_results.result_at(p, 0).unwrap()
    assert_eq(@relation_results.fields(r), ["id"])
    let o = @relation_results.order_by(r).unwrap()[0]
    assert_eq(o.field, "score")
    assert_eq(o.nulls, Last)
    assert_true(!o.explicit_nulls)
  }
  let p = check(
    "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"field\":\"asc\"},{\"field\":\"field\",\"dir\":\"desc\",\"nulls\":\"last\"}]}}",
  )
  assert_eq(
    @relation_results.order_by(@relation_results.result_at(p, 0).unwrap())
    .unwrap()
    .length(),
    2,
  )
}

///|
test "missing order and unorderable projected values remain unresolved rather than published" {
  let p = check("{\"r\":{\"from\":\"rows\",\"fields\":[\"data\",\"ref\"]}}")
  let r = @relation_results.result_at(p, 0).unwrap()
  assert_true(@relation_results.order_by(r) is None)
  assert_eq(@relation_results.pending_validations(r), [TotalDeterministicOrder])
}

///|
test "closed result grammar requires from and nonempty unique field names" {
  for
    text in [
      "{}", "[]", "null", "{\"r\":{\"fields\":[\"id\"]}}", "{\"r\":{\"from\":\"rows\"}}",
      "{\"r\":{\"from\":\"rows\",\"fields\":[]}}", "{\"r\":{\"from\":null,\"fields\":[\"id\"]}}",
      "{\"r\":{\"from\":\"rows\",\"fields\":[{\"name\":\"id\"}]}}", "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"extra\":1}}",
    ] {
    assert_true(
      @relation_results.check(pipeline(), cursor(text), limits()) is Err(_),
    )
  }
  let e = @relation_results.check(
    pipeline(),
    cursor("{\"r\":{\"from\":\"rows\",\"fields\":[\"id\",\"id\"]}}"),
    limits(),
  ).unwrap_err()
  assert_true(e.kind is DuplicateField("id"))
  assert_eq(e.path, [Key("r"), Key("fields"), Index(1)])
  let e = @relation_results.check(
    pipeline(),
    cursor("{\"r\":{\"from\":\"ids\",\"fields\":[\"score\"]}}"),
    limits(),
  ).unwrap_err()
  assert_true(e.kind is UnknownField("score"))
  assert_eq(e.path, [Key("r"), Key("fields"), Index(0)])
}

///|
test "Result namespace does not become dataflow and current has no implicit public name" {
  for key in ["first", "step:1", "1"] {
    let e = @relation_results.check(
      pipeline(),
      cursor(
        "{\"first\":{\"from\":\"rows\",\"fields\":[\"id\"]},\"r\":{\"from\":\"" +
        key +
        "\",\"fields\":[\"id\"]}}",
      ),
      limits(),
    ).unwrap_err()
    assert_true(e.kind is UnknownSource(_))
    assert_eq(e.path, [Key("r"), Key("from")])
  }
}

///|
test "authored order types are strict and malformed order forms are rejected" {
  for key in ["ref", "data"] {
    let e = @relation_results.check(
      pipeline(),
      cursor(
        "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"" +
        key +
        "\":\"asc\"}]}}",
      ),
      limits(),
    ).unwrap_err()
    assert_true(e.kind is NotAuthorOrderable(_))
  }
  for
    order in [
      "[]", "null", "[{}]", "[{\"id\":\"up\"}]", "[{\"field\":\"id\",\"dir\":\"asc\"}]",
      "[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":null}]", "[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\",\"x\":1}]",
      "[{\"missing\":\"asc\"}]",
    ] {
    assert_true(
      @relation_results.check(
        pipeline(),
        cursor(
          "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":" +
          order +
          "}}",
        ),
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "metadata is retained with reserved keys only at the top level" {
  let p = check(
    "{\"__proto__\":{\"from\":\"rows\",\"fields\":[\"id\"],\"meta\":{\"custom\":[1,null,{\"actql_nested\":true}]}}}",
  )
  let r = @relation_results.lookup(p, "__proto__").unwrap()
  assert_eq(@relation_results.name(r), "__proto__")
  assert_eq(@decode.cursor_path(@relation_results.metadata(r).unwrap()), [
    Key("__proto__"),
    Key("meta"),
  ])
  for meta in ["{}", "[]", "null", "1"] {
    assert_true(
      @relation_results.check(
        pipeline(),
        cursor(
          "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"meta\":" +
          meta +
          "}}",
        ),
        limits(),
      )
      is Err({ kind: InvalidMetadata, .. }),
    )
  }
  let e = @relation_results.check(
    pipeline(),
    cursor(
      "{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"],\"meta\":{\"actql_reserved\":true}}}",
    ),
    limits(),
  ).unwrap_err()
  assert_true(e.kind is ReservedMetadataKey("actql_reserved"))
  assert_eq(e.path, [Key("r"), Key("meta"), Key("actql_reserved")])
}

///|
test "shared budgets accept exact consumption and reject one less" {
  let source = cursor(
    "{\"a\":{\"from\":\"rows\",\"fields\":[\"score\",\"id\"],\"meta\":{\"x\":[{\"y\":1}]}},\"b\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"score\":\"desc\"}]}}",
  )
  let p = pipeline()
  let u = @relation_results.usage(
    @relation_results.check(p, source, limits()).unwrap(),
  )
  let exact = {
    ..limits(),
    max_results: 2,
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@relation_results.check(p, source, exact) is Ok(_))
  for
    l in [
      { ..exact, max_results: 1, },
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_depth: 1, },
    ] {
    assert_true(
      @relation_results.check(p, source, l) is Err({ kind: BudgetExceeded, .. }),
    )
  }
  for
    l in [
      { ..limits(), max_results: -1, },
      { ..limits(), max_work: -1, },
      { ..limits(), max_nodes: -1, },
      { ..limits(), max_text_bytes: -1, },
      { ..limits(), max_depth: -1, },
    ] {
    assert_true(
      @relation_results.check(p, source, l) is Err({ kind: InvalidLimits, .. }),
    )
  }
}

///|
test "pipeline schema access is bounds checked without exposing input storage" {
  let p = pipeline()
  assert_true(@pipeline.schema_at(p, Input(-1)) is None)
  assert_true(@pipeline.schema_at(p, Input(1)) is None)
  assert_true(@pipeline.schema_at(p, Step(-1)) is None)
  assert_true(@pipeline.schema_at(p, Step(2)) is None)
  assert_true(
    @contract.type_equal(
      @schema.as_object(@pipeline.schema_at(p, Input(0)).unwrap()).unwrap(),
      input(),
      1000,
    ),
  )
}
