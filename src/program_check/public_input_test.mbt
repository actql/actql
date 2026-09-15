///|
test "document and parsed public entries retain the same decisions and evidence roles" {
  for (generated, repeated) in [(false, false), (true, false), (true, true)] {
    let a = public_program_fixture(generated~, repeated~)
    let b = public_program_fixture(generated~, repeated~, document=true)
    assert_eq(@program_check.unit_count(a), 2)
    assert_eq(@program_check.unit_count(b), 2)
    for unit in 0..<2 {
      assert_eq(
        @program_check.unit_definition_cid(a, unit),
        @program_check.unit_definition_cid(b, unit),
      )
      let x = @program_check.unit_publication_at(a, unit, 0).unwrap()
      let y = @program_check.unit_publication_at(b, unit, 0).unwrap()
      assert_eq(
        @wire.limit_cid(@program_check.publication_rows(x)),
        @wire.limit_cid(@program_check.publication_rows(y)),
      )
      assert_eq(
        @program_check.publication_proof_count(x),
        @program_check.publication_proof_count(y),
      )
      for index in 0..<@program_check.publication_proof_count(x) {
        let left = @program_check.publication_proof_at(x, index).unwrap()
        let right = @program_check.publication_proof_at(y, index).unwrap()
        assert_eq(
          @wire.cid(
            @wire.program_proof_witness(@program_check.proof_claim(left)),
          ),
          @wire.cid(
            @wire.program_proof_witness(@program_check.proof_claim(right)),
          ),
        )
        assert_eq(
          @program_check.proof_input_count(left),
          @program_check.proof_input_count(right),
        )
      }
    }
  }
}

///|
test "ordinary entries require no evidence inventory and reuse current Parameter values" {
  let (text, parsed, environment, _, limits) = public_input_fixture()
  let node = @source.parse_json("{\"n\":2}", {
    max_input_bytes: 7,
    max_nodes: 2,
    max_depth: 1,
  }).unwrap()
  let supplied = @decode.admit(node, {
    max_nodes: 2,
    max_depth: 1,
    max_string_bytes: 1,
    max_total_string_bytes: 1,
  }).unwrap()
  let a = public_checked(
    @program_check.check_document(
      text,
      environment,
      Some(supplied),
      limits,
      format=Json,
      source_path="fixture.actql",
    ),
  )
  let b = public_checked(
    @program_check.check_parsed(parsed, environment, Some(supplied), limits),
  )
  for value in [a, b] {
    let stage = @context.program_identity_stage_at(
      @program_check.source_identity(value),
      0,
    ).unwrap()
    let used = @context.stage_identity_parameter_values(stage)
    assert_eq(@parameter_refs.used_value_count(used), 1)
    assert_true(
      @parameter_refs.used_value_at(used, 0).unwrap().value.value is Number(2.0),
    )
  }
  assert_eq(
    @program_check.unit_definition_cid(a, 0),
    @program_check.unit_definition_cid(b, 0),
  )
}

///|
test "parsed entry enforces retained raw document bytes including trailing whitespace" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let document = text + " \r\n"
  let exact = {
    ..limits,
    input: {
      ..limits.input,
      source: { ..limits.input.source, max_input_bytes: text.length() + 3, },
    },
  }
  let parsed = @syntax.parse(
    document,
    exact.input,
    format=Json,
    source_path="retained.actql",
  ).unwrap()
  ignore(
    public_checked(
      @program_check.check_parsed(parsed, environment, None, exact),
    ),
  )
  let smaller = {
    ..exact,
    input: {
      ..exact.input,
      source: { ..exact.input.source, max_input_bytes: text.length() + 2, },
    },
  }
  try
    public_checked(
      @program_check.check_parsed(parsed, environment, None, smaller),
    )
  catch {
    @program_check.LocalConstructionFailure::Program(
      RetentionLimit(InputBytes, source_path="retained.actql")
    ) => ()
    e => raise e
  } noraise {
    _ => fail("reuse bypassed the current document byte limit")
  }
  try
    public_checked(
      @program_check.check_document(
        document,
        environment,
        None,
        smaller,
        format=Json,
        source_path="retained.actql",
      ),
    )
  catch {
    @program_check.LocalConstructionFailure::Program(Parse(issue)) => {
      assert_eq(issue.issue, InputLimit)
      assert_eq(issue.source_path, "retained.actql")
    }
    e => raise e
  } noraise {
    _ => fail("document admission bypassed its byte limit")
  }
}

///|
test "input errors retain syntax locations and later checking cannot return partial success" {
  let (text, _, environment, _, limits) = public_input_fixture()
  try
    public_checked(
      @program_check.check_document(
        "{",
        environment,
        None,
        limits,
        format=Json,
        source_path="broken.actql",
      ),
    )
  catch {
    @program_check.LocalConstructionFailure::Program(Parse(issue)) =>
      assert_eq(issue.source_path, "broken.actql")
    e => raise e
  } noraise {
    _ => fail("invalid syntax returned a CheckedProgram")
  }
  let invalid = text.replace(
    old="{\"take\":1,\"as\":\"selected\"}",
    new="{\"derive\":{\"bad\":\"missing_column + 1\"},\"as\":\"selected\"}",
  )
  try
    public_checked(
      @program_check.check_document(
        invalid,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
  catch {
    @program_check.LocalConstructionFailure::Source(_) => ()
    e => raise e
  } noraise {
    _ => fail("failed consumer returned a partial CheckedProgram")
  }
}
