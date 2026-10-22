///|
priv struct CommitCursorFixture {
  binding_inputs : DurableBindingInputs
  reference_inputs : PublicationReferenceInputs
}

///|
fn commit_cursor_fixture(
  names : Array[String],
  namespace_id? : String = "local",
) -> CommitCursorFixture {
  let retention = inventory_fixture(0).retention
  let cid = inventory_fixture_cid
  let run = seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"scope\",\"run_id\":\"run\"," +
    "\"compiled_plan_cid\":\"" +
    cid("1") +
    "\",\"invocation_template_cid\":\"" +
    cid("d") +
    "\",\"authorization_context_cid\":\"" +
    cid("2") +
    "\",\"input_artifact_set_cid\":\"" +
    cid("3") +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\",\"valid_until\":\"2026-09-18T04:00:00.000Z\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let invocation = seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    cid("d") +
    "\",\"observation_set_cid\":\"" +
    cid("4") +
    "\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let definitions : Array[PublicationContract] = []
  let artifacts : Array[PublicationContract] = []
  let orderings : Array[PublicationContract] = []
  let bindings : Array[PublicationContract] = []
  let schema_cid = "sha256:4b94cf57d7e0fa174c9edbdc43b22f3ca573038098f1b29ed64f39b149edc8a1"
  for name in names {
    let definition = result_definition_contract(
      prepare_result_definition(cid("8"), name).unwrap(),
    )
    let evidence = issue_result_occurrence_evidence(
      definition,
      cid("9"),
      schema_cid,
      cid("a"),
      [],
      cid("b"),
      cid("e"),
      "common-host",
      cid("c"),
      65536,
      4096,
      32,
    ).unwrap()
    let artifact = issue_complete_result_artifact(
      definition, invocation, evidence, retention, 1, 65536, 4096, 32,
    ).unwrap()
    let binding = issue_durable_result_binding(
      run,
      definition,
      invocation,
      artifact,
      evidence.ordering,
      retention,
      cid("1"),
      ["answer"],
      "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}",
      cid("2"),
      cid("3"),
      1,
      97,
      "4".repeat(64),
      65536,
      4096,
      32,
    ).unwrap()
    definitions.push(definition)
    artifacts.push(artifact)
    orderings.push(evidence.ordering)
    bindings.push(binding)
  }
  let manifest = issue_result_manifest(
    run, invocation, definitions, artifacts, 65536, 4096, 32,
  ).unwrap()
  let request = issue_publication_request(
    run,
    definitions,
    namespace_id,
    cid("3"),
    cid("4"),
    cid("5"),
    "2026-09-18T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let attempt = issue_publication_attempt(
    request,
    run,
    "attempt",
    cid("6"),
    None,
    "2026-09-18T00:00:01.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  // This private fixture isolates reference traversal. Already admitted roots
  // supply distinct CID tokens; it is not a complete Run evidence chain.
  // The standard Host regression uses real Receipt/Captured Run owners.
  let receipt = retention
  let captured_run = orderings[0]
  let index_entry = seal_publication_contract(
    "public_index_entry",
    "{\"version\":\"actql-public-index-entry/0.1\",\"namespace_id\":\"" +
    namespace_id +
    "\",\"authority_scope_cid\":\"" +
    cid("3") +
    "\",\"run_definition_cid\":\"" +
    run.identity +
    "\",\"invocation_cid\":\"" +
    invocation.identity +
    "\",\"result_manifest_cid\":\"" +
    manifest.identity +
    "\",\"run_receipt_cid\":\"" +
    receipt.identity +
    "\",\"captured_run_cid\":\"" +
    captured_run.identity +
    "\",\"durable_result_binding_cids\":[" +
    bindings.map(value => "\"" + value.identity + "\"").join(",") +
    "],\"publication_request_cid\":\"" +
    request.identity +
    "\",\"publication_attempt_cid\":\"" +
    attempt.identity +
    "\",\"committed_at\":\"2026-09-18T00:00:02.000Z\"}",
    65536,
    4096,
    32,
  ).unwrap()
  {
    binding_inputs: {
      run_definition: run,
      invocation,
      definitions,
      artifacts,
      orderings,
      retentions: [retention],
      bindings,
      index_entry,
    },
    reference_inputs: {
      run_definition: run,
      invocation,
      definitions,
      manifest,
      receipt,
      captured_run,
      request,
      attempt,
      index_entry,
    },
  }
}

///|
fn commit_cursor_reseal(
  contract : PublicationContract,
  field : String,
  value : String,
) -> PublicationContract {
  let body = @json.object_without_field(contract.value, contract.identity_field).unwrap()
  let body = @json.object_without_field(body, field).unwrap()
  let body = @json.object_with_string_field(body, field, value).unwrap()
  let wire = canonical_value_wire(body, 65536, 4096, 32).unwrap()
  seal_publication_contract(contract.name, wire, 65536, 4096, 32).unwrap()
}

///|
/// A corruption probe below admission, not a valid public index fixture.
/// It fixes the defensive type-before-cardinality refusal order.
fn commit_cursor_index_probe(
  index : PublicationContract,
  entries : String,
) -> PublicationContract {
  let inventory = @json.object_field(index.value, "durable_result_binding_cids").unwrap()
  let inventory = canonical_value_wire(inventory, 65536, 4096, 32).unwrap()
  let wire = index.wire.replace(
    old="\"durable_result_binding_cids\":" + inventory,
    new="\"durable_result_binding_cids\":" + entries,
  )
  {
    name: index.name,
    identity_field: index.identity_field,
    wire_usage: None,
    identity: index.identity,
    wire,
    value: parse_contract_wire(wire, 65536, 4096, 32).unwrap(),
  }
}

///|
test "durable binding inventories retain independent work and exact frame bounds" {
  let fixture = commit_cursor_fixture(["first", "second"])
  for quantum in [1, 7, 64] {
    let check = start_durable_binding_preparation(
      fixture.binding_inputs,
      Some(16),
    )
    let mut work = 0
    let mut finished = false
    for _ in 0..<50 {
      let (done, used) = check.advance(quantum).unwrap()
      assert_true(used > 0 && used <= quantum)
      work += used
      if done {
        finished = true
        break
      }
    }
    assert_true(finished)
    // All prior/lookup/index scans plus fixed guards: 4*N*N + 14*N + 5.
    assert_eq(work, 49)
    assert_eq(check.peak, 16)
    check.cancel()
    assert_true(check.inputs is None)
    assert_eq(check.live, 0)
  }
  let short = start_durable_binding_preparation(
    fixture.binding_inputs,
    Some(15),
  )
  assert_eq(short.advance(1), Err(CommitEncoding))
  assert_true(short.inputs is None)
  assert_eq(short.live, 0)
}

///|
test "durable binding inventories preserve permuted membership and typed mismatch precedence" {
  let fixture = commit_cursor_fixture(["first", "second"])
  let inputs = fixture.binding_inputs
  validate_durable_result_bindings(
    inputs.run_definition,
    inputs.invocation,
    inputs.definitions,
    inputs.artifacts,
    inputs.orderings,
    inputs.retentions,
    [inputs.bindings[1], inputs.bindings[0]],
    inputs.index_entry,
  ).unwrap()
  assert_eq(
    validate_durable_result_bindings(
      inputs.run_definition,
      inputs.invocation,
      inputs.definitions,
      inputs.artifacts,
      inputs.orderings,
      inputs.retentions,
      [inputs.bindings[0], inputs.bindings[0]],
      inputs.index_entry,
    ),
    Err(CommitInventoryMismatch),
  )
  for
    field in [
      "run_definition_cid", "invocation_cid", "logical_result_cid", "result_schema_cid",
      "ordering_evidence_cid", "effective_retention_policy_cid",
    ] {
    let foreign = commit_cursor_reseal(
      inputs.bindings[0],
      field,
      inventory_fixture_cid("f"),
    )
    assert_eq(
      validate_durable_result_bindings(
        inputs.run_definition,
        inputs.invocation,
        inputs.definitions,
        inputs.artifacts,
        inputs.orderings,
        inputs.retentions,
        [foreign, inputs.bindings[1]],
        inputs.index_entry,
      ),
      Err(CommitReferenceMismatch("binding." + field)),
    )
  }
  let foreign = commit_cursor_reseal(
    inputs.bindings[0],
    "run_definition_cid",
    inventory_fixture_cid("f"),
  )
  assert_eq(
    validate_durable_result_bindings(
      inputs.run_definition,
      inputs.invocation,
      inputs.definitions,
      inputs.artifacts,
      [],
      [],
      [foreign, inputs.bindings[1]],
      inputs.index_entry,
    ),
    Err(CommitReferenceMismatch("binding.ordering_evidence_cid")),
  )
  let foreign_index = commit_cursor_reseal(
    inputs.index_entry,
    "run_receipt_cid",
    inventory_fixture_cid("f"),
  )
  // A binding inventory check does not substitute for the separate root
  // reference check. That root mutation is rejected by the reference owner.
  validate_durable_result_bindings(
    inputs.run_definition,
    inputs.invocation,
    inputs.definitions,
    inputs.artifacts,
    inputs.orderings,
    inputs.retentions,
    inputs.bindings,
    foreign_index,
  ).unwrap()
}

///|
test "durable binding index rejects missing duplicate extra and nonstring entries" {
  let inputs = commit_cursor_fixture(["first", "second"]).binding_inputs
  let first = "\"" + inputs.bindings[0].identity + "\""
  let second = "\"" + inputs.bindings[1].identity + "\""
  for
    (entries, cause) in [
      ("[" + first + "]", CommitInventoryMismatch),
      ("[" + first + "," + first + "]", CommitInventoryMismatch),
      (
        "[" + first + "," + second + ",\"" + inventory_fixture_cid("f") + "\"]",
        CommitInventoryMismatch,
      ),
      ("[null]", CommitReferenceMismatch("index.durable_result_binding_cids")),
    ] {
    let index = commit_cursor_index_probe(inputs.index_entry, entries)
    assert_eq(
      validate_durable_result_bindings(
        inputs.run_definition,
        inputs.invocation,
        inputs.definitions,
        inputs.artifacts,
        inputs.orderings,
        inputs.retentions,
        inputs.bindings,
        index,
      ),
      Err(cause),
    )
  }
  let index = commit_cursor_index_probe(
    inputs.index_entry,
    "[" + second + "," + first + "]",
  )
  validate_durable_result_bindings(
    inputs.run_definition,
    inputs.invocation,
    inputs.definitions,
    inputs.artifacts,
    inputs.orderings,
    inputs.retentions,
    inputs.bindings,
    index,
  ).unwrap()
}

///|
test "durable binding index scans yield and cancellation leaves borrowed contracts valid" {
  let fixture = commit_cursor_fixture(
    Array::makei(32, index => "result_\{index}"),
  )
  let check = start_durable_binding_preparation(
    fixture.binding_inputs,
    Some(16),
  )
  let original = fixture.binding_inputs.index_entry.wire
  let mut reached = false
  for _ in 0..<4550 {
    let (done, used) = check.advance(1).unwrap()
    assert_eq(used, 1)
    assert_true(!done)
    if check.phase is IndexMatches(_, _, index, _) && index > 0 {
      reached = true
      break
    }
  }
  assert_true(reached)
  check.cancel()
  check.cancel()
  assert_true(check.inputs is None)
  assert_eq(check.live, 0)
  assert_eq(check.advance(1), Err(CommitEncoding))
  assert_eq(fixture.binding_inputs.index_entry.wire, original)
  let complete = start_durable_binding_preparation(
    fixture.binding_inputs,
    Some(16),
  )
  let mut work = 0
  let mut finished = false
  for _ in 0..<4550 {
    let (done, used) = complete.advance(1).unwrap()
    work += used
    if done {
      finished = true
      break
    }
  }
  assert_true(finished)
  assert_eq(work, 4549)
  complete.cancel()
}

///|
test "commit references compare long names and namespace incrementally with exact workspace" {
  let prefix = "é".repeat(257) + "😀"
  let fixture = commit_cursor_fixture(
    [prefix + "a", prefix + "b"],
    namespace_id=prefix + "namespace",
  )
  for quantum in [1, 7, 64] {
    let check = start_publication_reference_preparation(
      fixture.reference_inputs,
      Some(24),
    )
    let mut work = 0
    let mut finished = false
    for _ in 0..<37 {
      let (done, used) = check.advance(quantum).unwrap()
      assert_true(used > 0 && used <= quantum)
      work += used
      if done {
        finished = true
        break
      }
    }
    assert_true(finished)
    // Reference guards: 11; inventory: N*N + 2*N + sum(name fragments) + 2;
    // namespace: five fragments. N=2, with five fragments per name.
    assert_eq(work, 36)
    assert_eq(check.peak, 24)
    check.cancel()
    assert_true(check.inputs is None)
    assert_eq(check.live, 0)
  }
  let short = start_publication_reference_preparation(
    fixture.reference_inputs,
    Some(23),
  )
  assert_eq(short.advance(1), Err(CommitEncoding))
  assert_true(short.inputs is None)
  assert_eq(short.live, 0)
}

///|
test "commit reference cancellation retires name and namespace cursors only" {
  let prefix = "é".repeat(257) + "😀"
  let fixture = commit_cursor_fixture(
    [prefix + "a", prefix + "b"],
    namespace_id=prefix + "namespace",
  )
  let original = fixture.reference_inputs.request.wire
  for namespace_phase in [false, true] {
    let check = start_publication_reference_preparation(
      fixture.reference_inputs,
      Some(24),
    )
    let mut reached = false
    for _ in 0..<37 {
      let (done, used) = check.advance(1).unwrap()
      assert_eq(used, 1)
      assert_true(!done)
      let matches = match check.phase {
        Inventory(child) if !namespace_phase =>
          match child.phase {
            Name(_, _, _, _, _, offset) => offset > 0
            _ => false
          }
        Namespace(offset) if namespace_phase => offset > 0
        _ => false
      }
      if matches {
        reached = true
        break
      }
    }
    assert_true(reached)
    check.cancel()
    check.cancel()
    assert_true(check.inputs is None)
    assert_eq(check.live, 0)
    assert_eq(check.advance(1), Err(CommitEncoding))
    assert_eq(fixture.reference_inputs.request.wire, original)
  }
  assert_true(
    publication_inventory_matches(
      fixture.reference_inputs.request,
      fixture.reference_inputs.definitions,
    ),
  )
}

///|
test "commit references preserve exact identity and long-prefix refusal causes" {
  let prefix = "é".repeat(257) + "😀"
  let fixture = commit_cursor_fixture(
    [prefix + "a", prefix + "b"],
    namespace_id=prefix + "namespace",
  )
  let inputs = fixture.reference_inputs
  let wrong_namespace = commit_cursor_reseal(
    inputs.index_entry,
    "namespace_id",
    prefix + "namespaceX",
  )
  assert_eq(
    validate_publication_commit_references(
      inputs.run_definition,
      inputs.invocation,
      inputs.definitions,
      inputs.manifest,
      inputs.receipt,
      inputs.captured_run,
      inputs.request,
      inputs.attempt,
      wrong_namespace,
    ),
    Err(CommitReferenceMismatch("index.namespace_id")),
  )
  let wrong_receipt = commit_cursor_reseal(
    inputs.index_entry,
    "run_receipt_cid",
    inventory_fixture_cid("f"),
  )
  assert_eq(
    validate_publication_commit_references(
      inputs.run_definition,
      inputs.invocation,
      inputs.definitions,
      inputs.manifest,
      inputs.receipt,
      inputs.captured_run,
      inputs.request,
      inputs.attempt,
      wrong_receipt,
    ),
    Err(CommitReferenceMismatch("index.run_receipt_cid")),
  )
  assert_eq(
    validate_publication_commit_references(
      inputs.run_definition,
      inputs.invocation,
      [inputs.definitions[0], inputs.definitions[0]],
      inputs.manifest,
      inputs.receipt,
      inputs.captured_run,
      inputs.request,
      inputs.attempt,
      wrong_namespace,
    ),
    Err(CommitInventoryMismatch),
  )
  assert_true(
    publication_inventory_matches(inputs.request, [
      inputs.definitions[1],
      inputs.definitions[0],
    ]),
  )
  let body = @json.object_without_field(
    inputs.request.value,
    inputs.request.identity_field,
  ).unwrap()
  let wire = canonical_value_wire(body, 65536, 4096, 32).unwrap()
  let wrong_name = seal_publication_contract(
    "publication_request",
    wire.replace(old=prefix + "a", new=prefix + "x"),
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(!publication_inventory_matches(wrong_name, inputs.definitions))
  assert_eq(
    validate_publication_commit_references(
      inputs.run_definition,
      inputs.invocation,
      inputs.definitions,
      inputs.manifest,
      inputs.receipt,
      inputs.captured_run,
      wrong_name,
      inputs.attempt,
      wrong_namespace,
    ),
    Err(CommitInventoryMismatch),
  )
}
