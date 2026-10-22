///|
priv struct RetainedComputationFixture {
  owner : CapturedRunIssuancePreparation
  originals : Array[PublicationContract]
}

///|
fn retained_computation_fixture() -> RetainedComputationFixture raise {
  let base = commit_read_fixture()
  let originals = base.originals.copy()
  let authoring = captured_run_test_chain(
      schema_cid="sha256:98fbcb0aa0d1065cf0b027b6390716452941ac4723d0b2cadfce3476280683db",
    ).authoring
  let snapshot = admit_captured_result_snapshot(
    originals[8],
    originals[9],
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let owner = start_effect_free_captured_run(
    originals[0],
    originals[1],
    [originals[8]],
    [originals[9]],
    originals[2],
    originals[3],
    [snapshot],
    [],
    authoring,
    [],
    65536,
    4096,
    32,
    32768,
  )
  while !owner.advance(256).unwrap().0 {
    ()
  }
  let captured = owner.finish_retained().unwrap()
  assert_eq(
    publication_contract_json(captured),
    publication_contract_json(originals[4]),
  )
  originals[4] = captured
  base.preparation.cancel()
  { owner, originals, }
}

///|
fn retained_test_chain(
  owner : CapturedRunIssuancePreparation,
  originals : Array[PublicationContract],
  wire? : Int = 65536,
  nodes? : Int = 4096,
  depth? : Int = 32,
) -> ComputationEvidenceCheck {
  start_effect_free_run_evidence_check_retained(
    owner,
    originals[0],
    originals[1],
    [originals[8]],
    [originals[9]],
    originals[2],
    originals[3],
    originals[4],
    wire,
    nodes,
    depth,
    32768,
  )
}

///|
fn retained_test_commit(
  owner : CapturedRunIssuancePreparation,
  originals : Array[PublicationContract],
  derivations? : Array[PublicationContract]? = None,
) -> PublicationCommitPreparation {
  start_effect_free_publication_commit_check_retained(
    owner,
    originals[0],
    originals[1],
    [originals[8]],
    [originals[9]],
    derivations.unwrap_or([originals[10]]),
    [originals[11]],
    [originals[12]],
    [originals[13]],
    originals[2],
    originals[3],
    originals[4],
    originals[5],
    originals[6],
    originals[7],
    65536,
    4096,
    32,
    32768,
  )
}

///|
fn retained_test_complete_chain(check : ComputationEvidenceCheck) -> Int {
  let mut work = 0
  for _ in 0..<500000 {
    let (done, used) = check.advance(1).unwrap()
    work += used
    if done {
      check.finish().unwrap()
      return work
    }
  }
  abort("Computation check exceeded finite fixture work")
}

///|
test "retained captured facts reuse the same tokens without computation work" {
  let fixture = retained_computation_fixture()
  assert_eq(captured_run_preparation_fixture_phase(fixture.owner), "retained")
  assert_eq(
    captured_run_preparation_fixture_inventory(fixture.owner),
    (30, 0, false, false),
  )
  assert_true(fixture.owner.finish_retained() is Err(CaptureIssuanceEncoding))
  assert_true(fixture.owner.finish() is Err(CaptureIssuanceEncoding))
  assert_true(fixture.owner.advance(1) is Err(CaptureIssuanceEncoding))
  let check = retained_test_chain(fixture.owner, fixture.originals)
  assert_eq(computation_evidence_check_fixture_phase(check), "done")
  assert_eq(retained_test_complete_chain(check), 0)
  let looser = retained_test_chain(
    fixture.owner,
    fixture.originals,
    wire=65537,
    nodes=4097,
    depth=33,
  )
  assert_eq(retained_test_complete_chain(looser), 0)
  fixture.owner.cancel()
  fixture.owner.cancel()
  assert_eq(
    captured_run_preparation_fixture_inventory(fixture.owner),
    (0, 0, false, false),
  )
  let restored = retained_test_chain(fixture.owner, fixture.originals)
  assert_true(retained_test_complete_chain(restored) > 0)
}

///|
test "copied tokens and tighter bounds retain full computation checking" {
  let fixture = retained_computation_fixture()
  for index in [0, 1, 2, 3, 4, 8, 9] {
    let selected = fixture.originals.copy()
    selected[index] = admit_publication_contract(
      publication_contract_name(selected[index]),
      publication_contract_json(selected[index]),
      65536,
      4096,
      32,
    ).unwrap()
    let check = retained_test_chain(fixture.owner, selected)
    assert_true(retained_test_complete_chain(check) > 0)
  }
  for
    (wire, nodes, depth) in [
      (65535, 4096, 32),
      (65536, 4095, 32),
      (65536, 4096, 31),
    ] {
    let check = retained_test_chain(
      fixture.owner,
      fixture.originals,
      wire~,
      nodes~,
      depth~,
    )
    assert_true(retained_test_complete_chain(check) > 0)
  }
  let foreign = retained_computation_fixture()
  assert_true(
    retained_test_complete_chain(
      retained_test_chain(foreign.owner, fixture.originals),
    ) >
    0,
  )
  foreign.owner.cancel()
  fixture.owner.cancel()
}

///|
test "retiring a captured holder invalidates an outstanding computation borrow" {
  let fixture = retained_computation_fixture()
  let check = retained_test_chain(fixture.owner, fixture.originals)
  fixture.owner.cancel()
  assert_true(check.advance(1) is Err(EvidenceEncoding))
  assert_true(check.finish() is Err(EvidenceEncoding))
  check.cancel()
}

///|
test "retained computation skips no Result dependency or new commit reference" {
  let fixture = retained_computation_fixture()
  let check = retained_test_commit(fixture.owner, fixture.originals)
  let mut done = false
  for _ in 0..<500000 {
    let (complete, _) = check.advance(1).unwrap()
    let phase = publication_commit_preparation_fixture_phase(check)
    assert_true(
      phase != "root-check" && phase != "context-check" && phase != "rows-check",
    )
    if complete {
      done = true
      break
    }
  }
  assert_true(done)
  let view = check.finish_view().unwrap()
  fixture.owner.cancel()
  assert_eq(check.view_count(view).unwrap(), fixture.originals.length())
  for index = 0; index < fixture.originals.length(); index = index + 1 {
    assert_eq(
      publication_contract_json(check.view_contract(view, index).unwrap()),
      publication_contract_json(fixture.originals[index]),
    )
  }
  check.release_view(view).unwrap()

  let failure_fixture = retained_computation_fixture()
  let dependencies = retained_test_commit(
    failure_fixture.owner,
    failure_fixture.originals,
    derivations=Some([]),
  )
  assert_eq(
    dependencies.advance(1),
    Err(CommitResultEvidence(ResultEvidenceCount)),
  )
  let changed = failure_fixture.originals.copy()
  changed[5] = changed[0]
  let references = retained_test_commit(failure_fixture.owner, changed)
  let mut refused = false
  for _ in 0..<500000 {
    match references.advance(1) {
      Err(_) => {
        refused = true
        break
      }
      Ok((complete, _)) => assert_true(!complete)
    }
  }
  assert_true(refused)
  failure_fixture.owner.cancel()
}

///|
test "retired captured holder cannot lend to a pending commit" {
  let fixture = retained_computation_fixture()
  let check = retained_test_commit(fixture.owner, fixture.originals)
  fixture.owner.cancel()
  assert_true(check.advance(1) is Err(CommitEncoding))
  assert_true(check.finish() is Err(CommitEncoding))
  check.cancel()
}

///|
test "changed computation inputs receive the original refusal without poisoning reuse" {
  let fixture = retained_computation_fixture()
  let changed = fixture.originals.copy()
  changed[3] = changed[2]
  let check = retained_test_chain(fixture.owner, changed)
  assert_true(computation_evidence_check_fixture_phase(check) != "done")
  let mut refused = false
  for _ in 0..<500000 {
    match check.advance(1) {
      Err(EvidenceWrongContract("run_receipt")) => {
        refused = true
        break
      }
      Err(_) => abort("Unexpected changed Receipt refusal")
      Ok((complete, _)) => assert_true(!complete)
    }
  }
  assert_true(refused)
  assert_eq(
    retained_test_complete_chain(
      retained_test_chain(fixture.owner, fixture.originals),
    ),
    0,
  )
  fixture.owner.cancel()
}
