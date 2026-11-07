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
  assert_true(
    @execution.execution_capacity_retained_bytes(declaration) < declared,
  )
  // Frozen435d working peaks, independently adjusted for the decoder's
  // active-ancestor Map lifetime. Old28020 potential object owners become
  // at most32 live object frames. Each retired KeyAdmission/Map owner is
  //8H19R21W (entries/growth remain charged):448 bytes at the common tariff.
  let retired_map_owners = 28020L - 32L
  let retired_map_bytes = 16L * (8L * retired_map_owners) +
    8L * (19L * retired_map_owners) +
    8L * (21L * retired_map_owners)
  assert_eq(retired_map_bytes, 12538624L)
  assert_eq(peak, 212287177L - retired_map_bytes)
  // Declaration skips Describe parsing but still decodes StaticDeclaration
  // JSON:16 envelope nodes +32 for one resource +20 per71 fields. Its
  //1468 possible object owners become64 active frames; all entries stay.
  let export_map_owners = 16L + 32L + 20L * 71L - 64L
  let export_map_bytes = 16L * (8L * export_map_owners) +
    8L * (19L * export_map_owners) +
    8L * (21L * export_map_owners)
  assert_eq(export_map_bytes, 628992L)
  assert_eq(declared, 38337530L - export_map_bytes)
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
  let whole_bytes = @execution.execution_capacity_execution_bytes(whole)
  // Whole uses the Describe-derived1000-field bound, so its export parse
  // has16+32+20*1000=20048 nodes at depth64. The two original decoder
  // Map-owner reductions now let this conservative whole quote fit512MiB;
  // its old excess is no longer a required refusal. Phase/current/failed-child
  // duties remain unchanged, and this logical quote proves no physical ACK.
  let whole_export_owners = 16L + 32L + 20L * 1000L - 64L
  let whole_export_delta = (16L * 8L + 8L * 19L + 8L * 21L) *
    whole_export_owners
  assert_true(prefix / 2L + whole_bytes <= 536870912L)
  assert_true(
    prefix / 2L + whole_bytes + retired_map_bytes + whole_export_delta >
    536870912L,
  )
}

///|
test "Salesforce phased retained metadata covers dense reference arrays and primitive strings" {
  // Up to 1000 fields can retain a much larger total ReferenceTo inventory.
  // Count each primitive String and all three reference-array copy roles;
  // neither one slot per field nor retained UTF16 contents alone covers them.
  let nodes = 300000L
  let retained = sf_initialization_metadata_retained(1000L, nodes, 2000000L).unwrap()
  assert_true(retained.record_headers >= nodes)
  assert_true(retained.reference_slots >= 3L * nodes)
  assert_true(retained.scalar_words >= nodes)
  assert_eq(retained.owned_utf16_units, 2000000L)
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
