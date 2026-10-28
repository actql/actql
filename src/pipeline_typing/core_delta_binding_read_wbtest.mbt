///|
fn original_delta_bindings_reference(
  b : Budget,
  source : @decode.Cursor,
  inputs : Array[(String, @carrier.Carrier)],
  names : Map[String, Target],
  delta_inputs : Array[DeltaEvidence],
  delta_contracts : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ],
) -> Unit raise Stop {
  spend(b, source, delta_contracts.length())
  for (input_name, field, contract) in delta_contracts {
    name(b, source, input_name)
    let index = match names.get(input_name) {
      Some(Input(i)) => i
      _ => fail(source, InvalidDeltaContractBinding)
    }
    let rows = match inputs[index].1 {
      @carrier.Relation(r) => r
      _ => fail(source, InvalidDeltaContractBinding)
    }
    guard @carrier.lookup(rows, field) is Present({ contract: Some(_), .. }) else {
      fail(source, InvalidDeltaContractBinding)
    }
    let key = @schema.reference_name(field)
    charge(b, source, key)
    if delta_inputs[index].fields.contains(key) {
      fail(source, InvalidDeltaContractBinding)
    }
    carrier_preflight(
      b,
      source,
      @carrier.graph_carrier(@graph_contract.graph(contract)),
    )
    delta_inputs[index].fields[key] = contract
  }
}

