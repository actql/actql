///|
test "metadata compiler facts remain independent of authored row count" {
  let one = closed_values_compilation_metadata_layout(1, 8).unwrap()
  let hundred = closed_values_compilation_metadata_layout(100, 8).unwrap()
  assert_eq(one.max_facts, 2)
  assert_eq(one.max_witnesses, 3)
  assert_true(hundred.max_nodes > one.max_nodes)
  assert_true(
    preparation_representation_cost(hundred.retained).unwrap() >
    preparation_representation_cost(one.retained).unwrap(),
  )
  assert_eq(one.plan_extra.node_upper, hundred.plan_extra.node_upper)
  assert_eq(one.plan_extra.input_bytes, hundred.plan_extra.input_bytes)
  assert_true(closed_values_compilation_metadata_layout(0, 8) is None)
  assert_true(closed_values_compilation_metadata_layout(1, -1) is None)
  assert_true(closed_values_compilation_metadata_layout(2147483647, 8) is None)
  assert_true(closed_values_compilation_metadata_layout(1, 2147483647) is None)
}

///|
test "metadata lexical families match source structural inventories" {
  let binding = compilation_metadata_facts(2, 2, 10).unwrap()
  assert_eq(binding.node_upper, 12)
  assert_eq(binding.quoted_utf16_units, 507)
  let row = compilation_metadata_facts(6, 2, 10).unwrap()
  assert_eq(row.node_upper, 11)
  assert_eq(row.quoted_utf16_units, 101)
  let result = compilation_metadata_facts(7, 2, 10).unwrap()
  assert_eq(result.node_upper, 23)
  assert_eq(result.quoted_utf16_units, 688)
  let root = compilation_metadata_facts(8, 2, 10).unwrap()
  assert_eq(root.node_upper, 6)
  assert_eq(root.quoted_utf16_units, 68)
  for kind in 0..<16 {
    let facts = compilation_metadata_facts(kind, 2, 10).unwrap()
    assert_true(facts.fields_upper < facts.node_upper)
    assert_true(facts.quoted_tokens >= facts.fields_upper)
    assert_true(facts.input_bytes > facts.quoted_utf16_units)
    assert_true(
      compilation_parse_layout(facts, Int::min(14, facts.fields_upper))
      is Some(_),
    )
  }
}

///|
fn metadata_assert_wire(
  wire : String,
  facts : ClosedValuesLexicalFacts,
) -> Unit raise {
  let source = @source.parse_json(wire, {
    max_input_bytes: facts.input_bytes,
    max_nodes: facts.node_upper,
    max_depth: facts.depth_upper,
  }).unwrap()
  let value = @identity.from_source(
    source,
    facts.node_upper,
    facts.depth_upper,
    facts.input_bytes,
    data_keys=true,
  )
  let actual = @identity.representation_extent(
    value,
    facts.node_upper,
    facts.depth_upper,
    facts.input_bytes,
  ).unwrap()
  assert_true(actual.nodes <= facts.node_upper.to_int64())
  assert_true(actual.objects <= facts.objects.to_int64())
  assert_true(actual.arrays <= facts.arrays.to_int64())
  assert_true(wire.length() <= facts.input_bytes)
}

///|
test "metadata sealed owners satisfy real constructor bounds and reject one-short nodes" {
  let cid = "sha256:" + Array::make(64, "0").join("")
  let invocation = "{\"version\":\"actql-invocation-bindings/0.1\",\"bindings\":{}}"
  let i = compilation_metadata_facts(9, 1, 1).unwrap()
  let actual = @publication.seal_run_evidence_value(
    "invocation_bindings",
    invocation,
    i.input_bytes,
    i.node_upper,
    i.depth_upper,
  ).unwrap()
  metadata_assert_wire(@publication.run_evidence_value_json(actual), i)
  assert_true(
    @publication.seal_run_evidence_value(
      "invocation_bindings",
      invocation,
      i.input_bytes,
      i.node_upper - 1,
      i.depth_upper,
    )
    is Err(_),
  )
  let template = "{\"version\":\"actql-bound-invocation-template/0.1\",\"program_definition_cid\":\"" +
    cid +
    "\",\"parameter_values_cid\":\"" +
    cid +
    "\",\"invocation_bindings_cid\":\"" +
    cid +
    "\",\"check_environment_cid\":\"" +
    cid +
    "\",\"grammar_manifest_cid\":\"" +
    cid +
    "\",\"required_profile_contracts\":[],\"barrier_contract_manifest_cid\":\"" +
    cid +
    "\",\"source_evidence\":\"unbound\"}"
  let t = compilation_metadata_facts(10, 1, 1).unwrap()
  let actual = @publication.seal_run_evidence_value(
    "bound_invocation_template",
    template,
    t.input_bytes,
    t.node_upper,
    t.depth_upper,
  ).unwrap()
  metadata_assert_wire(@publication.run_evidence_value_json(actual), t)
  assert_true(
    @publication.seal_run_evidence_value(
      "bound_invocation_template",
      template,
      t.input_bytes,
      t.node_upper - 1,
      t.depth_upper,
    )
    is Err(_),
  )
  let compiled = "{\"version\":\"actql-compiled-plan/0.1\",\"compiler_version\":\"actql-moonbit-0.0.1\",\"aoa_ir_version\":\"aoa-pipeline:0.1\",\"executable_plan_cid\":\"" +
    cid +
    "\",\"program_definition_cid\":\"" +
    cid +
    "\",\"program_semantics_cid\":\"" +
    cid +
    "\",\"aoa_contract_cid\":\"" +
    cid +
    "\",\"aoa_logical_cid\":\"" +
    cid +
    "\"}"
  let c = compilation_metadata_facts(11, 1, 1).unwrap()
  let actual = @publication.seal_publication_contract(
    "compiled_plan",
    compiled,
    c.input_bytes,
    c.node_upper,
    c.depth_upper,
  ).unwrap()
  metadata_assert_wire(@publication.publication_contract_json(actual), c)
  assert_true(
    @publication.seal_publication_contract(
      "compiled_plan",
      compiled,
      c.input_bytes,
      c.node_upper - 1,
      c.depth_upper,
    )
    is Err(_),
  )
  assert_true(
    @publication.seal_run_evidence_value(
      "invocation_bindings",
      "{}",
      i.input_bytes,
      i.node_upper,
      i.depth_upper,
    )
    is Err(_),
  )
}

///|
test "shared checked contract serializer packet follows actual scope multiplicity" {
  let one = compilation_number_contract_emitter_layout().unwrap()
  let two = compilation_metadata_repeat_units(one, 2L).unwrap()
  assert_eq(
    preparation_representation_cost(two).unwrap(),
    2L * preparation_representation_cost(one).unwrap(),
  )
  assert_true(compilation_metadata_repeat_units(one, -1L) is None)
  assert_true(
    compilation_metadata_repeat_units(one, 9223372036854775807L) is None,
  )
}

///|
test "small metadata serializer scopes use shared depth and witness dependencies" {
  let shallow = compilation_canonical_emitter_layout(2).unwrap()
  let deep = compilation_canonical_emitter_layout(8).unwrap()
  assert_true(
    preparation_representation_cost(deep).unwrap() >
    preparation_representation_cost(shallow).unwrap(),
  )
  let witness = compilation_small_witness_emitter_layout().unwrap()
  assert_true(preparation_representation_cost(witness).unwrap() > 0L)
  let quote = closed_values_compilation_metadata_layout(100, 8).unwrap()
  assert_true(
    preparation_representation_cost(quote.temporary).unwrap() >
    preparation_representation_cost(witness).unwrap(),
  )
}
