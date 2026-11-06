///|
test "Salesforce phased recovery keeps full failed peak and only closed metadata after success" {
  let describe : @catalog.DescribeLimits = {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 32,
    max_fields: 1000,
    max_name_units: 200000,
  }
  let limits : @catalog.DeclarationLimits = {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 64,
  }
  // Exact nonsecret original extents. Two identity/load text reads alone
  // retain 13 text units and one wire byte per original publication byte.
  let prefix = 2L * (337472L + 337865L) * (13L * 8L + 1L)
  let observation = sf_initialization_construction_capacity(
    [251217],
    [28020],
    334956,
    984,
    [7],
    984,
    10,
    14,
    describe,
    8000000,
    limits,
    phase=Observation,
  ).unwrap()
  let declaration = initialization_declaration_construction_capacity(
    [71, 2500],
    984,
    [7],
    984,
    10,
    14,
    describe,
    8000000,
    limits,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(observation)
  let retained = @execution.execution_capacity_retained_bytes(observation)
  let declared = @execution.execution_capacity_execution_bytes(declaration)
  assert_true(retained < peak)
  assert_eq(@execution.execution_capacity_retained_bytes(declaration), declared)
  println(
    "SF phased peak=\{peak} retained=\{retained} declaration=\{declared} prefix=\{prefix}",
  )
  // Provider + Common Source recovery, then Effect provider recovery. The
  // unchanged closed-constructor caller chooses retained DATA only after
  // actual synchronous return/current checks; failure still owns this peak.
  assert_true(prefix + 2L * (retained + declared) + peak < 536870912L)
  let whole = sf_initialization_construction_capacity(
    [251217],
    [28020],
    334956,
    984,
    [7],
    984,
    10,
    14,
    describe,
    8000000,
    limits,
  ).unwrap()
  assert_true(
    prefix / 2L + @execution.execution_capacity_execution_bytes(whole) >
    536870912L,
  )
}

///|
test "Salesforce declaration dimensions keep full raw forest before tight writer refusal" {
  let describe : @catalog.DescribeLimits = {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 32,
    max_fields: 1000,
    max_name_units: 200000,
  }
  let tiny : @catalog.DeclarationLimits = {
    max_bytes: 1,
    max_nodes: 1,
    max_depth: 1,
  }
  let one = initialization_declaration_construction_capacity(
    [1, 2],
    984,
    [7],
    984,
    10,
    14,
    describe,
    8000000,
    tiny,
  ).unwrap()
  let many = initialization_declaration_construction_capacity(
    [71, 2500],
    984,
    [7],
    984,
    10,
    14,
    describe,
    8000000,
    tiny,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(many) >
    @execution.execution_capacity_execution_bytes(one),
  )
  for dimensions in [[1], [1001, 2], [-1, 2], [1, -1], [1, 4000001]] {
    assert_true(
      initialization_declaration_construction_capacity(
        dimensions,
        984,
        [7],
        984,
        10,
        14,
        describe,
        8000000,
        tiny,
      )
      is None,
    )
  }
}
