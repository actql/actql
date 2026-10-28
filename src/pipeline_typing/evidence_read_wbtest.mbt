///|
fn evidence_read_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn evidence_read_limits() -> Limits {
  {
    max_steps: 100,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }
}

///|
fn evidence_read_carrier() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
        max_fields=1,
        max_name_bytes=2,
      ).unwrap(),
    ),
  )
}

///|
test "original pipeline evidence read preserves borrowed inputs and actual carrier holdings across returns" {
  let carrier = evidence_read_carrier()
  let key = @evidence.declare_primary_key(
    evidence_read_cursor("[\"id\"]"),
    carrier,
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  let keys = @evidence.singleton_key(key)
  let inputs : Array[(String, InputContract)] = [
    ("plain", CarrierInput(carrier)),
    ("keyed", KeyedInput(key)),
    ("candidates", CandidateKeysInput(keys)),
  ]
  let source = evidence_read_cursor("[{\"select\":[\"id\"]}]")
  let from = Some(evidence_read_cursor("\"candidates\""))
  let read = begin_pipeline_evidence_read(
    source,
    inputs,
    None,
    from,
    evidence_read_limits(),
  ).unwrap()
  assert_true(take_pipeline_evidence_read(read) is None)
  guard read.state is Reading(original) else { abort("original body expected") }
  assert_true(physical_equal(original.inputs, inputs))
  assert_true(physical_equal(original.source, source))
  assert_true(physical_equal(original.from, from))
  let quote = pipeline_evidence_read_step_construction(read).unwrap()
  assert_eq(advance_pipeline_evidence_read(read), Keys)
  let held = pipeline_evidence_read_carriers_retained_extent(read).unwrap()
  assert_true(held.record_headers <= quote.peak.record_headers)
  assert_true(held.reference_slots <= quote.peak.reference_slots)
  assert_true(held.scalar_words <= quote.peak.scalar_words)
  assert_eq(original.carrier_wrappers, 2)
  guard original.step is Keys(carriers) else { abort("same carriers expected") }
  assert_eq(carriers.length(), 3)
  assert_true(physical_equal(carriers[0].1, carrier))
  assert_true(
    physical_equal(
      @carrier.relation_rows(carriers[1].1).unwrap(),
      @evidence.keyed_records(key),
    ),
  )
  assert_true(
    physical_equal(
      @carrier.relation_rows(carriers[2].1).unwrap(),
      @evidence.key_set_records(keys),
    ),
  )
  assert_eq(pipeline_evidence_read_owned_work(read), Some(0))
  assert_true(pipeline_evidence_read_step_construction(read) is Some(_))
  assert_eq(advance_pipeline_evidence_read(read), Rankings)
  guard original.step is Rankings(same, retained_keys) else {
    abort("keys expected")
  }
  assert_true(physical_equal(same, carriers))
  assert_true(physical_equal(retained_keys[2].unwrap(), keys))
  assert_eq(advance_pipeline_evidence_read(read), Core)
  assert_eq(advance_pipeline_evidence_read(read), CoreInputs)
  while pipeline_evidence_read_phase(read) == CoreInputs {
    let _ = advance_pipeline_evidence_read(read)
  }
  assert_eq(pipeline_evidence_read_phase(read), CoreParameters)
  while pipeline_evidence_read_phase(read) == CoreParameters {
    let _ = advance_pipeline_evidence_read(read)
  }
  assert_eq(pipeline_evidence_read_phase(read), CoreImportedEvidence)
  while pipeline_evidence_read_phase(read) == CoreImportedEvidence {
    let _ = advance_pipeline_evidence_read(read)
  }
  assert_eq(pipeline_evidence_read_phase(read), CoreDeltaContracts)
  for expected in [CoreSteps, CoreFinalEvidence, Complete] {
    assert_eq(advance_pipeline_evidence_read(read), expected)
  }
  let checked = take_pipeline_evidence_read(read).unwrap().unwrap()
  assert_eq(step_count(checked), 1)
  assert_eq(current(checked), Some(Step(0)))
  assert_eq(
    @evidence.key_witness_count(candidate_keys(checked, Step(0)).unwrap()),
    1,
  )
  assert_true(physical_equal(checked.source, source))
  assert_eq(checked.input_contracts.length(), 3)
  guard checked.input_contracts[2] is CandidateKeysInput(original_keys) else {
    abort("original input expected")
  }
  assert_true(physical_equal(original_keys, keys))
  assert_true(take_pipeline_evidence_read(read) is None)
  assert_eq(advance_pipeline_evidence_read(read), Taken)
  clear_pipeline_evidence_read(read)
  assert_eq(pipeline_evidence_read_phase(read), Taken)
  let used = checked.usage
  let exact = {
    ..evidence_read_limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_tokens: used.tokens,
    max_text_bytes: used.text_bytes,
  }
  assert_true(check_with_evidence(source, inputs, None, from, exact) is Ok(_))
  assert_true(
    check_with_evidence(source, inputs, None, from, {
      ..exact,
      max_work: exact.max_work - 1,
    })
    is Err(_),
  )
}

///|
test "original pipeline evidence failure stays typed unknown work and clear retires every pending phase" {
  let source = evidence_read_cursor("{}")
  let read = begin_pipeline_evidence_read(
    source,
    [],
    None,
    None,
    evidence_read_limits(),
  ).unwrap()
  assert_eq(advance_pipeline_evidence_read(read), Keys)
  assert_eq(advance_pipeline_evidence_read(read), Rankings)
  assert_eq(advance_pipeline_evidence_read(read), Core)
  assert_eq(advance_pipeline_evidence_read(read), Failed)
  assert_true(pipeline_evidence_read_owned_work(read) is None)
  assert_eq(advance_pipeline_evidence_read(read), Failed)
  guard take_pipeline_evidence_read(read) is Some(Err(issue)) else {
    abort("typed original issue expected")
  }
  assert_eq(issue.kind, InvalidBody)
  assert_true(physical_equal(issue.source, source))
  for steps in 0..<4 {
    let read = begin_pipeline_evidence_read(
      evidence_read_cursor("[]"),
      [],
      None,
      None,
      evidence_read_limits(),
    ).unwrap()
    for _ in 0..<steps {
      let _ = advance_pipeline_evidence_read(read)
    }
    assert_true(take_pipeline_evidence_read(read) is None)
    clear_pipeline_evidence_read(read)
    assert_eq(advance_pipeline_evidence_read(read), Cleared)
    assert_true(pipeline_evidence_read_owned_work(read) is None)
    assert_true(take_pipeline_evidence_read(read) is None)
  }
  assert_true(
    begin_pipeline_evidence_read(source, [], None, None, {
      ..evidence_read_limits(),
      max_work: -1,
    })
    is Err({ kind: InvalidLimits, .. }),
  )
}
