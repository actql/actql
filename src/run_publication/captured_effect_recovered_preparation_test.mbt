///|
test "recovered captured Effect inventory retains complete typed DATA and binds the exact contract" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let spent = Ref(0)
  let prepared = prepare_recovered_captured_effect_run(
    captured,
    65536,
    4096,
    32,
    units => {
      spent.val += units
      true
    },
  ).unwrap()
  assert_true(
    physical_equal(prepared_captured_effect_run_contract(prepared), captured),
  )
  assert_eq(
    captured_effect_dependency_inventory_json(
      prepared_captured_effect_run_inventory(prepared),
    ),
    "[]",
  )
  assert_eq(prepared_captured_effect_run_schemas(prepared), [])
  assert_eq(prepared_captured_effect_run_payloads(prepared), [])
  let preview = final_test_preview(chain)
  assert_true(
    validate_prepared_effectful_computation_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      prepared,
      preview,
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  let foreign = final_test_captured(chain)
  assert_eq(
    publication_contract_json(foreign),
    publication_contract_json(captured),
  )
  assert_true(
    validate_prepared_effectful_computation_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      foreign,
      prepared,
      preview,
      65536,
      4096,
      32,
    )
    is Err(EvidenceInventoryMismatch(_)),
  )
  assert_true(
    prepare_recovered_captured_effect_run(chain.receipt, 65536, 4096, 32, _ => {
      true
    })
    is Err(InvalidBody),
  )
  assert_true(
    prepare_recovered_captured_effect_run(captured, 65536, 4096, 32, _ => false)
    is Err(ReferenceLimit),
  )
}

///|
test "prepared dependency inventory retains exact nonempty root DATA without caller array aliases" {
  // Independent canonical empty acquisition-scope vector.
  let cid = "sha256:58aca71c9645edf63bfebadb8d0717cccebbc1a7092ad6f12ee9192304401bc3"
  let wire = "{\"self_cid\":\"" +
    cid +
    "\",\"sources\":[],\"version\":\"actql-acquisition-scope/0.1\"}"
  let body = admit_publication_effect_dependency_body(
    "acquisition_scope", wire, 8192, 1000, 32,
  ).unwrap()
  let roots = [body]
  let prepared = prepare_captured_effect_dependency_inventory(
    [body],
    roots,
    1000,
    32,
    _ => true,
  ).unwrap()
  let legacy = issue_captured_effect_dependency_inventory(
    [body],
    roots,
    {
      max_entries: 1,
      max_total_bytes: 8192,
      max_depth: 64,
      max_references: 65536,
    },
    1000,
    32,
  ).unwrap()
  roots.clear()
  let funded = issue_prepared_captured_effect_dependency_inventory(prepared, _ => {
    true
  }).unwrap()
  for inventory in [legacy, funded] {
    assert_true(
      captured_effect_dependency_inventory_matches_roots(inventory, [body]),
    )
    assert_false(
      captured_effect_dependency_inventory_matches_roots(inventory, []),
    )
    assert_false(
      captured_effect_dependency_inventory_matches_roots(
        inventory,
        [body],
        work=Some(_ => false),
      ),
    )
  }
}
