///|
priv struct InventoryFixture {
  definitions : Array[PublicationContract]
  artifacts : Array[PublicationContract]
  derivations : Array[PublicationContract]
  orderings : Array[PublicationContract]
  retention : PublicationContract
}

///|
fn inventory_fixture_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn inventory_fixture(
  count : Int,
  provenance_count? : Int = 1,
) -> InventoryFixture {
  let policy = inventory_fixture_cid("e")
  let retention = seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    inventory_fixture_cid("8") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2026-09-18T01:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T02:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T03:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    inventory_fixture_cid("9") +
    "\",\"metadata_delete_by\":\"2026-09-18T04:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    inventory_fixture_cid("a") +
    "\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let fixture : InventoryFixture = {
    definitions: [],
    artifacts: [],
    derivations: [],
    orderings: [],
    retention,
  }
  for index in 0..<count {
    let definition = result_definition_contract(
      prepare_result_definition(inventory_fixture_cid("1"), "result_\{index}").unwrap(),
    )
    let evidence = issue_result_occurrence_evidence(
      definition,
      inventory_fixture_cid("3"),
      inventory_fixture_cid("4"),
      inventory_fixture_cid("2"),
      [],
      inventory_fixture_cid("5"),
      policy,
      "common-host",
      inventory_fixture_cid("6"),
      65536,
      4096,
      32,
    ).unwrap()
    let provenance : Array[String] = []
    for entry in 0..<(provenance_count - 1) {
      let parsed = @source.parse_json("\"unrelated_\{entry}\"", {
        max_input_bytes: 65536,
        max_nodes: 4096,
        max_depth: 32,
      }).unwrap()
      let value = @json.from_source(parsed, 4096, 32, 65536) catch {
        _ => abort("Invalid fixture provenance value")
      }
      let cid = @json.cid_value(value, 65536, 4096, 32) catch {
        _ => abort("Invalid fixture provenance")
      }
      provenance.push("\"" + cid + "\"")
    }
    provenance.push("\"" + evidence.derivation.identity + "\"")
    let artifact = seal_publication_contract(
      "result_artifact",
      "{\"version\":\"actql-result-artifact/0.1\"," +
      "\"result_definition_cid\":\"" +
      definition.identity +
      "\",\"invocation_cid\":\"" +
      inventory_fixture_cid("b") +
      "\",\"logical_result_cid\":\"" +
      inventory_fixture_cid("3") +
      "\",\"result_schema_cid\":\"" +
      inventory_fixture_cid("4") +
      "\",\"ordering_evidence_cid\":\"" +
      evidence.ordering.identity +
      "\",\"actual_row_count\":1,\"actual_completeness\":\"complete\"," +
      "\"effective_data_policy_cid\":\"" +
      policy +
      "\",\"effective_retention_policy_cid\":\"" +
      retention.identity +
      "\",\"provenance_evidence_cids\":[" +
      provenance.join(",") +
      "]}",
      65536,
      4096,
      32,
    ).unwrap()
    fixture.definitions.push(definition)
    fixture.artifacts.push(artifact)
    fixture.derivations.push(evidence.derivation)
    fixture.orderings.push(evidence.ordering)
  }
  fixture
}

///|
fn inventory_fixture_start(
  fixture : InventoryFixture,
  workspace : Int,
) -> ResultEvidencePreparation {
  start_result_evidence_preparation(
    fixture.definitions,
    fixture.artifacts,
    fixture.derivations,
    fixture.orderings,
    [fixture.retention],
    Some(workspace),
  )
}

