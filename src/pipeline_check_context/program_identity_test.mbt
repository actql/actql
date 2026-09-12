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
    1,
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
    is Err(SourceSemantics(@program_refs.BudgetExceeded)),
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
