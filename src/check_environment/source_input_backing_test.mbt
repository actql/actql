///|
fn evidence_backing_view(name : String) -> SourceViewCarrier raise {
  let body = record_body()
  guard body is Object(record) && record["fields"] is Object(fields) else {
    abort("original Relation fixture expected")
  }
  let id = fields["id"]
  fields.remove("id") |> ignore
  fields[name] = id
  let facts : Json = {
    "relation_keys": { "candidate_keys": [[name]] },
    "relation_scores": Json::object(
      Map([
        (
          name,
          {
            "domain": "Relevance",
            "normalization": "Identity",
            "range": [0, 1],
          },
        ),
      ]),
    ),
  }
  let modes = carrier_modes(body, "relation", facts=Some(facts))
  let schemas = check_carrier_schemas(modes, carrier_limits()).unwrap()
  let environment = contract_registry_environment(
    catalog_registry(
      reference_contents(
        data_policy_references(
          value_contract_policies(
            source_view_shape_values(read_mode_shapes(modes)),
          ),
        ),
      ),
    ),
  )
  source_view_carrier(schemas, member_at(environment, SourceViews, 0).unwrap()).unwrap()
}

///|
test "original Source key and ranking constructors fit their actual selected inventories and retained buffers" {
  let name = "é".repeat(128)
  let view = evidence_backing_view(name)
  let original = source_view_relation_keys(view).unwrap()
  assert_eq(
    source_relation_key_construction_geometry(original, 0),
    Some((1, 128)),
  )
  assert_true(source_relation_key_construction_geometry(original, -1) is None)
  let q = @evidence.source_view_key_construction_inventory(view).unwrap()
  assert_eq(q.inspection_work, 4L)
  let value = @evidence.source_view_keys(view, {
      max_work: 100000,
      max_name_bytes: 100000,
    })
    .unwrap()
    .unwrap()
  let actual = @evidence.source_key_set_retained_construction(value.keys).unwrap()
  assert_true(q.retained.record_headers >= actual.extent.record_headers)
  assert_true(q.retained.reference_slots >= actual.extent.reference_slots)
  assert_true(q.retained.scalar_words >= actual.extent.scalar_words)
  assert_true(q.scratch_utf16_units > 128L)
  assert_eq(actual.owned_utf16_units, 0L)
  assert_eq(actual.observation_work, 3L)
  assert_eq(@evidence.key_witness_count(value.keys), 1)
  let witness = @evidence.key_witness_at(value.keys, 0).unwrap()
  assert_eq(@evidence.key_field_at(witness, 0).unwrap().name, Unqualified(name))
  assert_true(
    physical_equal(
      @evidence.key_source(witness),
      source_relation_key_at(original, 0).unwrap(),
    ),
  )
  let q = @evidence.source_view_ranking_construction_inventory(view).unwrap()
  let value = @evidence.source_view_scores(view, {
      max_work: 100000,
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_depth: 100,
    })
    .unwrap()
    .unwrap()
  let actual = @evidence.source_ranking_retained_construction(value.input).unwrap()
  assert_true(q.retained.record_headers >= actual.extent.record_headers)
  assert_true(q.retained.reference_slots >= actual.extent.reference_slots)
  assert_true(q.retained.scalar_words >= actual.extent.scalar_words)
  assert_eq(actual.owned_utf16_units, 130L)
  assert_eq(q.retained_utf16_units, actual.owned_utf16_units)
  assert_eq(actual.observation_work, 2L)
  assert_true(
    @evidence.ranking_score_at(value.input, Unqualified(name)) is Some(_),
  )
}

///|
test "repeated original Source projections sum held evidence but reuse sequential scratch without changing budgets" {
  let name = "é".repeat(128)
  let view = evidence_backing_view(name)
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"evidence\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"first\":{\"connector\":\"fixture\",\"resource\":\"rows\",\"request\":{}},\"second\":{\"connector\":\"fixture\",\"resource\":\"rows\",\"request\":{}}},\"steps\":[],\"results\":{\"out\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
  ).unwrap()
  let stage = @syntax.stages(program)[0]
  let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
  let inputs = @decode.open_object(@decode.required(body, "inputs").unwrap()).unwrap()
  let source = @decode.required(body, "steps").unwrap()
  let one = @pipeline.begin_pipeline_evidence_read(
    source,
    [
      (
        "first",
        @pipeline.SourceViewInput(
          stage,
          "first",
          @decode.required(inputs, "first").unwrap(),
          view,
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let two = @pipeline.begin_pipeline_evidence_read(
    source,
    [
      (
        "first",
        @pipeline.SourceViewInput(
          stage,
          "first",
          @decode.required(inputs, "first").unwrap(),
          view,
        ),
      ),
      (
        "second",
        @pipeline.SourceViewInput(
          stage,
          "second",
          @decode.required(inputs, "second").unwrap(),
          view,
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  assert_eq(@pipeline.advance_pipeline_evidence_read(one), Keys)
  assert_eq(@pipeline.advance_pipeline_evidence_read(two), Keys)
  let a = @pipeline.pipeline_evidence_read_step_construction(one).unwrap()
  let b = @pipeline.pipeline_evidence_read_step_construction(two).unwrap()
  assert_eq(a.peak_utf16_units, b.peak_utf16_units)
  assert_eq(b.inspection_work, 2L * a.inspection_work)
  assert_true(b.peak.reference_slots > a.peak.reference_slots)
  assert_eq(@pipeline.advance_pipeline_evidence_read(two), Rankings)
  let held = @pipeline.pipeline_evidence_read_step_holdings(two).unwrap()
  assert_true(held.extent.record_headers <= b.peak.record_headers)
  assert_true(held.extent.reference_slots <= b.peak.reference_slots)
  assert_eq(held.owned_utf16_units, 0L)
  let a = @pipeline.pipeline_evidence_read_step_construction(one).unwrap()
  // One is still at Keys. Continue its original call before comparing ranking.
  let _ = a
  assert_eq(@pipeline.advance_pipeline_evidence_read(one), Rankings)
  let a = @pipeline.pipeline_evidence_read_step_construction(one).unwrap()
  let b = @pipeline.pipeline_evidence_read_step_construction(two).unwrap()
  let original = @evidence.source_view_ranking_construction_inventory(view).unwrap()
  assert_eq(
    b.peak_utf16_units - a.peak_utf16_units,
    original.retained_utf16_units,
  )
  assert_eq(@pipeline.advance_pipeline_evidence_read(two), Core)
  let held = @pipeline.pipeline_evidence_read_step_holdings(two).unwrap()
  assert_eq(held.owned_utf16_units, 2L * original.retained_utf16_units)
  @pipeline.clear_pipeline_evidence_read(one)
  @pipeline.clear_pipeline_evidence_read(two)
  assert_eq(@pipeline.advance_pipeline_evidence_read(two), Cleared)
}
