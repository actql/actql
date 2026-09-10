///|
fn join_pipeline(
  text : String,
) -> Result[@pipeline_typing.CheckedPipeline, @pipeline_typing.Issue] {
  @pipeline_typing.check(
    cursor(text),
    [("l", schema()), ("r", schema())],
    None,
    None,
    limits(),
  )
}

///|
test "templates resolve both join scopes and propagate outer null extension" {
  for kind in ["inner", "left", "full", "semi", "anti"] {
    let start = "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"" +
      kind +
      "\",\"on\":\"id\"}},"
    for side in ["left", "right"] {
      let text = start +
        "{\"derive\":{\"caption\":{\"template\":\"{" +
        side +
        ".amount}\"}}}]"
      if side == "right" && (kind == "semi" || kind == "anti") {
        assert_true(
          join_pipeline(text)
          is Err({ kind: Operation(UnknownField("right.amount")), .. }),
        )
      } else {
        let p = join_pipeline(text).unwrap()
        let caption = @schema.lookup(
          @pipeline_typing.output_schema(p),
          Unqualified("caption"),
        ).unwrap()
        assert_eq(
          caption.nullable,
          kind == "full" || (kind == "left" && side == "right"),
        )
        let operation = unary(@pipeline_typing.step_at(p, 1).unwrap().operation)
        let references = @relation.references(
          @relation.binding_at(operation, 0).unwrap(),
        )
        assert_eq(references.length(), 1)
        assert_eq(
          references[0].target,
          @relation.InputField(
            @schema.Qualified(
              if side == "left" {
                Left
              } else {
                Right
              },
              "amount",
            ),
          ),
        )
      }
    }
    for side in ["left", "right"] {
      let issue = join_pipeline(
        start +
        "{\"derive\":{\"caption\":{\"template\":\"{" +
        side +
        ".missing}\"}}}]",
      ).unwrap_err()
      assert_eq(issue.kind, Operation(UnknownField(side + ".missing")))
      assert_eq(issue.path, [@source.Index(1), Key("derive"), Key("caption")])
      assert_eq(issue.range, None)
    }
    for
      placeholder in [
        "left.amount.x", "right.amount[0]", "other.amount", "$p", "left.",
      ] {
      assert_true(
        join_pipeline(
          start +
          "{\"derive\":{\"caption\":{\"template\":\"{" +
          placeholder +
          "}\"}}}]",
        )
        is Err(_),
      )
    }
    let p = join_pipeline(
      start +
      "{\"derive\":{\"caption\":{\"template\":\"{{right.missing}} {left.amount}\"}}}]",
    ).unwrap()
    assert_eq(
      @relation.references(
        @relation.binding_at(
          unary(@pipeline_typing.step_at(p, 1).unwrap().operation),
          0,
        ).unwrap(),
      ).length(),
      1,
    )
  }
}

///|
test "join resolves both sides from inputs and prior bindings without inventing names" {
  let overridden = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"},\"from\":\"r\"}]",
  ).unwrap()
  assert_eq(@pipeline_typing.step_at(overridden, 0).unwrap().input, Input(0))
  assert_true(
    @pipeline_typing.step_at(overridden, 0).unwrap().operation
    is Join(right=Input(1), ..),
  )
  let p = join_pipeline(
    "[{\"select\":[\"id\",\"amount\"],\"from\":\"r\",\"as\":\"right_rows\"},{\"join\":{\"left\":\"l\",\"with\":\"right_rows\",\"kind\":\"left\",\"on\":\"id\"},\"as\":\"joined\"}]",
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  assert_eq(step.input, Input(0))
  assert_true(step.operation is Join(right=Step(0), ..))
  assert_eq(@pipeline_typing.current(p), Step(1))
  assert_eq(@pipeline_typing.lookup(p, "joined"), Some(Step(1)))
  let self_join = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"l\",\"kind\":\"inner\",\"on\":\"id\"}}]",
  ).unwrap()
  assert_true(
    @pipeline_typing.step_at(self_join, 0).unwrap().operation
    is Join(right=Input(0), ..),
  )
  for
    text in [
      "[{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"}}]", "[{\"join\":{\"left\":\"later\",\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"},\"as\":\"later\"}]",
      "[{\"join\":{\"left\":\"l\",\"with\":\"later\",\"kind\":\"inner\",\"on\":\"id\"},\"as\":\"later\"}]",
      "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"},\"from\":\"missing\"}]",
    ] {
    assert_true(join_pipeline(text) is Err(_))
  }
}