///|
test "Result inventory control work and workspace follow independent bounds" {
  let fixture = inventory_fixture(2)
  // Sixteen fixed owner slots, two use flags per Artifact, one shared
  // retention flag, and an eight-slot provenance continuation: 16 + 4 + 1 + 8.
  for quantum in [1, 7, 64] {
    let check = inventory_fixture_start(fixture, 29)
    let mut work = 0
    let mut finished = false
    for _ in 0..<43 {
      let (done, used) = check.advance(quantum).unwrap()
      assert_true(used > 0 && used <= quantum)
      work += used
      if done {
        finished = true
        break
      }
    }
    assert_true(finished)
    // Begin/end transitions, flag initialization, four exact reference scans,
    // duplicate/use checks, ordering guards, and one provenance entry each.
    assert_eq(work, 42)
    assert_eq(check.peak, 29L)
    check.cancel()
    assert_eq(check.live, 0L)
    assert_true(check.inputs is None)
    assert_eq(check.derivations_used.length(), 0)
    assert_eq(check.orderings_used.length(), 0)
    assert_eq(check.retentions_used.length(), 0)
  }
  let short = inventory_fixture_start(fixture, 28)
  let mut failure = None
  for _ in 0..<43 {
    match short.advance(1) {
      Err(issue) => {
        failure = Some(issue)
        break
      }
      Ok((done, _)) => assert_true(!done)
    }
  }
  assert_eq(failure, Some(CommitEncoding))
  assert_eq(short.live, 0L)
  assert_true(short.inputs is None)
  validate_result_evidence_set(
    fixture.definitions,
    fixture.artifacts,
    fixture.derivations,
    fixture.orderings,
    [fixture.retention],
  ).unwrap()
}

