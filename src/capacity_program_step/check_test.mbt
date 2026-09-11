///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 30,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn pipeline(
  body : String,
  parameters? : @parameter.Declarations? = None,
  field_type? : @contract.Contract = @contract.primitive(
    NumberType,
    nullable=false,
  ),
) -> @pipeline.CheckedPipeline {
  let schema = @schema.from_object(
    @contract.object_contract(
      [("id", field_type)],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  ).unwrap()
  @pipeline.check(cursor(body), [("rows", schema)], parameters, None, {
    max_steps: 20,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }).unwrap()
}

///|
// Build integrity-valid claims, including intentionally false application claims.
// Hash correctness is covered independently by the SHA and wire corpus suites.
fn proof(
  law : String,
  value : Int64,
  derivation : String,
  reference? : String = "checked-step:0",
  unit? : String = "rows",
  inputs? : Array[String] = [],
) -> @wire.ProgramProofClaim {
  let body = "{\"inputs\":" +
    cid_array(inputs) +
    ",\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    reference +
    "\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(body))
  let dependencies = inputs.copy()
  dependencies.push(id)
  let preimage = "{\"dependencies\":" +
    cid_array(dependencies, unique=true) +
    ",\"derivation\":" +
    derivation +
    ",\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    id +
    "\",\"semantic_ref\":\"" +
    reference +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage + "}"))
  let bytes = @utf8.encode(preimage + ",\"witness_cid\":\"" + cid + "\"}")
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let wire = @wire.admit(bytes, cid, caps).unwrap()
  @wire.bind_program_proof(@utf8.encode(body), wire, caps).unwrap()
}

///|
fn cid_array(ids : Array[String], unique? : Bool = false) -> String {
  let ordered : Array[String] = []
  for id in ids {
    if unique && ordered.contains(id) {
      continue
    }
    ordered.push(id)
    let mut i = ordered.length() - 1
    while i > 0 && ordered[i] < ordered[i - 1] {
      let previous = ordered[i - 1]
      ordered[i - 1] = ordered[i]
      ordered[i] = previous
      i = i - 1
    }
  }
  "[" + ordered.map(id => "\"" + id + "\"").join(",") + "]"
}

///|
fn bound_id(bound : @capacity_program_step.StepBound) -> String {
  @wire.cid(
    @wire.program_proof_witness(@capacity_program_step.checked_proof(bound)),
  )
}

