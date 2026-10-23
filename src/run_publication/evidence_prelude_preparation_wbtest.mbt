///|
fn stream_fixture_value(wire : String) -> @json.CanonicalValue {
  parse_contract_wire(wire, 65536, 4096, 32).unwrap()
}

///|
fn stream_fixture_wire(value : @json.CanonicalValue) -> String {
  canonical_value_wire(value, 65536, 4096, 32).unwrap()
}

///|
fn stream_test(
  value : @json.CanonicalValue,
  target : EvidenceStreamTarget,
  workspace : Int,
  bytes? : Int = 65536,
  nodes? : Int = 4096,
  depth? : Int = 32,
) -> EvidenceStreamPreparation {
  start_evidence_stream(value, target, bytes, nodes, depth, workspace)
}

///|
test "evidence streams use exact bounded fragments and independent control totals" {
  let text = "é".repeat(257) + "😀"
  let value = stream_fixture_value("\"" + text + "\"")
  let wire = "\"" + text + "\""
  // Begin, opening quote emit/compare, five Text emit/compare pairs, Done.
  for quantum in [1, 7, 64] {
    let check = stream_test(value, Wire(wire), 1038)
    let mut work = 0
    let mut done = false
    for _ in 0..<15 {
      let result = check.advance(quantum).unwrap()
      assert_true(result.1 > 0 && result.1 <= quantum)
      work += result.1
      if result.0 {
        done = true
        break
      }
    }
    assert_true(done)
    assert_eq(work, 14)
    assert_eq(check.peak, 1038)
    assert_true(check.finish().unwrap())
    assert_eq(check.live, 0)
    assert_true(check.left is None && check.target is None)
  }
  // Two identical streams have twelve emits, six compares, Begin and Done.
  let check = stream_test(value, Pair(value), 2063)
  let mut work = 0
  while true {
    let (done, used) = check.advance(1).unwrap()
    work += used
    if done {
      break
    }
    assert_true(work < 21)
  }
  assert_eq(work, 20)
  assert_eq(check.peak, 2063)
  assert_true(check.finish().unwrap())
  let too_small = stream_test(value, Wire(wire), 1037)
  assert_eq(too_small.advance(1).unwrap(), (false, 1))
  assert_true(too_small.advance(1) is Err(EvidenceEncoding))
  assert_eq(too_small.live, 0)
  assert_true(too_small.left_writer is None && too_small.value is None)
}

///|
test "evidence stream comparison preserves escaping Unicode and finite writer limits" {
  // Sixty-four escaped controls emit 384 ASCII units plus the two quotes;
  // comparison takes seven bounded fragments, even for one emitter Visit.
  let wire = "\"" + "\\u0000".repeat(64) + "\""
  let value = stream_fixture_value(wire)
  let check = stream_test(value, Wire(wire), 1038, bytes=386, nodes=1, depth=0)
  let mut work = 0
  while true {
    let (done, used) = check.advance(1).unwrap()
    work += used
    if done {
      break
    }
    assert_true(work < 11)
  }
  assert_eq(work, 10)
  assert_true(check.finish().unwrap())
  let short = stream_test(value, Wire(wire), 1038, bytes=385, nodes=1, depth=0)
  assert_eq(short.advance(1).unwrap(), (false, 1))
  assert_true(short.advance(1) is Err(EvidenceEncoding))
  assert_eq(short.live, 0)
  for
    (left, right, expected) in [
      ("\"e\\u0301\\r\\n😀\"", "\"é\\n😀\"", false),
      ("[0,null,\"😀\"]", "[0,null,\"😀\"]", true),
      ("{\"a\":[1,2],\"b\":null}", "{\"a\":[1,2],\"b\":null}", true),
      ("{\"a\":[1,2]}", "{\"a\":[1,2],\"b\":null}", false),
    ] {
    let check = stream_test(
      stream_fixture_value(left),
      Pair(stream_fixture_value(right)),
      8192,
    )
    let mut terminal = false
    for _ in 0..<500 {
      if check.advance(1).unwrap().0 {
        terminal = true
        break
      }
    }
    assert_true(terminal)
    assert_eq(check.finish().unwrap(), expected)
  }
}

///|
test "evidence streams keep bounds refusal ahead of a recorded mismatch" {
  let value = stream_fixture_value("[1,2,3,4]")
  let check = stream_test(value, Wire("wrong"), 4096, bytes=8)
  let mut refused = false
  for _ in 0..<50 {
    match check.advance(1) {
      Err(EvidenceEncoding) => {
        refused = true
        break
      }
      Err(_) => abort("Wrong stream refusal")
      Ok((done, _)) => assert_true(!done)
    }
  }
  assert_true(refused)
  assert_eq(check.live, 0)
  let pair = stream_test(value, Pair(stream_fixture_value("[9,8,7,6]")), 4096)
  while !pair.advance(7).unwrap().0 {
    ()
  }
  assert_true(!pair.finish().unwrap())
}