///|
fn delta_binding_fixture(
  bindings : Array[(String, @schema.FieldName, @graph_contract.CheckedContract)],
  field : @schema.FieldName,
  limits? : Limits = evidence_read_limits(),
) -> PipelineCoreRead {
  let carrier = @carrier.relation(
    @carrier.rows(
      [(field, Some(@contract.primitive(JsonType, nullable=false)))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=1000,
    ).unwrap(),
  )
  let read = begin_pipeline_core_read(
    evidence_read_cursor("[]"),
    [("a", carrier), ("b", carrier)],
    None,
    None,
    limits,
    None,
    None,
    bindings,
    [None, None],
    [None, None],
    [None, None],
    [CarrierInput(carrier), CarrierInput(carrier)],
    None,
  ).unwrap()
  while pipeline_core_read_phase(read) != DeltaContracts &&
        pipeline_core_read_phase(read) != Failed {
    let _ = advance_pipeline_core_read(read)
  }
  read
}

///|
fn original_binding_cost(
  q : @shape.CollectionConstructionExtent,
  text : Int64,
) -> Int64 {
  input_construction_bytes(q) + 2L * text
}

///|
test "original Delta bindings preserve qualified Unicode storage and charge old UTF16 backing on the same Map domain" {
  let contract = imported_graph_contract()
  let field = @schema.Qualified(Left, "deltá")
  let bindings = [("a", field, contract), ("b", field, contract)]
  let read = delta_binding_fixture(bindings, field)
  guard read.state is Reading(body) else { abort("binding Core expected") }
  let original_budget : Budget = {
    limits: body.b.limits,
    work: body.b.work,
    text: body.b.text,
    nodes: body.b.nodes,
    tokens: body.b.tokens,
  }
  let expected : Array[DeltaEvidence] = [empty_delta(), empty_delta()]
  original_delta_bindings_reference(
    original_budget,
    body.source,
    body.inputs,
    body.names,
    expected,
    bindings,
  ) catch {
    Stop(_) => abort("original binding must admit")
  }
  let mut old = core_delta_binding_holdings(body).unwrap()
  let mut work = pipeline_core_read_consumed_work(read).unwrap()
  let mut saw_old_text = false
  while pipeline_core_read_phase(read) == DeltaContracts {
    let quote = core_delta_binding_step_construction(body).unwrap()
    assert_eq(quote.replaced, old.extent)
    assert_eq(quote.replaced_utf16_units, old.owned_utf16_units)
    if quote.replaced_utf16_units > 0L {
      saw_old_text = true
    }
    let _ = advance_pipeline_core_read(read)
    assert_true(pipeline_core_read_phase(read) != Failed)
    let held = core_delta_binding_holdings(body).unwrap()
    assert_true(
      original_binding_cost(held.extent, held.owned_utf16_units) <=
      original_binding_cost(old.extent, old.owned_utf16_units) +
      original_binding_cost(quote.peak, quote.peak_utf16_units),
    )
    old = held
    let current = pipeline_core_read_consumed_work(read).unwrap()
    assert_true(current >= work)
    work = current
  }
  assert_true(saw_old_text)
  assert_true(pipeline_core_read_phase(read) == Steps)
  assert_eq(body.b.work, original_budget.work)
  assert_eq(body.b.text, original_budget.text)
  // "left."5 + "deltá"5 UTF16 units, independently counted for each Map.
  assert_eq(old.owned_utf16_units, 20L)
  assert_eq(body.delta_bound_name_headers, 2L)
  assert_true(body.delta_binding is None)
  assert_true(body.delta_binding_key is None)
  assert_true(body.delta_binding_old is None)
  assert_true(body.carrier_read is None)
  for i in 0..<2 {
    assert_true(
      physical_equal(
        body.delta_inputs.unwrap()[i].fields["left.deltá"],
        contract,
      ),
    )
    assert_true(physical_equal(expected[i].fields["left.deltá"], contract))
  }
  assert_false(
    physical_equal(
      body.delta_inputs.unwrap()[0].fields,
      body.delta_inputs.unwrap()[1].fields,
    ),
  )
}

///|
test "Delta binding refuses original duplicate missing and noncanonical names with known consumed work" {
  let contract = imported_graph_contract()
  let field = @schema.Unqualified("delta")
  for
    (bindings, kind) in [
      (
        [("a", field, contract), ("a", field, contract)],
        InvalidDeltaContractBinding,
      ),
      ([("missing", field, contract)], InvalidDeltaContractBinding),
      (
        [("a", @schema.Unqualified("absent"), contract)],
        InvalidDeltaContractBinding,
      ),
      ([("é", field, contract)], InvalidName("é")),
    ] {
    let read = delta_binding_fixture(bindings, field)
    guard read.state is Reading(body) else { abort("binding Core expected") }
    let original_budget : Budget = {
      limits: body.b.limits,
      work: body.b.work,
      text: body.b.text,
      nodes: body.b.nodes,
      tokens: body.b.tokens,
    }
    let expected = [empty_delta(), empty_delta()]
    let original = try {
      original_delta_bindings_reference(
        original_budget,
        body.source,
        body.inputs,
        body.names,
        expected,
        bindings,
      )
      None
    } catch {
      Stop(issue) => Some(issue)
    }
    while pipeline_core_read_phase(read) != Failed {
      let _ = advance_pipeline_core_read(read)
    }
    guard read.state is Rejected(failed, issue) else {
      abort("original refusal expected")
    }
    assert_eq(issue.kind, kind)
    assert_eq(issue.kind, original.unwrap().kind)
    assert_eq(failed.b.work, original_budget.work)
    assert_eq(failed.b.text, original_budget.text)
    assert_eq(
      pipeline_core_read_consumed_work(read),
      Some(failed.limits.max_work - failed.b.work),
    )
    clear_pipeline_core_read(read)
    assert_true(pipeline_core_read_consumed_work(read) is None)
  }
}

///|
test "Delta binding captures one original tuple before quoting and clears its original pending Carrier" {
  let contract = imported_graph_contract()
  let field = @schema.Qualified(Left, "deltá")
  let bindings = [("a", field, contract)]
  let read = delta_binding_fixture(bindings, field)
  guard read.state is Reading(body) else { abort("binding Core expected") }
  let _ = advance_pipeline_core_read(read)
  assert_true(body.delta_binding_step == Name)
  let work = pipeline_core_read_consumed_work(read)
  bindings[0] = (String::make(1000, 'b'), field, contract)
  assert_true(core_delta_binding_step_construction(body) is None)
  assert_true(advance_pipeline_core_read(read) == Failed)
  guard read.state is Rejected(_, issue) else {
    abort("changed original must refuse")
  }
  assert_eq(issue.kind, InvalidDeltaContractBinding)
  assert_eq(pipeline_core_read_consumed_work(read), work)
  let pending = delta_binding_fixture([("a", field, contract)], field)
  guard pending.state is Reading(original) else {
    abort("pending original expected")
  }
  while original.carrier_read is None {
    let _ = advance_pipeline_core_read(pending)
  }
  let child = original.carrier_read.unwrap()
  let _ = advance_pipeline_core_read(pending)
  let nested = child.contract.unwrap()
  clear_pipeline_core_read(pending)
  assert_true(child.state is Cleared)
  assert_true(nested.state is Cleared)
  assert_true(original.delta_binding_key is None)
  assert_true(original.delta_binding_old is None)
  assert_true(original.delta_binding is None)
  assert_eq(original.delta_inputs.unwrap()[0].fields.length(), 0)
  assert_true(pipeline_core_read_consumed_work(pending) is None)
}

///|
test "public Pipeline quote forwards actual retained UTF16 units through the original read and never zeroes old backing" {
  let contract = imported_graph_contract()
  let field = @schema.Qualified(Left, "deltá")
  let rows = @carrier.relation(
    @carrier.rows(
      [(field, Some(@contract.primitive(JsonType, nullable=false)))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=1000,
    ).unwrap(),
  )
  let read = begin_pipeline_evidence_read(
    evidence_read_cursor("[]"),
    [("a", CarrierInput(rows))],
    None,
    None,
    evidence_read_limits(),
    delta_contracts=[("a", field, contract)],
  ).unwrap()
  while pipeline_evidence_read_phase(read) != CoreDeltaContracts {
    let _ = advance_pipeline_evidence_read(read)
  }
  let mut seen = false
  while pipeline_evidence_read_phase(read) == CoreDeltaContracts {
    let q = pipeline_evidence_read_step_construction(read).unwrap()
    let _ = advance_pipeline_evidence_read(read)
    assert_true(pipeline_evidence_read_phase(read) != Failed)
    let held = pipeline_evidence_read_step_holdings(read, CoreDeltaContracts).unwrap()
    if q.replaced_utf16_units > 0L {
      assert_eq(q.replaced_utf16_units, 10L)
      seen = true
    }
    assert_true(
      original_binding_cost(held.extent, held.owned_utf16_units) <=
      original_binding_cost(q.replaced, q.replaced_utf16_units) +
      original_binding_cost(q.peak, q.peak_utf16_units),
    )
  }
  assert_true(seen)
  assert_eq(pipeline_evidence_read_phase(read), CoreSteps)
  clear_pipeline_evidence_read(read)
  assert_eq(pipeline_evidence_read_phase(read), Cleared)
}