///|
fn count_declarations() -> @parameter.Declarations {
  @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\",\"default\":7},\"unused\":{\"type\":\"string\",\"default\":\"text\"}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn count_values(
  d : @parameter.Declarations,
  supplied : String?,
) -> @parameter.BoundValues raise {
  let result = @parameter.bind(d, supplied.map(cursor), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  guard result is Ready(values) else { fail("complete binding expected") }
  values
}

///|
test "bound selection counts retain default or supplied values from the exact owner" {
  let d = count_declarations()
  for
    body in [
      "[{\"take\":{\"$param\":\"n\"}}]", "[{\"top_k\":{\"k\":{\"$param\":\"n\"},\"by\":[{\"id\":\"asc\"}]}}]",
      "[{\"top_k_by\":{\"partition_by\":[],\"k\":{\"$param\":\"n\"},\"by\":[{\"id\":\"asc\"}]}}]",
    ] {
    let p = pipeline(body, parameters=Some(d))
    let law = if body.contains("top_k") {
      "actql.bound.top-k"
    } else {
      "actql.bound.take"
    }
    for
      (supplied, n) in [
        (None, 7L),
        (Some("{\"n\":9}"), 9L),
        (Some("{\"n\":9007199254740991}"), 9007199254740991L),
      ] {
      let values = count_values(d, supplied)
      let bindings = @capacity_program_step.bind_parameters(
        p,
        values,
        max_work=2,
        max_text_bytes=7,
      ).unwrap()
      assert_eq(@capacity_program_step.binding_usage(bindings), (2, 7))
      assert_true(
        physical_equal(
          @capacity_program_step.parameter_values(bindings),
          values,
        ),
      )
      let claim = proof(
        law,
        n,
        "{\"maximum\":" + n.to_string() + ",\"op\":\"clamp\"}",
      )
      let checked = @capacity_program_step.check_with_inputs(
        p,
        0,
        claim,
        [],
        bindings=Some(bindings),
      ).unwrap()
      assert_true(
        physical_equal(
          @capacity_program_step.checked_bindings(checked).unwrap(),
          bindings,
        ),
      )
      assert_true(
        @capacity_program_step.check(p, 0, claim) is Err(UnresolvedCount),
      )
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=1,
          max_text_bytes=7,
        )
        is Err(BindingWorkLimit),
      )
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=2,
          max_text_bytes=6,
        )
        is Err(BindingTextLimit),
      )
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=-1,
          max_text_bytes=7,
        )
        is Err(InvalidBindingLimits),
      )
      let other = pipeline(body, parameters=Some(d))
      assert_true(
        @capacity_program_step.check_with_inputs(
          other,
          0,
          claim,
          [],
          bindings=Some(bindings),
        )
        is Err(BindingOwnerMismatch),
      )
    }
    let foreign_values = count_values(count_declarations(), None)
    assert_true(
      @capacity_program_step.bind_parameters(
        p,
        foreign_values,
        max_work=2,
        max_text_bytes=7,
      )
      is Err(BindingOwnerMismatch),
    )
    for
      supplied in [
        "{\"n\":0}", "{\"n\":-1}", "{\"n\":1.5}", "{\"n\":9007199254740992}",
      ] {
      let bindings = @capacity_program_step.bind_parameters(
        p,
        count_values(d, Some(supplied)),
        max_work=2,
        max_text_bytes=7,
      ).unwrap()
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          0,
          proof(law, 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
          [],
          bindings=Some(bindings),
        )
        is Err(InvalidBoundCount),
      )
    }
  }
}

///|
test "bound counts clamp producer bounds without replacing derivation maxima" {
  let d = count_declarations()
  let p = pipeline(
    "[{\"take\":3},{\"take\":{\"$param\":\"n\"}}]",
    parameters=Some(d),
  )
  let bindings = @capacity_program_step.bind_parameters(
    p,
    count_values(d, None),
    max_work=2,
    max_text_bytes=7,
  ).unwrap()
  let input = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
  ).unwrap()
  let id = bound_id(input)
  for maximum in [7, 3] {
    let claim = proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" +
      id +
      "\",\"maximum\":" +
      maximum.to_string() +
      ",\"op\":\"clamp\"}",
      reference="checked-step:1",
      inputs=[id],
    )
    let result = @capacity_program_step.check_with_inputs(
      p,
      1,
      claim,
      [input],
      bindings=Some(bindings),
    )
    if maximum == 7 {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(InvalidDerivation))
    }
  }
}

///|
fn consume(
  producer : @pipeline.CheckedPipeline,
  target : @pipeline.Target,
  body : String,
) -> @pipeline.CheckedPipeline {
  @pipeline.check_with_evidence(
    cursor(body),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(producer, target).unwrap(),
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 20,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "producer edges retain exact source owners and cumulative traversal work" {
  let root = pipeline("[{\"take\":7}]")
  let root_claim = proof(
    "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
  )
  let a = @capacity_program_step.check(root, 0, root_claim).unwrap()
  let id = bound_id(a)
  let middle = consume(root, @pipeline.Step(0), "[]")
  let end = consume(
    middle,
    @pipeline.Input(0),
    "[{\"append\":{\"with\":\"prior\"}}]",
  )
  let claim = proof(
    "actql.bound.append",
    14,
    "{\"left\":\"" + id + "\",\"op\":\"add\",\"right\":\"" + id + "\"}",
    inputs=[id, id],
  )
  let checked = @capacity_program_step.check_with_inputs(
    end,
    0,
    claim,
    [a, a],
    max_input_work=4,
  ).unwrap()
  assert_eq(@capacity_program_step.input_work(checked), 4)
  assert_true(
    physical_equal(@capacity_program_step.checked_pipeline(checked), end),
  )
  assert_true(
    physical_equal(@capacity_program_step.input_at(checked, 0).unwrap(), a),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a, a],
      max_input_work=3,
    )
    is Err(InputWorkLimit),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(end, 0, claim, [a, a])
    is Err(InputWorkLimit),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a, a],
      max_input_work=-1,
    )
    is Err(InvalidInputWorkLimit),
  )
  let foreign = @capacity_program_step.check(
    pipeline("[{\"take\":7}]"),
    0,
    root_claim,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a, foreign],
      max_input_work=4,
    )
    is Err(InputOwnerMismatch(1)),
  )
  let ordinary = pipeline("[{\"append\":{\"with\":\"rows\"}}]")
  assert_true(
    @capacity_program_step.check_with_inputs(
      ordinary,
      0,
      claim,
      [a, a],
      max_input_work=4,
    )
    is Err(MissingInputProducer(0)),
  )
}