///|
test "evidence stream identity hashes and partial comparisons retire only private custody" {
  // SHA-256 of the canonical JSON null token, independently fixed.
  let check = stream_test(
    stream_fixture_value("null"),
    Identity(
      "sha256:74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b",
    ),
    14,
  )
  assert_eq(check.advance(1).unwrap(), (false, 1))
  assert_eq(check.advance(1).unwrap(), (true, 1))
  assert_eq(check.peak, 14)
  assert_true(check.finish().unwrap())
  let text = "é".repeat(4097) + "😀"
  let value = stream_fixture_value("\"" + text + "\"")
  for target in [EvidenceStreamTarget::Wire("\"" + text + "\""), Pair(value)] {
    let child = stream_test(value, target, 8192)
    let mut partial = false
    for _ in 0..<100 {
      assert_true(!child.advance(1).unwrap().0)
      if child.right_offset >= 64 {
        partial = true
        break
      }
    }
    assert_true(partial)
    child.cancel()
    child.cancel()
    assert_eq(child.live, 0)
    assert_true(
      child.left is None && child.right is None && child.target is None,
    )
    assert_true(child.advance(1) is Err(EvidenceEncoding))
    assert_eq(stream_fixture_wire(value), "\"" + text + "\"")
  }
}

///|
fn root_test_inputs(fixture : CommitCursorFixture) -> PublicationRootInputs {
  let inputs = fixture.binding_inputs
  {
    run_definition: inputs.run_definition,
    invocation: inputs.invocation,
    definitions: inputs.definitions,
    artifacts: inputs.artifacts,
    manifest: fixture.reference_inputs.manifest,
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
}

///|
fn root_test_finish(
  check : PublicationRootPreparation,
) -> Result[Unit, RunEvidenceChainIssue] {
  for _ in 0..<100000 {
    match check.advance(1) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => {
        check.cancel()
        return Ok(())
      }
      Ok((false, _)) => ()
    }
  }
  Err(EvidenceEncoding)
}

///|
test "publication root traverses long names and exact Artifact wires without inventory copies" {
  let prefix = "é".repeat(257) + "😀"
  let fixture = commit_cursor_fixture([prefix + "a", prefix + "b"])
  let issued = root_test_inputs(fixture)
  // This existing stream/workspace/cancellation regression exercises an
  // independently admitted Manifest, not the issuer's same-child reuse.
  let inputs = {
    ..issued,
    manifest: admit_publication_contract(
      "result_manifest", issued.manifest.wire, 65536, 4096, 32,
    ).unwrap(),
  }
  let original = inputs.manifest.wire
  // Two twelve-field Artifacts each have 47 emitter transitions and 46
  // nonempty fragment comparisons: Begin + 47 + 46 + Done = 95. The root's
  // kind/name/reference scans contribute 59 transitions for these names.
  // Twelve root slots plus a stream's 12 + 1024 + three pending frames and
  // one provisional reservation give a peak of 1052.
  for quantum in [1, 7, 64] {
    let check = start_publication_root_preparation(inputs, 1052)
    let mut work = 0
    let mut finished = false
    for _ in 0..<10000 {
      let (done, used) = check.advance(quantum).unwrap()
      assert_true(used > 0 && used <= quantum)
      work += used
      if done {
        finished = true
        break
      }
    }
    assert_true(finished)
    assert_eq(work, 249)
    assert_eq(check.peak, 1052)
    check.cancel()
    assert_true(check.inputs is None && check.results is None)
  }
  let too_small = start_publication_root_preparation(inputs, 1051)
  assert_eq(root_test_finish(too_small), Err(EvidenceRoot(ChainEncoding)))
  assert_true(too_small.inputs is None && too_small.results is None)
  let check = start_publication_root_preparation(inputs, 8192)
  let mut partial = false
  for _ in 0..<10000 {
    assert_true(!check.advance(1).unwrap().0)
    if check.phase is Wire(_, _, child) && child.right_offset > 64 {
      partial = true
      break
    }
  }
  assert_true(partial)
  check.cancel()
  assert_eq(inputs.manifest.wire, original)
  validate_run_publication_chain(
    inputs.run_definition,
    inputs.invocation,
    inputs.definitions,
    inputs.artifacts,
    inputs.manifest,
    65536,
    4096,
    32,
  ).unwrap()
}

///|
test "publication root keeps duplicate and inventory failure precedence" {
  let fixture = commit_cursor_fixture(["first", "second"])
  let inputs = root_test_inputs(fixture)
  let duplicate = {
    ..inputs,
    definitions: [inputs.definitions[0], inputs.definitions[0]],
  }
  assert_eq(
    root_test_finish(start_publication_root_preparation(duplicate, 8192)),
    Err(EvidenceRoot(ChainDuplicateResult("first"))),
  )
  let missing = { ..inputs, definitions: [inputs.definitions[0]], }
  assert_eq(
    root_test_finish(start_publication_root_preparation(missing, 8192)),
    Err(EvidenceRoot(ChainArtifactMismatch("inventory"))),
  )
  let absent = {
    ..inputs,
    definitions: [
      result_definition_contract(
        prepare_result_definition(inventory_fixture_cid("1"), "absent").unwrap(),
      ),
    ],
  }
  assert_eq(
    root_test_finish(start_publication_root_preparation(absent, 8192)),
    Err(EvidenceRoot(ChainMissingResult("absent"))),
  )
  let foreign = {
    ..inputs,
    definitions: [
      inputs.definitions[0],
      result_definition_contract(
        prepare_result_definition(inventory_fixture_cid("1"), "elsewhere").unwrap(),
      ),
    ],
  }
  assert_eq(
    root_test_finish(start_publication_root_preparation(foreign, 8192)),
    Err(EvidenceRoot(ChainForeignResult("second"))),
  )
  let kinds = {
    ..inputs,
    artifacts: [inputs.run_definition, inputs.artifacts[0]],
  }
  assert_eq(
    root_test_finish(start_publication_root_preparation(kinds, 8192)),
    Err(EvidenceRoot(ChainWrongContract("result_artifact"))),
  )
}
