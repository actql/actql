///|
fn identity_limits() -> ProgramIdentityLimits {
  {
    max_work: 10000000,
    max_stages: 2,
    max_hash_bytes: 100000,
    max_hash_nodes: 10000,
    max_depth: 100,
  }
}

///|
test "Program source identities use the retained Program and bound values" {
  let (operations, references, bindings) = program_sources_fixture()
  let sources = bind_program_sources(operations, references, bindings, 10000000).unwrap()
  let v = identify_program_sources(sources, identity_limits()).unwrap()
  // Fixed preimages: {version:"actql-parameter-values/0.1",values:{n:1,p:"é😀"}}
  // and the same envelope with p:"abc". Expected SHA-256 comes from the
  // independent Node canonical encoder, not this assembly's product output.
  assert_eq(
    program_identity_parameter_values_cid(v),
    "sha256:1a45020e7c1f85fcf07fd628eab887e48a4e830123d7f992eae6588254934875",
  )
  assert_true(physical_equal(program_identity_sources(v), sources))
  let definition = program_identity_definition(v)
  assert_eq(program_identity_stage_count(v), 2)
  for invalid in [-2147483648, -1, 2, 2147483647] {
    assert_true(program_identity_stage_at(v, invalid) is None)
  }
  let semantics = @program_refs.program_definition_semantics(definition)
  let usage = @program_refs.parameter_usage(
    program_reference_values(references),
  )
  assert_true(
    physical_equal(@program_refs.program_semantics_usage(semantics), usage),
  )
  assert_eq(
    program_identity_definition_cid(v),
    @program_refs.program_definition_cid(definition, 10000, 1000, 100),
  )
  let (work, bytes, nodes) = program_identity_usage(v)
  assert_eq(
    work,
    program_sources_work(sources) +
    @program_refs.program_semantics_work(semantics) -
    @program_refs.usage_work(usage) +
    1 +
    program_identity_stage_count(v),
  )
  let limits = {
    ..identity_limits(),
    max_work: work,
    max_hash_bytes: bytes,
    max_hash_nodes: nodes,
  }
  assert_true(identify_program_sources(sources, limits) is Ok(_))
  assert_true(
    identify_program_sources(sources, { ..limits, max_work: work - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    identify_program_sources(sources, { ..limits, max_hash_bytes: bytes - 1, })
    is Err(Hash(ParameterValues, _)),
  )
  assert_true(
    identify_program_sources(sources, { ..limits, max_hash_nodes: nodes - 1, })
    is Err(Hash(ParameterValues, _)),
  )
  assert_true(
    identify_program_sources(sources, { ..limits, max_stages: 1, })
    is Err(SourceSemantics(@program_refs.BudgetExceeded)),
  )
  assert_true(
    identify_program_sources(sources, { ..limits, max_depth: 0, })
    is Err(SourceSemantics(@program_refs.StageHash(0, @encode.OutputLimit))),
  )
  assert_true(
    identify_program_sources(sources, {
      ..limits,
      max_work: program_sources_work(sources),
    })
    is Err(BudgetExceeded),
  )
  for
    invalid in [
      { ..limits, max_work: -1, },
      { ..limits, max_stages: -1, },
      { ..limits, max_hash_bytes: -1, },
      { ..limits, max_hash_nodes: -1, },
      { ..limits, max_depth: -1, },
    ] {
    assert_true(
      identify_program_sources(sources, invalid) is Err(InvalidLimits),
    )
  }
  let (stage_bytes, _) = @program_refs.program_semantics_hash_usage(semantics)
  let (root_bytes, _) = @program_refs.program_definition_hash_usage(definition)
  assert_true(
    identify_program_sources(sources, { ..limits, max_hash_bytes: stage_bytes, })
    is Err(Hash(ProgramSemantics, _)),
  )
  assert_true(
    identify_program_sources(sources, {
      ..limits,
      max_hash_bytes: stage_bytes + root_bytes,
    })
    is Err(Hash(Definition, _)),
  )
  let root_writer = @encode.hashing_writer(10000, 1000, 100)
  @program_refs.emit_program_definition(definition, root_writer)
  let (_, root_output_bytes, _) = @encode.finish_hash_usage(root_writer)
  let mut used_bytes = stage_bytes + root_bytes + root_output_bytes
  for i in 0..<program_identity_stage_count(v) {
    let stage = program_identity_stage_at(v, i).unwrap()
    let local_definition = stage_identity_definition(stage)
    assert_eq(
      @program_refs.stage_definition_hash_usage(local_definition),
      (0, 0),
    )
    assert_true(
      physical_equal(
        @program_refs.stage_semantics_usage(
          @program_refs.stage_definition_semantics(local_definition),
        ),
        usage,
      ),
    )
    assert_true(
      physical_equal(
        stage_identity_parameter_values(stage),
        @program_refs.stage_parameter_values(
          program_reference_values(references),
          i,
        ).unwrap(),
      ),
    )
    assert_eq(
      stage_identity_parameter_values_cid(stage),
      program_identity_parameter_values_cid(v),
    )
    assert_eq(
      stage_identity_definition_cid(stage),
      @program_refs.stage_definition_cid(local_definition, 10000, 1000, 100),
    )
    assert_true(
      identify_program_sources(sources, {
        ..limits,
        max_hash_bytes: used_bytes,
      })
      is Err(Hash(StageDefinition(index), _)) &&
      index == i,
    )
    let stage_writer = @encode.hashing_writer(10000, 1000, 100)
    @program_refs.emit_stage_definition(local_definition, stage_writer)
    let (_, local_bytes, _) = @encode.finish_hash_usage(stage_writer)
    used_bytes += local_bytes
    assert_true(
      identify_program_sources(sources, {
        ..limits,
        max_hash_bytes: used_bytes,
      })
      is Err(Hash(StageParameterValues(index), _)) &&
      index == i,
    )
    let values_writer = @encode.hashing_writer(10000, 1000, 100)
    @references.emit_used_values(
      stage_identity_parameter_values(stage),
      values_writer,
    )
    let (_, value_bytes, _) = @encode.finish_hash_usage(values_writer)
    used_bytes += value_bytes
  }
  let (other_ops, other_refs, other_bindings) = program_sources_fixture(
    supplied=Some(cursor("{\"p\":\"abc\",\"n\":1}")),
  )
  let other_sources = bind_program_sources(
    other_ops, other_refs, other_bindings, 10000000,
  ).unwrap()
  let other = identify_program_sources(other_sources, identity_limits()).unwrap()
  assert_eq(
    program_identity_parameter_values_cid(other),
    "sha256:805409a8322f1f14a16edc67471a0c2fe798411e61a84f734a5c8417472a9c62",
  )
  assert_false(physical_equal(program_identity_sources(other), sources))
  assert_eq(
    program_identity_definition_cid(other),
    program_identity_definition_cid(v),
  )
  assert_true(
    program_identity_parameter_values_cid(other) !=
    program_identity_parameter_values_cid(v),
  )
}

///|
test "stage identities retain local used values without sibling parameter dependencies" {
  let (operations, references, bindings) = program_sources_fixture(
    steps=Some("[{\"derive\":{\"p_copy\":\"$p\"}}]"),
    second_steps=Some("[{\"derive\":{\"n_copy\":\"$n\"}}]"),
  )
  let sources = bind_program_sources(operations, references, bindings, 10000000).unwrap()
  let v = identify_program_sources(sources, identity_limits()).unwrap()
  let a = program_identity_stage_at(v, 0).unwrap()
  let b = program_identity_stage_at(v, 1).unwrap()
  // Independent canonical UTF-8/SHA-256 expectations for {values:{p:...}}
  // and {values:{n:1}}, with version actql-parameter-values/0.1.
  assert_eq(
    stage_identity_parameter_values_cid(a),
    "sha256:f30e703574e88d1b41253227c7aea846fa3d751c653c08d7bbd228d029015889",
  )
  assert_eq(
    stage_identity_parameter_values_cid(b),
    "sha256:1263254b6fb0c45a9562bd42a4e24a4704d43c52cfaaa27ea9887a95e44919e1",
  )
  assert_eq(@references.used_value_count(stage_identity_parameter_values(a)), 1)
  assert_eq(@references.used_value_count(stage_identity_parameter_values(b)), 1)
  let (ops2, refs2, bindings2) = program_sources_fixture(
    steps=Some("[{\"derive\":{\"p_copy\":\"$p\"}}]"),
    second_steps=Some("[{\"derive\":{\"n_copy\":\"$n\"}}]"),
    supplied=Some(cursor("{\"p\":\"abc\",\"n\":1}")),
  )
  let other = identify_program_sources(
    bind_program_sources(ops2, refs2, bindings2, 10000000).unwrap(),
    identity_limits(),
  ).unwrap()
  let other_a = program_identity_stage_at(other, 0).unwrap()
  let other_b = program_identity_stage_at(other, 1).unwrap()
  assert_eq(
    stage_identity_parameter_values_cid(other_a),
    "sha256:9f0cd5274cf564d1a1569af59814570fad90a6fc9d73835a5b367ca4d0c92c59",
  )
  assert_eq(
    stage_identity_parameter_values_cid(other_b),
    stage_identity_parameter_values_cid(b),
  )
  assert_eq(
    stage_identity_definition_cid(other_a),
    stage_identity_definition_cid(a),
  )
  assert_eq(
    stage_identity_definition_cid(other_b),
    stage_identity_definition_cid(b),
  )
  assert_false(
    physical_equal(
      stage_identity_parameter_values(other_b),
      stage_identity_parameter_values(b),
    ),
  )
  let (empty_ops, empty_refs, empty_bindings) = program_sources_fixture(
    second_steps=Some("[]"),
  )
  let empty = identify_program_sources(
    bind_program_sources(empty_ops, empty_refs, empty_bindings, 10000000).unwrap(),
    identity_limits(),
  ).unwrap()
  let empty_stage = program_identity_stage_at(empty, 1).unwrap()
  assert_eq(
    @references.used_value_count(stage_identity_parameter_values(empty_stage)),
    0,
  )
  assert_eq(
    stage_identity_parameter_values_cid(empty_stage),
    "sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52",
  )
}