///|
test "forwarded proof inputs use an iterative bounded walk" {
  let root = pipeline("[{\"take\":7}]")
  let a = @capacity_program_step.check(
    root,
    0,
    proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
  ).unwrap()
  let mut owner = root
  let mut target = @pipeline.Step(0)
  for _ in 0..<2000 {
    owner = consume(owner, target, "[]")
    target = @pipeline.Input(0)
  }
  let end = consume(owner, target, "[{\"take\":3}]")
  let id = bound_id(a)
  let claim = proof(
    "actql.bound.take",
    3,
    "{\"input\":\"" + id + "\",\"maximum\":3,\"op\":\"clamp\"}",
    inputs=[id],
  )
  let checked = @capacity_program_step.check_with_inputs(
    end,
    0,
    claim,
    [a],
    max_input_work=2001,
  ).unwrap()
  assert_eq(@capacity_program_step.input_work(checked), 2001)
  assert_true(
    @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a],
      max_input_work=2000,
    )
    is Err(InputWorkLimit),
  )
}

///|
test "unnest derives expansion from the admitted array bound including outer empty arrays" {
  for
    (maximum, outer, factor) in [
      (Some(0L), false, 0L),
      (Some(0L), true, 1L),
      (Some(3L), true, 3L),
      (None, false, 0L),
    ] {
    let p = pipeline(
      "[{\"take\":7},{\"unnest\":{\"column\":\"id\",\"as\":\"value\",\"outer\":" +
      outer.to_string() +
      "}}]",
      field_type=@contract.array_contract(
        @contract.primitive(NumberType, nullable=false),
        nullable=false,
        max_items=maximum,
      ).unwrap(),
    )
    let a = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
    ).unwrap()
    let id = bound_id(a)
    let claim = proof(
      "actql.bound.unnest-array-items",
      7 * factor,
      "{\"factor\":" +
      factor.to_string() +
      ",\"input\":\"" +
      id +
      "\",\"op\":\"multiply\"}",
      reference="checked-step:1",
      inputs=[id],
    )
    let checked = @capacity_program_step.check_with_inputs(p, 1, claim, [a])
    if maximum is None {
      assert_true(checked is Err(UnresolvedCount))
    } else {
      assert_true(checked is Ok(_))
    }
  }
}

