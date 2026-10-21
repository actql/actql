///|
test "public parsed Catalog reuse retains current Parameter values and checked identities" {
  let (_, program, environment, _, limits) = public_input_fixture()
  let catalog = @program_check.prepare_source_catalog(environment, {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  let values : Array[String] = []
  for number in [2, 3] {
    let supplied = @decode.admit(
      @source.parse_json("{\"n\":\{number}}", {
        max_input_bytes: 7,
        max_nodes: 2,
        max_depth: 1,
      }).unwrap(),
      {
        max_nodes: 2,
        max_depth: 1,
        max_string_bytes: 1,
        max_total_string_bytes: 1,
      },
    ).unwrap()
    let old = public_checked(
      @program_check.check_parsed(program, environment, Some(supplied), limits),
    )
    let reused = public_checked(
      @program_check.check_parsed(
        program,
        environment,
        Some(supplied),
        limits,
        source_catalog=Some(catalog),
      ),
    )
    assert_eq(@program_check.unit_count(reused), @program_check.unit_count(old))
    for unit in 0..<@program_check.unit_count(old) {
      assert_eq(
        @program_check.unit_definition_cid(reused, unit),
        @program_check.unit_definition_cid(old, unit),
      )
      assert_eq(
        @program_check.unit_used_values_cid(reused, unit),
        @program_check.unit_used_values_cid(old, unit),
      )
    }
    values.push(@program_check.unit_used_values_cid(reused, 0).unwrap())
  }
  assert_true(values[0] != values[1])
}

///|
test "public Catalog reuse refuses a foreign configured owner and retains current input bounds" {
  let (text, program, environment, _, limits) = public_input_fixture()
  let catalog = @program_check.prepare_source_catalog(environment, {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  let profile = @program_check.checking_environment_profile_selection(
    environment,
  )
  let foreign = @program_check.checking_environment(
    @program_check.checking_environment_wire(environment),
    profile.expressions,
    profile.operations,
  )
  try
    public_checked(
      @program_check.check_parsed(
        program,
        foreign,
        None,
        limits,
        source_catalog=Some(catalog),
      ),
    )
  catch {
    @program_check.LocalConstructionFailure::Environment(ForeignPreparedCatalog) =>
      ()
    other => raise other
  } noraise {
    _ => fail("foreign configured Catalog owner was accepted")
  }
  let short = {
    ..limits,
    input: {
      ..limits.input,
      source: { ..limits.input.source, max_input_bytes: text.length() - 1, },
    },
  }
  try
    public_checked(
      @program_check.check_parsed(
        program,
        environment,
        None,
        short,
        source_catalog=Some(catalog),
      ),
    )
  catch {
    @program_check.LocalConstructionFailure::Program(
      RetentionLimit(InputBytes, source_path="fixture.actql")
    ) => ()
    other => raise other
  } noraise {
    _ => fail("retained Catalog bypassed the current Program byte bound")
  }
}
