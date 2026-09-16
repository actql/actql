///|
priv struct ReadmissionProof {
  evidence : RetainedCompletionEvidence
  material : RetainedOutputMaterial
}

///|
fn readmission_material(
  owner : @lower.BoundPrepared,
  descriptor : RetainedCompletionDescriptor,
  live : Ref[Bool],
) -> RetainedOutputMaterial raise {
  let read = prepare_retained_content_read(
    content_read_preparation(owner),
    descriptor,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_retained_content_read(read, row, content_read_limits()).unwrap()
  }
  retained_output_material(
    retain_admitted_output_stream(
      finish_retained_content_read(read).unwrap(),
      (),
      fn() { live.val },
    ),
  )
}

///|
fn readmission_port(
  owner : @lower.BoundPrepared,
  evidence : RetainedCompletionEvidence,
  material : RetainedOutputMaterial,
  permitted : Ref[Bool],
) -> TrustedRetainedReadmission[ReadmissionProof] raise {
  prepare_trusted_retained_readmission(
    content_read_preparation(owner),
    retained_completion_descriptor(evidence),
    100,
    10000,
    fn(proof : ReadmissionProof) {
      // Test-only installed custody verifier: exact genuine saved evidence and
      // exact separately revalidated material, not a digest/Boolean assertion.
      if permitted.val &&
        physical_equal(proof.evidence, evidence) &&
        physical_equal(proof.material, material) {
        Some(material)
      } else {
        None
      }
    },
  ).unwrap()
}

///|
test "retained readmission preserves completed facts without requiring live original inputs" {
  let old_live = Ref(true)
  let original = evidence_fixture(capture_fixture(), old_live)
  let evidence = retain_completion_evidence(original, 10, 10).unwrap()
  old_live.val = false
  let owner = capture_fixture()
  let live = Ref(true)
  let material = readmission_material(
    owner,
    retained_completion_descriptor(evidence),
    live,
  )
  let permitted = Ref(true)
  let port = readmission_port(owner, evidence, material, permitted)
  let output = readmit_trusted_retained_output(port, { evidence, material, }).unwrap()
  assert_true(completed_output_matches_port(output, owner, Step(1)))
  assert_false(completed_has_cell_access(output))
  assert_false(completed_output_matches_inputs(output, []))
  assert_true(
    readmit_trusted_retained_output(port, { evidence, material, })
    is Err(Unverified),
  )
  let converted = prepare_completed_output_import(
    output,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(converted, output_fixture_row(owner, row)).unwrap()
  }
  let memory = finish_completed_output_import(converted).unwrap()
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, memory).unwrap(),
    1000,
    10000,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let consumer = execute_fixed_producer_input(
    generated,
    read,
    compute_test_limits(),
  ).unwrap()
  live.val = false
  assert_false(completed_output_available(output))
  assert_true(completed_output_available(memory))
  assert_false(completed_output_matches_inputs(memory, []))
  permitted.val = false
  assert_false(completed_output_available(memory))
  assert_false(producer_read_available(read))
  let result = completed_output(consumer, Step(0)).unwrap()
  assert_true(completed_cell(result, 0, 0) is Some(Number(1)))
  assert_true(completed_cell(result, 1, 0) is Some(Number(2)))
}

///|
test "equal-content foreign completion evidence and revoked permit cannot readmit" {
  let evidence = retain_completion_evidence(
    evidence_fixture(capture_fixture(), Ref(true)),
    10,
    10,
  ).unwrap()
  let foreign = retain_completion_evidence(
    evidence_fixture(capture_fixture(), Ref(true)),
    10,
    10,
  ).unwrap()
  assert_eq(
    retained_completion_descriptor(evidence),
    retained_completion_descriptor(foreign),
  )
  let owner = capture_fixture()
  let material = readmission_material(
    owner,
    retained_completion_descriptor(evidence),
    Ref(true),
  )
  let port = readmission_port(owner, evidence, material, Ref(true))
  assert_true(
    readmit_trusted_retained_output(port, { evidence: foreign, material, })
    is Err(Unverified),
  )
  assert_true(
    readmit_trusted_retained_output(port, { evidence, material, })
    is Err(Unverified),
  )
  let denied = readmission_port(owner, evidence, material, Ref(false))
  assert_true(
    readmit_trusted_retained_output(denied, { evidence, material, })
    is Err(Unverified),
  )
}

///|
test "readmission verifies owner and content independently of installed custody proof" {
  let evidence = retain_completion_evidence(
    evidence_fixture(capture_fixture(), Ref(true)),
    10,
    10,
  ).unwrap()
  let owner = capture_fixture()
  let foreign_material = readmission_material(
    capture_fixture(),
    retained_completion_descriptor(evidence),
    Ref(true),
  )
  let port = readmission_port(owner, evidence, foreign_material, Ref(true))
  assert_true(
    readmit_trusted_retained_output(port, {
      evidence,
      material: foreign_material,
    })
    is Err(ForeignOutput),
  )
  let material = readmission_material(
    owner,
    retained_completion_descriptor(evidence),
    Ref(true),
  )
  let expected = retained_completion_descriptor(evidence)
  let altered = prepare_trusted_retained_readmission(
    content_read_preparation(owner),
    { ..expected, rows_cid: "not-the-retained-content", },
    100,
    10000,
    fn(proof : ReadmissionProof) {
      if physical_equal(proof.material, material) &&
        physical_equal(proof.evidence, evidence) {
        Some(material)
      } else {
        None
      }
    },
  ).unwrap()
  assert_true(
    readmit_trusted_retained_output(altered, { evidence, material, })
    is Err(ForeignOutput),
  )
}

///|
test "readmission requires live independent holding and rejects wrong output contract" {
  let evidence = retain_completion_evidence(
    evidence_fixture(capture_fixture(), Ref(true)),
    10,
    10,
  ).unwrap()
  let owner = capture_fixture()
  let live = Ref(true)
  let material = readmission_material(
    owner,
    retained_completion_descriptor(evidence),
    live,
  )
  let port = readmission_port(owner, evidence, material, Ref(true))
  live.val = false
  assert_true(
    readmit_trusted_retained_output(port, { evidence, material, })
    is Err(Unverified),
  )
  let expected = retained_completion_descriptor(evidence)
  assert_true(
    prepare_trusted_retained_readmission(
      content_read_preparation(owner),
      { ..expected, input_count: expected.input_count + 1, },
      100,
      10000,
      fn(_ : ReadmissionProof) { None },
    )
    is Err(ForeignOutput),
  )
}
