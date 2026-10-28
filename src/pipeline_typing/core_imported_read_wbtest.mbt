///|
/// Independent current Graph contract; no diff result or product-emitted bytes.
fn imported_graph_contract() -> @graph_contract.CheckedContract raise {
  let body =
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[],"identity_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":[]},"name":"N","properties":{}}],"value_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","version":"actql-graph-contract/0.1"}
  let contract = @graph_contract.read_cursor(evidence_read_cursor(body), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  // Node crypto SHA-256 of the authored canonical body, independently computed.
  assert_eq(
    @graph_contract.cid(contract),
    "sha256:183b5a03d53a1edef82907958e3a40620703dde16b01f617b82a7ecf4ba0f284",
  )
  contract
}

///|
fn imported_delta(
  b : Budget,
  source : @decode.Cursor,
  inputs : Array[ProducedInput?],
) -> Array[DeltaEvidence] raise Stop {
  spend(b, source, inputs.length())
  inputs.map(input => {
    let result = empty_delta()
    if input is Some(producer) {
      spend(b, source, producer.delta.fields.length())
      for field, contract in producer.delta.fields {
        charge(b, source, field)
        carrier_preflight(
          b,
          source,
          @carrier.graph_carrier(@graph_contract.graph(contract)),
        )
        // Explicit bindings can extend this map, never mutate the producer.
        result.fields[field] = contract
      }
    }
    result
  })
}

///|
fn original_imported_reference(
  b : Budget,
  source : @decode.Cursor,
  produced_inputs : Array[ProducedInput?],
) -> (
  Array[@evidence.LiteralDomains?],
  Array[@evidence.LiteralDomains?],
  Array[DeltaEvidence],
  Array[DeltaEvidence],
) raise Stop {
  spend(b, source, produced_inputs.length())
  let literal_inputs = produced_inputs.map(input => input.bind(v => v.literals))
  for domains in literal_inputs {
    if domains is Some(domains) {
      let _ = literal_result(
        b,
        source,
        @evidence.admit_literal_domains(source, domains, {
          max_work: b.work,
          max_name_bytes: b.text,
        }),
      )
    }
  }
  let literal_steps : Array[@evidence.LiteralDomains?] = []
  let delta_inputs = imported_delta(b, source, produced_inputs)
  let delta_steps : Array[DeltaEvidence] = []
  (literal_inputs, literal_steps, delta_inputs, delta_steps)
}

///|
fn imported_original_producer() -> ProducedInput raise {
  let rows = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [
          (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
          (Unqualified("delta"), @contract.primitive(JsonType, nullable=false)),
        ],
        max_fields=2,
        max_name_bytes=7,
      ).unwrap(),
    ),
  )
  let original = check_carriers(
    evidence_read_cursor("[{\"derive\":{\"tag\":\"'é'\"}}]"),
    [("rows", rows)],
    None,
    None,
    evidence_read_limits(),
    delta_contracts=[("rows", Unqualified("delta"), imported_graph_contract())],
  ).unwrap()
  produced_input(original, Step(0)).unwrap()
}

///|
fn imported_original_core(
  producer : ProducedInput,
  limits : Limits,
) -> PipelineCoreRead {
  let read = begin_pipeline_core_read(
    evidence_read_cursor("[]"),
    [("a", producer.carrier), ("b", producer.carrier)],
    None,
    Some(evidence_read_cursor("\"a\"")),
    limits,
    None,
    None,
    [],
    [None, None],
    [None, None],
    [Some(producer), Some(producer)],
    [ProducedInput(producer), ProducedInput(producer)],
    None,
  ).unwrap()
  while pipeline_core_read_phase(read) == Inputs ||
        pipeline_core_read_phase(read) == Parameters {
    let _ = advance_pipeline_core_read(read)
  }
  read
}

