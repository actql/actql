///|
fn evidence_fixture(
  owner : @lower.BoundPrepared,
  physical_live : Ref[Bool],
) -> CompletedOutput raise {
  let source = export_fixture(owner)
  let (exported, text) = export_all(source)
  let handle = retain_admitted_output_stream(
    completed_export_content(exported),
    text,
    fn() { physical_live.val },
  )
  bind_completed_output_export(exported, retained_output_material(handle)).unwrap()
}

///|
test "completed evidence retains exact occurrence but no permission after physical loss" {
  let owner = capture_fixture()
  let live = Ref(true)
  let output = evidence_fixture(owner, live)
  let evidence = retain_completion_evidence(output, 10, 10).unwrap()
  let descriptor = retained_completion_descriptor(evidence)
  assert_eq(
    descriptor.rows_cid,
    "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
  )
  assert_eq(descriptor.output_step, 1)
  assert_eq(descriptor.rows, 2)
  assert_eq(descriptor.columns, 2)
  assert_eq(descriptor.values, { nodes: 6, text_bytes: 10, work: 16, })
  assert_true(retained_completion_can_handoff(evidence, output))
  assert_true(retained_completion_material(evidence, output) is Some(_))
  live.val = false
  assert_true(retained_completion_matches_output(evidence, output))
  assert_eq(retained_completion_descriptor(evidence), descriptor)
  assert_false(retained_completion_can_handoff(evidence, output))
  assert_true(retained_completion_material(evidence, output) is None)
  assert_true(retain_completion_evidence(output, 10, 10) is Err(Unavailable))
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  assert_true(
    bind_completed_input(receiver, 0, owner, output) is Err(ProducerUnavailable),
  )
}

///|
test "equal descriptors from separate executions do not share completion evidence" {
  let owner = capture_fixture()
  let first = evidence_fixture(owner, Ref(true))
  let second = evidence_fixture(owner, Ref(true))
  let foreign = evidence_fixture(capture_fixture(), Ref(true))
  let evidence = retain_completion_evidence(first, 10, 10).unwrap()
  let other = retain_completion_evidence(second, 10, 10).unwrap()
  assert_eq(
    retained_completion_descriptor(evidence),
    retained_completion_descriptor(other),
  )
  assert_false(retained_completion_matches_output(evidence, second))
  assert_false(retained_completion_matches_output(evidence, foreign))
  assert_false(retained_completion_can_handoff(evidence, second))
  assert_true(retained_completion_material(evidence, second) is None)
}

///|
test "logical revocation blocks new handoff without deleting immutable evidence" {
  let owner = capture_fixture()
  let live = Ref(true)
  let output = restrict_completed_output(evidence_fixture(owner, Ref(true)), fn() {
    live.val
  })
  let evidence = retain_completion_evidence(output, 10, 10).unwrap()
  live.val = false
  assert_false(retained_completion_can_handoff(evidence, output))
  assert_true(retained_completion_matches_output(evidence, output))
  assert_true(retain_completion_evidence(output, 10, 10) is Err(Unavailable))
}

///|
test "evidence extraction is bounded and does not implicitly export row storage" {
  let owner = capture_fixture()
  let memory = export_fixture(owner)
  assert_true(retain_completion_evidence(memory, 10, 10) is Err(NotRetained))
  let output = evidence_fixture(owner, Ref(true))
  assert_true(retain_completion_evidence(output, -1, 10) is Err(MetadataLimit))
  assert_true(retain_completion_evidence(output, 10, 1) is Err(MetadataLimit))
}

///|
test "verified memory conversion preserves evidence without implying a retained handoff" {
  let owner = capture_fixture()
  let live = Ref(true)
  let output = evidence_fixture(owner, live)
  let evidence = retain_completion_evidence(output, 10, 10).unwrap()
  let conversion = prepare_completed_output_import(
    output,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(conversion, output_fixture_row(owner, row)).unwrap()
  }
  let memory = finish_completed_output_import(conversion).unwrap()
  live.val = false
  assert_true(completed_output_available(memory))
  assert_true(retained_completion_matches_output(evidence, memory))
  assert_false(retained_completion_can_handoff(evidence, memory))
}