///|
test "repeated append operands remain two occurrences and arithmetic overflow fails" {
  for maximum in [7L, 9007199254740991L] {
    // The actual group has at most one row, while the independent take proof
    // deliberately uses its looser literal bound. Pipeline counting stays valid.
    let p = pipeline(
      "[{\"group\":{\"by\":[],\"aggregates\":{}}},{\"take\":" +
      maximum.to_string() +
      ",\"as\":\"a\"},{\"append\":{\"with\":\"a\"}}]",
    )
    let a = @capacity_program_step.check(
      p,
      1,
      proof(
        "actql.bound.take",
        maximum,
        "{\"maximum\":" + maximum.to_string() + ",\"op\":\"clamp\"}",
        reference="checked-step:1",
      ),
    ).unwrap()
    let id = bound_id(a)
    let derivation = "{\"left\":\"" +
      id +
      "\",\"op\":\"add\",\"right\":\"" +
      id +
      "\"}"
    let claim = proof(
      "actql.bound.append",
      14,
      derivation,
      reference="checked-step:2",
      inputs=[id, id],
    )
    let result = @capacity_program_step.check_with_inputs(p, 2, claim, [a, a])
    if maximum == 7 {
      let checked = result.unwrap()
      assert_eq(@capacity_program_step.input_count(checked), 2)
      assert_true(
        physical_equal(
          @capacity_program_step.input_at(checked, 0).unwrap(),
          @capacity_program_step.input_at(checked, 1).unwrap(),
        ),
      )
    } else {
      assert_true(result is Err(BoundOverflow))
    }
  }
}

///|
test "selection clamps a verified input and unpivot counts repeated columns" {
  let p = pipeline(
    "[{\"take\":7},{\"take\":3},{\"unpivot\":{\"columns\":[\"id\",\"id\"],\"keep\":[],\"name_column\":\"name\",\"value_column\":\"value\"}}]",
  )
  let a = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
  ).unwrap()
  let a_id = bound_id(a)
  let b = @capacity_program_step.check_with_inputs(
    p,
    1,
    proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" + a_id + "\",\"maximum\":3,\"op\":\"clamp\"}",
      reference="checked-step:1",
      inputs=[a_id],
    ),
    [a],
  ).unwrap()
  let b_id = bound_id(b)
  let claim = proof(
    "actql.bound.unpivot",
    6,
    "{\"factor\":2,\"input\":\"" + b_id + "\",\"op\":\"multiply\"}",
    reference="checked-step:2",
    inputs=[b_id],
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [b]) is Ok(_),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [a])
    is Err(InputTargetMismatch(0)),
  )
  let false_factor = proof(
    "actql.bound.unpivot",
    6,
    "{\"factor\":1,\"input\":\"" + b_id + "\",\"op\":\"multiply\"}",
    reference="checked-step:2",
    inputs=[b_id],
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, false_factor, [b])
    is Err(InvalidDerivation),
  )
}

///|
test "append binds ordered edges independently of sorted proof operands" {
  let body = "[{\"group\":{\"by\":[],\"aggregates\":{}},\"as\":\"a\"},{\"group\":{\"by\":[],\"aggregates\":{}},\"from\":\"rows\",\"as\":\"b\"},{\"append\":{\"with\":\"b\"},\"from\":\"a\"}]"
  let p = pipeline(body)
  let a_claim = proof("actql.bound.global-group", 1, "{\"op\":\"source\"}")
  let a = @capacity_program_step.check(p, 0, a_claim).unwrap()
  let b = @capacity_program_step.check(
    p,
    1,
    proof(
      "actql.bound.global-group",
      1,
      "{\"op\":\"source\"}",
      reference="checked-step:1",
    ),
  ).unwrap()
  let left = bound_id(a)
  let right = bound_id(b)
  let derivation = "{\"left\":\"" +
    left +
    "\",\"op\":\"add\",\"right\":\"" +
    right +
    "\"}"
  let claim = proof(
    "actql.bound.append",
    2,
    derivation,
    reference="checked-step:2",
    inputs=[left, right],
  )
  let inputs = [a, b]
  let result = @capacity_program_step.check_with_inputs(p, 2, claim, inputs).unwrap()
  inputs[0] = b
  assert_true(
    physical_equal(@capacity_program_step.input_at(result, 0).unwrap(), a),
  )
  assert_eq(@capacity_program_step.input_count(result), 2)
  assert_true(@capacity_program_step.input_at(result, -1) is None)
  assert_true(@capacity_program_step.input_at(result, 2) is None)
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [b, a])
    is Err(InputTargetMismatch(0)),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [a])
    is Err(InputCountMismatch),
  )
  let foreign = @capacity_program_step.check(pipeline(body), 0, a_claim).unwrap()
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [foreign, b])
    is Err(InputOwnerMismatch(0)),
  )
  let reversed = "{\"left\":\"" +
    right +
    "\",\"op\":\"add\",\"right\":\"" +
    left +
    "\"}"
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      2,
      proof("actql.bound.append", 2, reversed, reference="checked-step:2", inputs=[
        left, right,
      ]),
      [a, b],
    )
    is Err(InvalidDerivation),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      2,
      proof("actql.bound.append", 3, derivation, reference="checked-step:2", inputs=[
        left, right,
      ]),
      [a, b],
    )
    is Err(ValueMismatch),
  )
}