///|
test "all unary operations consume qualified outputs without silently flattening" {
  let start = "{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"}}"
  let p = join_pipeline(
    "[" +
    start +
    ",{\"filter\":\"right.amount > 0\"},{\"derive\":{\"total\":\"left.amount + right.amount\"}},{\"rename\":{\"left.id\":\"id\"}},{\"drop\":[\"right.id\"]},{\"select\":[\"id\",\"total\",{\"amount\":\"left.amount\"}]}]",
  ).unwrap()
  let output = @pipeline_typing.output_schema(p)
  assert_true(@schema.as_object(output) is Some(_))
  assert_true(@schema.lookup(output, Unqualified("total")).unwrap().nullable)
  assert_true(!@schema.lookup(output, Unqualified("id")).unwrap().nullable)
  let filtered = @pipeline_typing.step_at(p, 1).unwrap()
  assert_true(@schema.as_object(filtered.output) is None)
  let derived = unary(@pipeline_typing.step_at(p, 2).unwrap().operation)
  let refs = @relation.references(@relation.binding_at(derived, 0).unwrap())
  assert_eq(
    refs[0].target,
    @relation.InputField(@schema.Qualified(Left, "amount")),
  )
  assert_eq(
    refs[1].target,
    @relation.InputField(@schema.Qualified(Right, "amount")),
  )
  for
    op in [
      "{\"derive\":{}}", "{\"rename\":{}}", "{\"drop\":[]}", "{\"select\":[\"left.id\",\"right.id\"]}",
    ] {
    let p = join_pipeline("[" + start + "," + op + "]").unwrap()
    assert_true(@schema.as_object(@pipeline_typing.output_schema(p)) is None)
  }
  for
    op in [
      "{\"filter\":\"id = 'a'\"}", "{\"select\":[\"id\"]}", "{\"derive\":{\"left.x\":\"1\"}}",
      "{\"rename\":{\"left.id\":\"right.id\"}}",
    ] {
    assert_true(join_pipeline("[" + start + "," + op + "]") is Err(_))
  }
}

///|
test "derived flat fields coexist with qualified scopes and sequential replacements" {
  let p = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"full\",\"on\":\"id\"}},{\"derive\":[{\"x\":\"left.amount\"},{\"x2\":\"x + right.amount\"}]},{\"filter\":\"x2 > 0 AND left.amount > 0\"}]",
  ).unwrap()
  let output = @pipeline_typing.output_schema(p)
  assert_true(@schema.lookup(output, Unqualified("x2")).unwrap().nullable)
  assert_true(
    @schema.lookup(output, Qualified(Left, "amount")).unwrap().nullable,
  )
  assert_true(@schema.as_object(output) is None)
}

///|
test "rejoin requires flat schemas on both sides and explicit projection enables it" {
  let start = "{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"},\"as\":\"raw\"}"
  assert_true(
    join_pipeline(
      "[" +
      start +
      ",{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"}}]",
    )
    is Err({ kind: Join(@join.QualifiedInput(Left)), .. }),
  )
  assert_true(
    join_pipeline(
      "[" +
      start +
      ",{\"join\":{\"left\":\"l\",\"with\":\"raw\",\"kind\":\"inner\",\"on\":\"id\"}}]",
    )
    is Err({ kind: Join(@join.QualifiedInput(Right)), .. }),
  )
  let p = join_pipeline(
    "[" +
    start +
    ",{\"select\":[{\"id\":\"left.id\"}]},{\"join\":{\"with\":\"r\",\"kind\":\"semi\",\"on\":\"id\"}}]",
  ).unwrap()
  assert_eq(
    @schema.fields(@pipeline_typing.output_schema(p)).map(f => f.name),
    [@schema.Qualified(Left, "id")],
  )
}

///|
test "mixed expression diagnostics retain qualified reference source and token range" {
  let prefix = "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"}},{\"derive\":{\"x\":{\"add\":[{\"literal\":1},"
  let issue = match join_pipeline(prefix + "\"right.missing\"]}}}]") {
    Err(e) => e
    _ => abort("expected failure")
  }
  assert_true(issue.kind is Operation(UnknownField("right.missing")))
  assert_eq(issue.path, [
    @source.Index(1),
    Key("derive"),
    Key("x"),
    Key("add"),
    Index(1),
  ])
  assert_eq(issue.range, Some({ start: 0, end: 13, }))
  let issue = match
    join_pipeline(prefix + "{\"field\":\"left.missing\"}]}}}]") {
    Err(e) => e
    _ => abort("expected failure")
  }
  assert_true(issue.kind is Operation(UnknownField("left.missing")))
  assert_eq(issue.path, [
    @source.Index(1),
    Key("derive"),
    Key("x"),
    Key("add"),
    Index(1),
  ])
  assert_eq(issue.range, None)
}

///|
test "join obligations and metadata survive a later branch selection" {
  let p = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"full\",\"on\":\"id\",\"cardinality\":\"one_to_one\",\"max_output_rows\":3},\"as\":\"joined\",\"meta\":{\"note\":\"x\"}},{\"select\":[\"id\"],\"from\":\"l\"}]",
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.metadata is Some(_))
  let j = match step.operation {
    Join(checked~, ..) => checked
    _ => abort("expected join")
  }
  assert_true(
    @join.pending_validations(j).contains(StableIdentity(@schema.Left)),
  )
  assert_true(
    @join.pending_validations(j).contains(ValidateCardinality(OneToOne)),
  )
  assert_eq(@join.output_guard(j), Some(Literal(3L)))
}

///|
test "join and unary operations share cumulative budgets" {
  let text = "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"}},{\"derive\":{\"x\":\"left.amount + right.amount\"}},{\"select\":[\"x\"]}]"
  let p = join_pipeline(text).unwrap()
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
    max_tokens: u.tokens,
  }
  for l in [exact] {
    assert_true(
      @pipeline_typing.check(
        cursor(text),
        [("l", schema()), ("r", schema())],
        None,
        None,
        l,
      )
      is Ok(_),
    )
  }
  for
    l in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_tokens: u.tokens - 1, },
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(text),
        [("l", schema()), ("r", schema())],
        None,
        None,
        l,
      )
      is Err(_),
    )
  }
}