///|
test "Result inventory cancellation releases private flags at each scan boundary" {
  let fixture = inventory_fixture(4, provenance_count=129)
  let original = fixture.artifacts[0].wire
  for boundary in 0..<4 {
    let check = inventory_fixture_start(fixture, 33)
    let mut reached = false
    for _ in 0..<1000 {
      let (done, work) = check.advance(1).unwrap()
      assert_true(!done)
      assert_eq(work, 1)
      let matches = match (boundary, check.phase) {
        (0, Retentions(_, _)) => true
        (1, Initialize(_, index)) => index > 0
        (2, Lookup(_, _, index, _, _)) => index > 0
        (3, ArtifactEvidence(child)) =>
          match child.phase {
            Provenance(_, index) => index > 0
            _ => false
          }
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
    assert_eq(check.live, 0L)
    assert_true(check.inputs is None)
    assert_eq(check.derivations_used.length(), 0)
    assert_eq(check.orderings_used.length(), 0)
    assert_eq(check.retentions_used.length(), 0)
    assert_eq(check.advance(1), Err(CommitEncoding))
    assert_eq(fixture.artifacts[0].wire, original)
  }
  validate_result_evidence_set(
    fixture.definitions,
    fixture.artifacts,
    fixture.derivations,
    fixture.orderings,
    [fixture.retention],
  ).unwrap()
}

///|
test "Result provenance checks one entry per poll and retains exact refusal" {
  let fixture = inventory_fixture(1, provenance_count=129)
  let evidence : ResultOrderingEvidence = {
    derivation: fixture.derivations[0],
    ordering: fixture.orderings[0],
  }
  let child = start_result_artifact_check(
    fixture.definitions[0].identity,
    fixture.artifacts[0],
    evidence,
    fixture.retention,
  )
  assert_eq(child.step(), Ok(false))
  for index in 0..<128 {
    assert_eq(child.step(), Ok(false))
    guard child.phase is Provenance(_, position) else {
      fail("provenance phase")
    }
    assert_eq(position, index + 1)
  }
  assert_eq(child.step(), Ok(true))
  child.cancel()
  assert_true(child.inputs is None)
  let missing = @json.object_without_field(
    fixture.artifacts[0].value,
    fixture.artifacts[0].identity_field,
  ).unwrap()
  let wire = @json.stringify_value(missing, 65536, 4096, 32) catch {
    _ => abort("Invalid fixture artifact")
  }
  let missing_artifact = seal_publication_contract(
    "result_artifact",
    wire.replace(
      old=evidence.derivation.identity,
      new=inventory_fixture_cid("f"),
    ),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    validate_result_artifact_evidence(
      fixture.definitions[0],
      missing_artifact,
      evidence,
      fixture.retention,
    ),
    Err(ArtifactMissingDerivation),
  )
}

///|
test "Result inventory retains duplicate and missing dependency diagnostics" {
  let fixture = inventory_fixture(2)
  assert_eq(
    validate_result_evidence_set(
      fixture.definitions,
      fixture.artifacts,
      fixture.derivations,
      fixture.orderings,
      [fixture.retention, fixture.retention],
    ),
    Err(ResultEvidenceDuplicate),
  )
  assert_eq(
    validate_result_evidence_set(
      [fixture.definitions[0], fixture.definitions[0]],
      fixture.artifacts,
      fixture.derivations,
      fixture.orderings,
      [fixture.retention],
    ),
    Err(ResultEvidenceMissingDefinition),
  )
  assert_eq(
    validate_result_evidence_set(
      fixture.definitions,
      fixture.artifacts,
      [fixture.derivations[0], fixture.derivations[0]],
      fixture.orderings,
      [fixture.retention],
    ),
    Err(ResultEvidenceMissingDerivation),
  )
  assert_eq(
    validate_result_evidence_set(
      fixture.definitions,
      fixture.artifacts,
      fixture.derivations,
      [fixture.orderings[0], fixture.orderings[0]],
      [fixture.retention],
    ),
    Err(ResultEvidenceMissingOrdering),
  )
  assert_eq(
    validate_result_evidence_set(
      fixture.definitions,
      [fixture.artifacts[0], fixture.artifacts[0]],
      fixture.derivations,
      fixture.orderings,
      [fixture.retention],
    ),
    Err(ResultEvidenceDuplicate),
  )
}

///|
test "Result inventory reference scans progress at quantum one without bulk initialization" {
  let fixture = inventory_fixture(32)
  let check = inventory_fixture_start(fixture, 89)
  assert_eq(check.derivations_used.length(), 0)
  assert_eq(check.orderings_used.length(), 0)
  assert_eq(check.retentions_used.length(), 0)
  let mut done = false
  let mut work = 0
  for _ in 0..<3463 {
    let prior = check.phase
    let (finished, used) = check.advance(1).unwrap()
    assert_eq(used, 1)
    work += used
    match (prior, check.phase) {
      (Lookup(kind, _, position, _, _), Lookup(next_kind, _, next, _, _)) =>
        if kind == next_kind {
          assert_eq(next, position + 1)
        }
      _ => ()
    }
    if finished {
      done = true
      break
    }
  }
  assert_true(done)
  // 5 + R + R*(R-1)/2 + 2*A + A*(3*A + R + 8 + P), with
  // A=32 Artifacts, R=1 retention, and P=1 provenance entry per Artifact.
  assert_eq(work, 3462)
  assert_eq(check.peak, 89L)
  check.cancel()
  assert_eq(check.live, 0L)
}

///|
test "Result inventory empty sets and early budget refusal retain no borrowed roots" {
  let empty = start_result_evidence_preparation([], [], [], [], [], Some(16))
  assert_eq(empty.advance(5), Ok((true, 5)))
  empty.cancel()
  assert_eq(empty.live, 0L)
  assert_eq(validate_result_evidence_set([], [], [], [], []), Ok(()))
  let fixture = inventory_fixture(1)
  let short = inventory_fixture_start(fixture, 15)
  assert_eq(short.advance(1), Err(CommitEncoding))
  assert_true(short.inputs is None)
  assert_eq(short.live, 0L)
  assert_eq(short.derivations_used.length(), 0)
  assert_eq(short.orderings_used.length(), 0)
  assert_eq(short.retentions_used.length(), 0)
  assert_eq(
    validate_result_evidence_set([], [], [], [], [fixture.retention]),
    Err(ResultEvidenceCount),
  )
}