///|
test "operation applications retain the checked owner and verify global and literal clamp laws" {
  for
    (body, law, n, derivation) in [
      (
        "[{\"group\":{\"by\":[],\"aggregates\":{}}}]", "actql.bound.global-group",
        1, "{\"op\":\"source\"}",
      ),
      (
        "[{\"take\":7}]", "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"take\":{\"count\":7,\"offset\":100}}]", "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"top_k\":{\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]", "actql.bound.top-k",
        7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"top_k_by\":{\"partition_by\":[],\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]",
        "actql.bound.top-k", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
    ] {
    let p = pipeline(body)
    let claim = proof(law, n.to_int64(), derivation)
    let checked = @capacity_program_step.check(p, 0, claim).unwrap()
    assert_true(
      physical_equal(@capacity_program_step.checked_pipeline(checked), p),
    )
    assert_true(
      physical_equal(@capacity_program_step.checked_proof(checked), claim),
    )
    assert_eq(@capacity_program_step.checked_step(checked), 0)
    assert_eq(@capacity_program_step.subject_ref(p, 0), Some("checked-step:0"))
    assert_true(@capacity_program_step.subject_ref(p, -1) is None)
    assert_true(@capacity_program_step.subject_ref(p, 1) is None)
    assert_true(@capacity_program_step.check(p, 1, claim) is Err(MissingStep))
  }
}

///|
test "matching values and valid proof identities do not establish an operation application" {
  let group = pipeline(
    "[{\"group\":{\"by\":[],\"aggregates\":{}},\"as\":\"grouped\"}]",
  )
  let take = pipeline("[{\"take\":1}]")
  let grouped = pipeline("[{\"group\":{\"by\":[\"id\"],\"aggregates\":{}}}]")
  let source = "{\"op\":\"source\"}"
  let group_proof = proof("actql.bound.global-group", 1, source)
  assert_true(
    @capacity_program_step.check(take, 0, group_proof) is Err(LawMismatch),
  )
  assert_true(
    @capacity_program_step.check(grouped, 0, group_proof)
    is Err(UnsupportedOperation),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 2, source),
    )
    is Err(ValueMismatch),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 1, source, unit="nodes"),
    )
    is Err(LawMismatch),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 1, source, reference="grouped"),
    )
    is Err(SubjectMismatch),
  )
  assert_true(
    @capacity_program_step.check(take, 0, proof("actql.bound.take", 1, source))
    is Err(InvalidDerivation),
  )
  assert_true(
    @capacity_program_step.check(
      take,
      0,
      proof("actql.bound.take", 1, "{\"maximum\":2,\"op\":\"clamp\"}"),
    )
    is Err(InvalidDerivation),
  )
}

///|
test "partitioned selection and unresolved Parameter counts cannot supply global literal bounds" {
  let claim = proof("actql.bound.top-k", 7, "{\"maximum\":7,\"op\":\"clamp\"}")
  let partitioned = pipeline(
    "[{\"top_k_by\":{\"partition_by\":[\"id\"],\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]",
  )
  assert_true(
    @capacity_program_step.check(partitioned, 0, claim)
    is Err(UnsupportedOperation),
  )
  let d = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"default\":7}}")),
    { max_parameters: 1, max_nodes: 30, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let p = pipeline("[{\"take\":{\"$param\":\"n\"}}]", parameters=Some(d))
  assert_true(
    @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
    )
    is Err(UnresolvedCount),
  )
}
