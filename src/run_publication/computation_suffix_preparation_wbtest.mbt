///|
fn suffix_fixture_inputs() -> ComputationSuffixInputs {
  // Canonical bodies and SHA-256 values are authored independently. This is
  // an isolated suffix fixture, not an admitted complete Model invocation.
  let a = "sha256:663a7bcd81810cce90ee6aade5989160b356062a4a1e3dbf71756fc6d0224448"
  let b = "sha256:d712ef7ae4cfd6383b426e2cba7626ea598eefc785a24eb8874930c0d60b9ab4"
  let program = "sha256:" + "8".repeat(64)
  let authoring = "{\"authoring_context_cid\":\"sha256:6f968b232c060e5abe84eaaa82911066aa277465fb82de735c76f9d7d46a68b7\",\"program_definition_cid\":\"" +
    program +
    "\",\"version\":\"authoring-fixture\"}"
  let alpha = "{\"model_invocation_evidence_cid\":\"" +
    a +
    "\",\"payload\":\"alpha\",\"version\":\"model-fixture\"}"
  let beta = "{\"model_invocation_evidence_cid\":\"" +
    b +
    "\",\"payload\":\"beta\",\"version\":\"model-fixture\"}"
  let context = stream_fixture_value(
    "{\"authoring_context\":" +
    authoring +
    ",\"model_invocation_evidence\":[" +
    alpha +
    "," +
    beta +
    "," +
    alpha +
    "," +
    beta +
    "],\"model_invocation_evidence_cids\":[\"" +
    a +
    "\",\"" +
    b +
    "\",\"" +
    a +
    "\",\"" +
    b +
    "\"]}",
  )
  {
    context,
    program: Some(program),
    external_model_cids: [b, a, b, a],
    preview: None,
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
}

///|
test "suffix evidence distinguishes empty Models missing references and identity changes" {
  let inputs = suffix_fixture_inputs()
  let empty_context = stream_fixture_value(
    "{\"authoring_context\":" +
    stream_fixture_wire(
      @json.object_field(inputs.context, "authoring_context").unwrap(),
    ) +
    ",\"model_invocation_evidence\":[],\"model_invocation_evidence_cids\":[]}",
  )
  let empty_inputs = {
    ..inputs,
    context: empty_context,
    external_model_cids: [],
  }
  // Nine authoring polls plus seven fixed transitions. The two-field
  // authoring emitter needs fifteen private slots beside the frame of sixteen.
  let empty = start_computation_suffix(empty_inputs, 31)
  let mut total = 0
  for _ in 0..<17 {
    let (done, used) = empty.advance(1).unwrap()
    total += used
    if done {
      break
    }
  }
  assert_eq(total, 16)
  assert_eq(empty.peak, 31)
  empty.finish().unwrap()
  let short = start_computation_suffix(empty_inputs, 30)
  let mut short_refused = false
  for _ in 0..<17 {
    match short.advance(1) {
      Err(EvidenceEmbeddedIdentity("authoring_context_cid")) => {
        short_refused = true
        break
      }
      Err(_) => abort("unrelated authoring frame refusal")
      Ok(_) => ()
    }
  }
  assert_true(short_refused)
  assert_eq(short.live, 0)
  let original = stream_fixture_wire(inputs.context)
  let mutated = stream_fixture_value(
    original.replace(old="\"alpha\"", new="\"ALPHA\""),
  )
  let missing = @json.object_without_field(
    inputs.context,
    "model_invocation_evidence_cids",
  ).unwrap()
  let a = inputs.external_model_cids[1]
  let b = inputs.external_model_cids[0]
  let reordered = stream_fixture_value(
    original.replace(
      old="\"model_invocation_evidence_cids\":[\"" + a + "\",\"" + b,
      new="\"model_invocation_evidence_cids\":[\"" + b + "\",\"" + a,
    ),
  )
  for
    (context, expected) in [
      (mutated, EvidenceReferenceMismatch("model_invocation_evidence_cids")),
      (missing, EvidenceMissingField("model_invocation_evidence_cids")),
      (reordered, EvidenceReferenceMismatch("model_invocation_evidence_cids")),
    ] {
    let check = start_computation_suffix({ ..inputs, context, }, 48)
    let mut refusal = None
    for _ in 0..<100 {
      match check.advance(1) {
        Err(issue) => {
          refusal = Some(issue)
          break
        }
        Ok((true, _)) => abort("mutated suffix accepted")
        Ok((false, _)) => ()
      }
    }
    assert_true(refusal == Some(expected))
    assert_eq(check.live, 0)
  }
  assert_eq(stream_fixture_wire(inputs.context), original)
}

///|
test "suffix evidence uses independent charged transitions and exact private frames" {
  let inputs = suffix_fixture_inputs()
  let original = stream_fixture_wire(inputs.context)
  let external = inputs.external_model_cids.copy()
  // Begin + authoring (1 + 8 emits) + Models + four (Model + 7 identity
  // transitions) + Model end + five external transitions + two sorts of
  // 20 polls + four two-fragment equality checks + Compare end = 98.
  // Sixteen frame slots plus eight per Model/External pair = 48.
  for quantum in [1, 7, 64] {
    let check = start_computation_suffix(inputs, 48)
    let mut work = 0
    let mut done = false
    for _ in 0..<99 {
      let result = check.advance(quantum).unwrap()
      assert_true(result.1 > 0 && result.1 <= quantum)
      work += result.1
      if result.0 {
        done = true
        break
      }
    }
    assert_true(done)
    assert_eq(work, 98)
    assert_eq(check.peak, 48)
    check.finish().unwrap()
    assert_eq(check.live, 0)
    assert_true(check.inputs is None && check.model_sort is None)
    assert_eq(inputs.external_model_cids, external)
    assert_eq(stream_fixture_wire(inputs.context), original)
  }
  let short = start_computation_suffix(inputs, 47)
  let mut refused = false
  for _ in 0..<99 {
    match short.advance(1) {
      Err(EvidenceEncoding) => {
        refused = true
        break
      }
      Err(_) => abort("unrelated suffix refusal")
      Ok((true, _)) => abort("one-short suffix frame limit was accepted")
      Ok((false, _)) => ()
    }
  }
  assert_true(refused)
  assert_eq(short.live, 0)
  assert_true(short.model_keys.is_empty() && short.external_keys.is_empty())
}

///|
test "suffix evidence preserves multiplicity typed failures and borrowed inputs" {
  let inputs = suffix_fixture_inputs()
  let a = inputs.external_model_cids[1]
  let original = stream_fixture_wire(inputs.context)
  let bad = start_computation_suffix(
    { ..inputs, external_model_cids: [a, a, a, a], },
    48,
  )
  let mut mismatch = false
  for _ in 0..<150 {
    match bad.advance(1) {
      Err(EvidenceReferenceMismatch("external_model_evidence")) => {
        mismatch = true
        break
      }
      Err(_) => abort("unrelated Model multiplicity refusal")
      Ok((true, _)) => abort("Model multiplicity mismatch accepted")
      Ok((false, _)) => ()
    }
  }
  assert_true(mismatch)
  let wrong_program = start_computation_suffix({ ..inputs, program: None, }, 48)
  let mut authoring = false
  for _ in 0..<20 {
    match wrong_program.advance(1) {
      Err(EvidenceEmbeddedIdentity("authoring_context_cid")) => {
        authoring = true
        break
      }
      Err(_) => abort("unrelated authoring refusal")
      Ok(_) => ()
    }
  }
  assert_true(authoring)
  for phase in [0, 1, 2, 3, 4] {
    let check = start_computation_suffix(inputs, 48)
    let mut reached = false
    let mut visits = 0
    for _ in 0..<99 {
      let (done, _) = check.advance(1).unwrap()
      assert_true(!done)
      let hit = match check.phase {
        Authoring(_, _) => phase == 0
        Identity(_, _, _) => phase == 1
        SortModels(_) => phase == 2
        SortExternal(_) => phase == 3
        Compare(_, offset) => phase == 4 && offset == 64
        _ => false
      }
      if hit {
        visits += 1
        if visits == 2 {
          reached = true
          break
        }
      }
    }
    assert_true(reached)
    check.cancel()
    check.cancel()
    assert_eq(check.live, 0)
    assert_true(
      check.inputs is None &&
      check.model_sort is None &&
      check.external_sort is None,
    )
    assert_true(check.advance(1) is Err(EvidenceEncoding))
    assert_eq(stream_fixture_wire(inputs.context), original)
  }
}