///|
test "same original imported literals and delta maps retain producer identity Budget and actual old-new storage" {
  let producer = imported_original_producer()
  let read = imported_original_core(producer, evidence_read_limits())
  guard read.state is Reading(body) else {
    abort("original imported Core expected")
  }
  assert_true(body.phase == ImportedEvidence)
  let budget = body.b
  let expected_budget : Budget = {
    limits: budget.limits,
    work: budget.work,
    text: budget.text,
    nodes: budget.nodes,
    tokens: budget.tokens,
  }
  let expected = original_imported_reference(
    expected_budget,
    body.source,
    body.produced_inputs,
  ) catch {
    Stop(_) => abort("original imported reference must admit")
  }
  let mut old = core_imported_retained(body).unwrap()
  let mut work = pipeline_core_read_consumed_work(read).unwrap()
  let mut steps = 0
  while pipeline_core_read_phase(read) == ImportedEvidence {
    let quote = core_imported_step_construction(body).unwrap()
    assert_eq(quote.replaced, old)
    let _ = advance_pipeline_core_read(read)
    assert_true(pipeline_core_read_phase(read) != Failed)
    let held = core_imported_retained(body).unwrap()
    assert_true(
      held.record_headers <= old.record_headers + quote.peak.record_headers,
    )
    assert_true(
      held.reference_slots <= old.reference_slots + quote.peak.reference_slots,
    )
    assert_true(held.scalar_words <= old.scalar_words + quote.peak.scalar_words)
    old = held
    let consumed = pipeline_core_read_consumed_work(read).unwrap()
    assert_true(consumed >= work)
    work = consumed
    assert_true(physical_equal(body.b, budget))
    steps += 1
  }
  assert_true(steps > 20)
  assert_true(body.phase == DeltaContracts)
  assert_eq(body.b.work, expected_budget.work)
  assert_eq(body.b.text, expected_budget.text)
  assert_eq(body.literal_inputs.unwrap().length(), expected.0.length())
  assert_eq(body.delta_inputs.unwrap().length(), expected.2.length())
  for i in 0..<2 {
    assert_true(
      physical_equal(
        body.literal_inputs.unwrap()[i].unwrap(),
        producer.literals.unwrap(),
      ),
    )
    let imported = body.delta_inputs.unwrap()[i]
    assert_false(physical_equal(imported.fields, producer.delta.fields))
    assert_true(
      physical_equal(imported.fields["delta"], producer.delta.fields["delta"]),
    )
  }
  assert_false(
    physical_equal(
      body.delta_inputs.unwrap()[0].fields,
      body.delta_inputs.unwrap()[1].fields,
    ),
  )
  assert_eq(producer.delta.fields.length(), 1)
  assert_true(body.literal_read is None)
  assert_true(body.carrier_read is None)
  assert_true(body.delta_iterator is None)
  assert_true(body.delta_field is None)
  assert_true(body.delta_pending is None)
}

///|
test "failed imported literal charges its actual nested prefix once and retains original typed refusal until clear" {
  let producer = imported_original_producer()
  let source_limits = evidence_read_limits()
  let complete_prefix = imported_original_core(producer, source_limits)
  let prefix = pipeline_core_read_consumed_work(complete_prefix).unwrap()
  clear_pipeline_core_read(complete_prefix)
  // Two original import slots, then one field charge before its value refuses.
  let limits = { ..source_limits, max_work: prefix + 3, }
  let read = imported_original_core(producer, limits)
  while pipeline_core_read_phase(read) != Failed {
    let _ = advance_pipeline_core_read(read)
  }
  guard read.state is Rejected(body, issue) else {
    abort("original literal refusal expected")
  }
  assert_eq(issue.kind, KeyEvidence(@evidence.LimitExceeded))
  let nested = body.literal_read.unwrap()
  assert_eq(@evidence.literal_domains_read_consumed_work(nested), Some(1))
  assert_eq(body.b.work, 1)
  assert_eq(pipeline_core_read_consumed_work(read), Some(limits.max_work))
  assert_true(body.delta_inputs is None)
  assert_true(body.literal_steps is None)
  assert_true(take_pipeline_core_read(read) is Some(Err(_)))
  assert_true(pipeline_core_read_consumed_work(read) is None)
  // A distinct original pending read retains and clears its exact child.
  let stopped = imported_original_core(producer, source_limits)
  guard stopped.state is Reading(pending) else {
    abort("pending Core expected")
  }
  while pending.literal_read is None {
    let _ = advance_pipeline_core_read(stopped)
  }
  let child = pending.literal_read.unwrap()
  clear_pipeline_core_read(stopped)
  assert_eq(@evidence.literal_domains_read_phase(child), @evidence.Cleared)
  assert_true(pipeline_core_read_consumed_work(stopped) is None)
}
