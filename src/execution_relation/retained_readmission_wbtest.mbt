///|
fn[P] retained_readmission_test_attempt(
  preparation : CompletionPreparation,
  expected : RetainedCompletionDescriptor,
  metadata_entries : Int,
  name_bytes : Int,
  verify : (P) -> RetainedOutputMaterial?,
) -> Result[TrustedRetainedReadmission[P], TrustedOutputIssue] {
  prepare_retained_readmission_facts(preparation, expected, expected.rows, {
    producer_inputs: Some(metadata_entries),
    schema_columns: Some(metadata_entries),
    name_bytes: Some(name_bytes),
  }).bind(facts => {
    prepare_trusted_retained_readmission(preparation, expected, facts, verify)
  })
}

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
  retained_readmission_test_attempt(
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
  let altered = retained_readmission_test_attempt(
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
    retained_readmission_test_attempt(
      content_read_preparation(owner),
      { ..expected, input_count: expected.input_count + 1, },
      100,
      10000,
      fn(_ : ReadmissionProof) { None },
    )
    is Err(ForeignOutput),
  )
}

///|
test "retained metadata facts bind exact preparation and descriptor without calling custody" {
  let owner = capture_fixture()
  let evidence = retain_completion_evidence(
    evidence_fixture(owner, Ref(true)),
    10,
    10,
  ).unwrap()
  let expected = retained_completion_descriptor(evidence)
  let prepared = content_read_preparation(owner)
  let policy : RetainedReadmissionMetadataPolicy = {
    producer_inputs: None,
    schema_columns: None,
    name_bytes: Some(10000),
  }
  let facts = prepare_retained_readmission_facts(
    prepared,
    expected,
    expected.rows,
    policy,
  ).unwrap()
  assert_eq(retained_readmission_rows(facts), expected.rows)
  assert_eq(retained_readmission_producer_inputs(facts), expected.input_count)
  assert_eq(retained_readmission_schema_columns(facts), expected.columns)
  let calls = Ref(0)
  let verify = fn(_ : Unit) {
    calls.val += 1
    None
  }
  let other = content_read_preparation(owner)
  assert_true(
    prepare_trusted_retained_readmission(other, expected, facts, verify)
    is Err(ForeignOutput),
  )
  assert_true(
    prepare_trusted_retained_readmission(
      prepared,
      { ..expected, },
      facts,
      verify,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    prepare_retained_readmission_facts(
      prepared,
      { ..expected, columns: expected.columns + 1, },
      expected.rows,
      policy,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    prepare_retained_readmission_facts(
      prepared,
      { ..expected, registry_cid: "sha256:" + "f".repeat(64), },
      expected.rows,
      policy,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    prepare_retained_readmission_facts(
      prepared,
      expected,
      expected.rows + 1,
      policy,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    prepare_retained_readmission_facts(prepared, expected, expected.rows, {
      producer_inputs: None,
      schema_columns: Some(0),
      name_bytes: Some(10000),
    })
    is Err(Limit),
  )
  assert_true(
    prepare_retained_readmission_facts(prepared, expected, expected.rows, {
      producer_inputs: None,
      schema_columns: None,
      name_bytes: Some(0),
    })
    is Err(Limit),
  )
  // Equal canonical facts can be issued afresh for a recovered preparation.
  // The old nominal object itself never upgrades another receiving entrance.
  let recovered = prepare_retained_readmission_facts(
    other,
    expected,
    expected.rows,
    policy,
  ).unwrap()
  assert_true(
    prepare_trusted_retained_readmission(other, expected, recovered, verify)
    is Ok(_),
  )
  assert_eq(calls.val, 0)
}

///|
test "retained logical Relation readmission verifies typed order and schema on the receiving port" {
  let owner = capture_fixture()
  let body = "{\"sort\":\"relation\",\"value\":[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]}"
  let wire = row_wire_limits()
  let schema_limits = schema_identity_limits()
  let decode = retained_row_test_limits()
  let values = stream_value_limits()
  let rows = read_retained_logical_relation(
    owner,
    Step(1),
    input_cursor(body),
    2,
    decode,
    values,
    () => true,
  ).unwrap()
  let schema = identify_relation_schema(
    admitted_output_schema(rows),
    schema_limits,
  ).unwrap()
  let expected : RetainedLogicalRelationIdentity = {
    relation_cid: "sha256:" + @sha.text_hex(body).unwrap(),
    relation_bytes: @utf8.encode(body).length(),
    schema_cid: relation_schema_cid(schema),
    schema_bytes: relation_schema_usage(schema).0,
    rows: 2,
  }
  let preparation = content_read_preparation(owner)
  let original = Ref(true)
  let verified = fn(proof : Ref[Bool]) {
    if physical_equal(proof, original) && original.val {
      Some(rows)
    } else {
      None
    }
  }
  let spent = Ref(0)
  let work = fn(count : Int) {
    spent.val += count
    true
  }
  let restored = readmit_trusted_retained_relation(
    preparation,
    Step(1),
    expected,
    wire,
    schema_limits,
    work,
    original,
    verified,
  ).unwrap()
  assert_true(spent.val > 0)
  let one_short = Ref(spent.val - 1)
  assert_true(
    readmit_trusted_retained_relation(
      preparation,
      Step(1),
      expected,
      wire,
      schema_limits,
      count => {
        if one_short.val < count {
          false
        } else {
          one_short.val -= count
          true
        }
      },
      original,
      verified,
    )
    is Err(Limit),
  )
  assert_true(completed_output_matches_port(restored, owner, Step(1)))
  assert_true(restored.completion.readmitted)
  assert_false(completed_output_matches_inputs(restored, []))
  assert_true(completed_cell(restored, 1, 1) is Some(Text("😀")))
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let bound = bind_completed_input(receiver, 0, owner, restored).unwrap()
  let read = prepare_producer_read(receiver, bound, 1000, 10000).unwrap()
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
  let next = completed_output(consumer, Step(0)).unwrap()
  assert_true(completed_cell(next, 0, 0) is Some(Number(1)))
  assert_true(completed_cell(next, 1, 0) is Some(Number(2)))
  let reversed = "{\"sort\":\"relation\",\"value\":[{\"n\":2,\"s\":\"😀\"},{\"n\":1,\"s\":\"é\"}]}"
  let replacement = {
    ..expected,
    relation_cid: "sha256:" + @sha.text_hex(reversed).unwrap(),
  }
  assert_true(
    readmit_trusted_retained_relation(
      preparation,
      Step(1),
      replacement,
      wire,
      schema_limits,
      work,
      original,
      verified,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    readmit_trusted_retained_relation(
      preparation,
      Step(1),
      { ..expected, schema_cid: expected.relation_cid, },
      wire,
      schema_limits,
      work,
      original,
      verified,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    readmit_trusted_retained_relation(
      content_read_preparation(capture_fixture()),
      Step(1),
      expected,
      wire,
      schema_limits,
      work,
      original,
      verified,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    readmit_trusted_retained_relation(
      preparation,
      Step(1),
      expected,
      wire,
      schema_limits,
      work,
      Ref(true),
      verified,
    )
    is Err(Unverified),
  )
  assert_true(
    readmit_trusted_retained_relation(
      preparation,
      Step(1),
      expected,
      wire,
      schema_limits,
      _ => false,
      original,
      verified,
    )
    is Err(Limit),
  )
  original.val = false
  assert_true(completed_cell(restored, 0, 0) is None)
  assert_false(producer_read_available(read))
}
