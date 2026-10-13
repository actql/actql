///|
fn check_acquisition_fixture(
  wire : String,
  cid : String,
  arity : Int,
  capacity_kind : Int,
) -> Unit raise {
  let catalog = fixture_catalog(wire, cid)
  for variant in 0..<12 {
    let base = "\"connector\":\"crm/main\",\"resource\":\"r\""
    let keys = "\"id\":1," + (if arity == 2 { "\"other\":2," } else { "" })
    let complete = "{" + base + ",\"request\":{" + keys + "\"tenant\":null}}"
    let right = match variant {
      1 => complete
      5 =>
        "{" +
        base +
        ",\"scan\":{\"mode\":\"snapshot\"},\"request\":{\"tenant\":null}}"
      6 => "{" + base + "}"
      7 => "{" + base + ",\"request\":{\"id\":1,\"tenant\":null}}"
      _ => "{" + base + ",\"request\":{\"tenant\":null}}"
    }
    let on = match variant {
      8 =>
        if arity == 2 {
          "[\"other\",\"id\",\"id\"]"
        } else {
          "[\"id\",\"id\"]"
        }
      9 =>
        "[{\"left\":\"extra\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}" +
        (if arity == 2 { ",\"other\"]" } else { "]" })
      10 => if arity == 2 { "[\"id\",\"other\"]" } else { "\"id\"" }
      11 =>
        "[{\"left\":\"id\",\"right\":\"extra\"},\"id\"" +
        (if arity == 2 { ",\"other\"]" } else { "]" })
      _ => "\"id\""
    }
    let steps = if variant == 2 || variant == 3 {
      "[]"
    } else {
      "[{\"join\":{\"left\":\"a\",\"with\":\"b\",\"on\":" +
      on +
      ",\"kind\":\"" +
      (if variant == 10 { "full" } else { "left" }) +
      "\",\"select\":{\"id\":\"left.id\"}}}" +
      (if variant == 4 {
        ",{\"from\":\"b\",\"filter\":{\"literal\":true}}"
      } else {
        ""
      }) +
      "]"
    }
    let body = "{\"id\":\"a\",\"inputs\":{\"a\":" +
      complete +
      ",\"b\":" +
      right +
      ",\"c\":" +
      complete +
      "},\"from\":\"a\",\"steps\":" +
      steps +
      ",\"results\":{\"r\":{\"from\":\"" +
      (if variant == 2 { "b" } else { "a" }) +
      "\",\"fields\":[\"id\"]}}}"
    let source_inputs = fixture_inputs(complete, stage_bodies=Some(body))
    let source = @inputs.source(source_inputs)
    let resolved = resolve(source_inputs, catalog, caps()).unwrap()
    let prepared = prepare_pipeline_inputs(resolved, 10000000).unwrap()
    let stage = registered_stage(source, [
      pipeline_input_at(prepared, 0, 2).unwrap(),
      pipeline_input_at(prepared, 0, 1).unwrap(),
      pipeline_input_at(prepared, 0, 0).unwrap(),
    ])
    let operations = @stages.collect_operations(
      source,
      [@collection.pipeline(@stages.collection(stage))],
      {
        max_work: 1000000,
        max_slots: 1000,
        max_references: 1000,
        max_pointer_units: 1000000,
        max_direct_text_bytes: 1000000,
      },
    ).unwrap()
    let attachment = attach_pipeline_inputs(
      prepared,
      @stages.operations_stage_at(operations, 0).unwrap(),
      10000000,
    ).unwrap()
    let results = @stage_results.check(operations, {
      max_results: 100,
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    }).unwrap()
    let uses = collect_pipeline_uses(attachment, results, 1000000).unwrap()
    let context = prepare_requests(
      resolved,
      request_slots(source_inputs),
      1000000,
    ).unwrap()
    let parameters = prepare_request_parameters(
      context,
      supplied_values(source_inputs, "{}"),
      1000000,
    ).unwrap()
    let original_right = pipeline_input_source(prepared, 0, 1).unwrap()
    let form = check_request_form(context, original_right, 1000000)
    if variant == 7 && arity == 2 {
      assert_eq(form.unwrap_err(), RequestFormIssue::PartialCorrelation)
    } else {
      let projected = form.unwrap()
      assert_eq(
        request_form(projected),
        if variant == 1 || (variant == 7 && arity == 1) {
          DirectForm
        } else {
          KeyedTemplate
        },
      )
      assert_true(physical_equal(request_form_context(projected), context))
      assert_true(physical_equal(request_form_input(projected), original_right))
      let work = request_form_work(projected)
      assert_true(check_request_form(context, original_right, work) is Ok(_))
      assert_eq(
        check_request_form(context, original_right, work - 1).unwrap_err(),
        RequestFormIssue::WorkLimit,
      )
    }
    assert_eq(
      check_request_form(context, original_right, -1).unwrap_err(),
      RequestFormIssue::InvalidLimits,
    )
    let foreign_resolved = resolve(source_inputs, catalog, caps()).unwrap()
    assert_eq(
      check_request_form(context, at(foreign_resolved, 1).unwrap(), 1000000).unwrap_err(),
      RequestFormIssue::ForeignRequests,
    )
    let foreign_inputs = fixture_inputs(complete, stage_bodies=Some(body))
    assert_true(
      prepare_requests(resolved, request_slots(foreign_inputs), 1000000)
      is Err(issue) &&
      issue.kind == RequestIssueKind::ForeignSource,
    )
    // The projection above is only authored coverage. The original consumer,
    // mode, request-value and missing-field refusals below remain mandatory.
    let outcome = check_pipeline_requests(uses, parameters, request_caps())
    match variant {
      2 | 4 => assert_true(outcome is Err(InvalidKeyedConsumer(1, _)))
      3 => assert_true(outcome is Err(MissingKeyedConsumer(1)))
      5 =>
        assert_true(outcome is Err(Mode(1, e)) && e.kind == AuthoredKeyedScan)
      6 =>
        assert_true(
          outcome is Err(Request(1, e)) && e.kind == MissingField("tenant"),
        )
      7 if arity == 2 => assert_true(outcome is Err(PartialCorrelation(1)))
      _ => {
        let v = outcome.unwrap()
        assert_true(physical_equal(pipeline_requests_uses(v), uses))
        assert_true(physical_equal(pipeline_requests_parameters(v), parameters))
        assert_eq(pipeline_requests_count(v), 3)
        assert_true(pipeline_request_at(v, 0) is Some(Direct(_, _)))
        assert_true(pipeline_request_at(v, 2) is Some(Direct(_, _)))
        if variant == 0 || variant >= 8 {
          assert_true(pipeline_request_at(v, 1) is Some(Keyed(_, _)))
        } else {
          assert_true(pipeline_request_at(v, 1) is Some(Direct(_, _)))
        }
        assert_true(pipeline_request_at(v, -1) is None)
        assert_true(pipeline_request_at(v, 3) is None)
        let joins = check_keyed_joins(v, 1000000)
        if variant == 10 {
          assert_true(joins is Err(e) && e.kind == FullJoin(0))
        } else if variant == 11 {
          guard joins is Err(e) else { fail("extra correlation role accepted") }
          assert_eq(e.kind, UnknownResponseField(0, "extra"))
          let path = @decode.cursor_path(e.source.unwrap())
          assert_eq(path[path.length() - 1], @source.Index(0))
        } else if variant == 0 && arity == 2 {
          assert_true(
            joins is Err(e) && e.kind == MissingResponseField(0, "other"),
          )
        } else {
          let joined = joins.unwrap()
          assert_true(physical_equal(keyed_joins_requests(joined), v))
          assert_true(check_keyed_joins(v, keyed_joins_work(joined)) is Ok(_))
          assert_true(
            check_keyed_joins(v, keyed_joins_work(joined) - 1) is Err(e) &&
            e.kind == WorkLimit,
          )
          let is_keyed = variant == 0 || variant >= 8
          assert_eq(keyed_join_count(joined), if is_keyed { 1 } else { 0 })
          let facts = @environment.check_lookup_capacities(
            pipeline_catalog_references(prepared),
            { max_work: 1000000, max_facts: 100, },
          ).unwrap()
          let facts_result = check_keyed_facts(joined, facts, 100)
          if is_keyed && capacity_kind < 1 {
            assert_eq(
              facts_result.unwrap_err(),
              if capacity_kind < 0 {
                MissingCapacity(0)
              } else {
                IncompleteResponse(0)
              },
            )
          } else {
            let matched = facts_result.unwrap()
            assert_true(physical_equal(keyed_facts_joins(matched), joined))
            assert_true(physical_equal(keyed_facts_owner(matched), facts))
            assert_eq(keyed_facts_count(matched), if is_keyed { 1 } else { 0 })
            assert_true(
              check_keyed_facts(joined, facts, keyed_facts_work(matched))
              is Ok(_),
            )
            if is_keyed {
              let entry = keyed_facts_at(matched, 0).unwrap()
              assert_true(
                physical_equal(
                  keyed_source_join(entry),
                  keyed_join_at(joined, 0).unwrap(),
                ),
              )
              assert_eq(
                @environment.lookup_capacity_rows_per_key(
                  keyed_source_capacity(entry),
                ),
                2L,
              )
              assert_eq(
                @environment.lookup_capacity_pages_per_request(
                  keyed_source_capacity(entry),
                ),
                3L,
              )
              assert_eq(
                @environment.lookup_capacity_response_bytes_per_page(
                  keyed_source_capacity(entry),
                ),
                4096L,
              )
              assert_true(
                physical_equal(
                  @environment.lookup_facts_capacity(
                    @environment.source_lookup_body(keyed_source_facts(entry)),
                  ).unwrap(),
                  keyed_source_capacity(entry),
                ),
              )
              assert_eq(
                check_keyed_facts(joined, facts, 0).unwrap_err(),
                WorkLimit,
              )
            }
            assert_true(
              keyed_facts_at(matched, keyed_facts_count(matched)) is None,
            )
          }
          assert_eq(
            check_keyed_facts(joined, facts, -1).unwrap_err(),
            InvalidLimits,
          )
          let other_resolved = resolve(
            source_inputs,
            fixture_catalog(wire, cid),
            caps(),
          ).unwrap()
          let other_inputs = prepare_pipeline_inputs(other_resolved, 10000000).unwrap()
          let other_facts = @environment.check_lookup_capacities(
            pipeline_catalog_references(other_inputs),
            { max_work: 1000000, max_facts: 100, },
          ).unwrap()
          assert_eq(
            check_keyed_facts(joined, other_facts, 100).unwrap_err(),
            ForeignFacts,
          )
          if is_keyed {
            let linked = keyed_join_at(joined, 0).unwrap()
            check_captured_keyed_request(
              stage,
              parameters,
              linked,
              arity,
              variant,
              if capacity_kind >= 1 {
                Some(keyed_facts_at(facts_result.unwrap(), 0).unwrap())
              } else {
                None
              },
            )
            assert_eq(keyed_join_input(linked), 1)
            assert_eq(keyed_join_step(linked), 0)
            assert_eq(keyed_join_left(linked), @pipeline.Input(2))
            let (_, first) = keyed_join_role_at(linked, 0).unwrap()
            assert_eq(
              first.left,
              @row.Unqualified(if variant == 9 { "extra" } else { "id" }),
            )
            let expected = if variant == 8 && arity == 2 {
              [1, 0, 0]
            } else if variant >= 8 {
              if arity == 2 {
                [0, 0, 1]
              } else {
                [0, 0]
              }
            } else {
              [0]
            }
            assert_eq(
              @join.key_count(keyed_join_operation(linked)),
              expected.length(),
            )
            for j in 0..<expected.length() {
              assert_eq(keyed_join_pair_role(linked, j), Some(expected[j]))
            }
            assert_true(keyed_join_role_at(linked, arity) is None)
            assert_true(keyed_join_pair_role(linked, expected.length()) is None)
            guard pipeline_request_at(v, 1) is Some(Keyed(_, request)) else {
              fail("lost keyed request")
            }
            assert_true(physical_equal(keyed_join_request(linked), request))
          }
          assert_true(keyed_join_at(joined, keyed_join_count(joined)) is None)
        }
        let (work, pairs, nodes, text) = pipeline_requests_usage(v)
        let exact : RequestLimits = {
          max_work: work,
          max_pairs: pairs,
          values: {
            ..request_caps().values,
            max_nodes: nodes,
            max_text_bytes: text,
          },
        }
        assert_true(check_pipeline_requests(uses, parameters, exact) is Ok(_))
        assert_true(
          check_pipeline_requests(uses, parameters, {
            ..exact,
            max_work: work - 1,
          })
          is Err(_),
        )
        assert_true(
          check_pipeline_requests(uses, parameters, {
            ..exact,
            values: { ..exact.values, max_nodes: nodes - 1, },
          })
          is Err(_),
        )
      }
    }
    assert_true(
      check_pipeline_requests(uses, parameters, {
        ..request_caps(),
        max_work: -1,
      })
      is Err(InvalidLimits),
    )
    let other = resolve(source_inputs, catalog, caps()).unwrap()
    let other_context = prepare_requests(
      other,
      request_slots(source_inputs),
      1000000,
    ).unwrap()
    let other_parameters = prepare_request_parameters(
      other_context,
      supplied_values(source_inputs, "{}"),
      1000000,
    ).unwrap()
    assert_true(
      check_pipeline_requests(uses, other_parameters, request_caps())
      is Err(ForeignRequests),
    )
  }
}

///|
fn keyed_input_row_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
/// Read real immutable rows at the checked input port, including reordered and
/// repeated JOIN pairs. Bounds and expected values are authored independently
/// of the request implementation, not measured from a successful dry run.
fn check_captured_keyed_request(
  stage : @stages.CollectedStage,
  parameters : RequestParameters,
  joined : KeyedJoin,
  arity : Int,
  variant : Int,
  facts : KeyedSourceFacts?,
) -> Unit raise {
  let pipeline = @collection.pipeline(@stages.collection(stage))
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 100,
    max_references: 100,
    max_work: 100000,
    max_identifier_bytes: 10000,
  }).unwrap()
  let values = request_parameter_values(parameters)
  let owner = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  let rows = [
    keyed_input_row_cursor(
      if arity == 2 {
        "{\"extra\":2,\"id\":1,\"other\":3}"
      } else {
        "{\"extra\":2,\"id\":1}"
      },
    ),
    keyed_input_row_cursor(
      if arity == 2 {
        "{\"extra\":9,\"id\":7,\"other\":11}"
      } else {
        "{\"extra\":9,\"id\":7}"
      },
    ),
  ]
  let admission : @execution.ValueLimits = {
    max_nodes: 100,
    max_depth: 10,
    max_work: 10000,
    max_text_bytes: 10000,
  }
  // The fixture deliberately registers c,b,a in that order. The checked left
  // `a` is input 2; input 0 has equal schema but is a different occurrence.
  assert_eq(keyed_join_left(joined), @pipeline.Input(2))
  let captured = @execution.capture_input(owner, 2, rows, max_rows=2, admission).unwrap()
  let extraction_work = if arity == 2 {
    if variant == 9 {
      44
    } else {
      46
    }
  } else if variant == 9 {
    13
  } else {
    15
  }
  let request_work = if arity == 2 { 24 } else { 15 }
  let total_work = extraction_work + request_work
  let exact : RequestLimits = {
    max_work: total_work,
    max_pairs: arity + 1,
    values: { max_nodes: arity, max_depth: 1, max_text_bytes: 0, },
  }
  let (cursor, actual_extraction) = @query.start_captured_keyed_request(
    owner, joined, captured, 1, exact,
  ).unwrap()
  assert_eq(actual_extraction, extraction_work)
  let mut complete = None
  for _ in 0..<(3 * arity + 1) {
    match advance_keyed_row_request(cursor) {
      KeyedRowRequestContinue => ()
      KeyedRowRequestComplete(row) => complete = Some(row)
      KeyedRowRequestFailed(_) => fail("checked capture request failed")
    }
  }
  let request = complete.unwrap()
  let (work, nodes, text) = keyed_row_request_usage(request)
  assert_eq((actual_extraction + work, nodes, text), (total_work, arity, 0))
  let expected_id = if variant == 9 { "9" } else { "7" }
  let expected = "{\"id\":" +
    expected_id +
    (if arity == 2 { ",\"other\":11" } else { "" }) +
    ",\"tenant\":null}"
  assert_eq(
    @json.parse(keyed_row_request_wire(request, 1000, 100, 10).unwrap()),
    @json.parse(expected),
  )
  if facts is Some(facts) {
    check_captured_keyed_response(owner, facts, request, expected_id, arity)
  }
  let (short, _) = @query.start_captured_keyed_request(
    owner,
    joined,
    captured,
    1,
    { ..exact, max_work: total_work - 1, },
  ).unwrap()
  for _ in 0..<(3 * arity) {
    assert_true(advance_keyed_row_request(short) is KeyedRowRequestContinue)
  }
  assert_true(
    advance_keyed_row_request(short) is KeyedRowRequestFailed(WorkLimit),
  )
  assert_true(
    @query.start_captured_keyed_request(owner, joined, captured, 2, exact)
    is Err(@query.InvalidRow),
  )
  let wrong_port = @execution.capture_input(
    owner,
    0,
    rows,
    max_rows=2,
    admission,
  ).unwrap()
  assert_true(
    @query.start_captured_keyed_request(owner, joined, wrong_port, 1, exact)
    is Err(@query.ForeignInput),
  )
  let foreign_owner = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  assert_true(
    @query.start_captured_keyed_request(
      foreign_owner, joined, captured, 1, exact,
    )
    is Err(@query.ForeignInput),
  )
  let (cancelled, _) = @query.start_captured_keyed_request(
    owner, joined, captured, 1, exact,
  ).unwrap()
  assert_true(advance_keyed_row_request(cancelled) is KeyedRowRequestContinue)
  cancel_keyed_row_request(cancelled)
  assert_true(
    advance_keyed_row_request(cancelled) is KeyedRowRequestFailed(Closed),
  )
  // Request cancellation never reclaims or mutates the borrowed source rows.
  assert_eq(@execution.captured_row_count(captured), 2)
  assert_true(
    @execution.captured_cell(captured, 1, 1) is Some(@value.Number(7.0)),
  )
}

///|
fn check_captured_keyed_response(
  owner : @lower.BoundPrepared,
  facts : KeyedSourceFacts,
  request : KeyedRowRequest,
  expected_id : String,
  arity : Int,
) -> Unit raise {
  let joined = keyed_source_join(facts)
  let input = keyed_request_input(
    parameterized_keyed_request(keyed_join_request(joined)),
  )
  let schema = @query.keyed_response_input_schema(owner, joined, request).unwrap()
  let columns = []
  for i in 0..<@row.field_count(schema) {
    columns.push(@row.field_reference_name(@row.field_at(schema, i).unwrap()))
  }
  assert_eq(
    columns,
    if arity == 2 {
      ["extra", "id", "other"]
    } else {
      ["extra", "id"]
    },
  )
  let source_facts = @planning.keyed_source_evidence_facts(facts).unwrap()
  let view = @rowhost.declared_row_view(
    "r",
    source_facts.source_ref,
    selected_cid(input),
    columns,
    source_facts.carrier_schema_contract_cid,
    source_facts.source_data_policy_cid,
  )
  let page_limits : @rowhost.RowPageLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_rows: 2,
  }
  let retention : @execution.ValueLimits = {
    max_nodes: 100,
    max_depth: 10,
    max_work: 1000,
    max_text_bytes: 4096,
  }
  // Named-column metadata: 22 (one role) or 58 (two), plus one visit per
  // extracted response cell. Response comparison:
  // 9 (one role), or copy/start 3 + 2*6 role work + completion 1 = 16.
  // The resumable row owner additionally charges admission, append and page
  // completion once each. Quantum and repeated completion add no row work.
  let total = if arity == 2 { 79 } else { 35 }
  let limits : RequestLimits = {
    max_work: total,
    max_pairs: arity,
    values: { max_nodes: 100, max_depth: 10, max_text_bytes: 4096, },
  }
  let wire = "[{\"extra\":100,\"id\":" +
    expected_id +
    (if arity == 2 { ",\"other\":11" } else { "" }) +
    "}]"
  let begin = fn(work : Int) {
    @rowhost.begin_declared_keyed_row_read(
      owner,
      facts,
      request,
      "crm/main",
      view,
      page_limits,
      2,
      retention,
      { ..limits, max_work: work, },
    )
  }
  let read = begin(total).unwrap()
  assert_eq(
    @rowhost.accept_keyed_row_page(read, @utf8.encode(wire)).unwrap(),
    1,
  )
  assert_eq(
    @rowhost.keyed_row_read_usage(read),
    (total, 1L, @utf8.encode(wire).length().to_int64()),
  )
  let captured = @rowhost.complete_keyed_row_read(read).unwrap()
  assert_true(physical_equal(@execution.captured_owner(captured), owner))
  assert_eq(@execution.captured_origin(captured), @execution.SuppliedInput(1))
  assert_eq(@execution.captured_row_count(captured), 1)
  assert_false(@rowhost.cancel_keyed_row_read(read))
  assert_eq(@execution.captured_row_count(captured), 1)
  let short = begin(total - 1).unwrap()
  assert_true(
    @rowhost.accept_keyed_row_page(short, @utf8.encode(wire))
    is Err(@rowhost.KeyedLimit("work")),
  )
  assert_true(@rowhost.complete_keyed_row_read(short) is Err(@rowhost.Closed))
  assert_eq(@rowhost.keyed_row_read_usage(short).0, total - 1)
  for quantum in [1, 2, 64] {
    let resumed = begin(total).unwrap()
    let initial = @rowhost.keyed_row_read_usage(resumed).0
    @rowhost.begin_keyed_row_page(resumed, @utf8.encode(wire)).unwrap()
    // A decoded response and correct shape are not complete correlation or
    // permission to expose even the first captured row.
    assert_true(
      @rowhost.complete_keyed_row_read(resumed) is Err(@rowhost.KeyedIncomplete),
    )
    assert_true(
      @rowhost.begin_keyed_row_page(resumed, @utf8.encode(wire))
      is Err(@rowhost.KeyedIncomplete),
    )
    let mut sum = 0
    let mut complete = false
    for _ in 0..<1000 {
      match @rowhost.advance_keyed_row_page(resumed, quantum).unwrap() {
        KeyedPageContinue(work~) => sum += work
        KeyedPageComplete(rows~, work~) => {
          assert_eq(rows, 1)
          sum += work
          complete = true
          break
        }
      }
    }
    assert_true(complete)
    assert_eq(initial + sum, total)
    assert_eq(
      @rowhost.keyed_row_read_usage(resumed),
      (total, 1L, @utf8.encode(wire).length().to_int64()),
    )
    assert_true(
      @rowhost.advance_keyed_row_page(resumed, quantum)
      is Err(@rowhost.KeyedIncomplete),
    )
    assert_eq(@rowhost.keyed_row_read_usage(resumed).0, total)
    assert_eq(
      @execution.captured_row_count(
        @rowhost.complete_keyed_row_read(resumed).unwrap(),
      ),
      1,
    )
  }
  let interrupted = begin(total).unwrap()
  @rowhost.begin_keyed_row_page(interrupted, @utf8.encode(wire)).unwrap()
  for _ in 0..<5 {
    assert_true(
      @rowhost.advance_keyed_row_page(interrupted, 1)
      is Ok(KeyedPageContinue(..)),
    )
  }
  let interrupted_usage = @rowhost.keyed_row_read_usage(interrupted)
  assert_true(interrupted_usage.0 > (if arity == 2 { 58 } else { 22 }))
  assert_true(@rowhost.cancel_keyed_row_read(interrupted))
  assert_false(@rowhost.cancel_keyed_row_read(interrupted))
  assert_eq(@rowhost.keyed_row_read_usage(interrupted), interrupted_usage)
  assert_true(
    @rowhost.advance_keyed_row_page(interrupted, 1) is Err(@rowhost.Closed),
  )
  assert_true(
    @rowhost.complete_keyed_row_read(interrupted) is Err(@rowhost.Closed),
  )
  let foreign = begin(total).unwrap()
  let wrong = "[{\"extra\":100,\"id\":99" +
    (if arity == 2 { ",\"other\":11" } else { "" }) +
    "}]"
  assert_true(
    @rowhost.accept_keyed_row_page(foreign, @utf8.encode(wrong))
    is Err(@rowhost.KeyedResponse(CorrelationMismatch(0))),
  )
  assert_true(@rowhost.complete_keyed_row_read(foreign) is Err(@rowhost.Closed))
  let cancelled = begin(total).unwrap()
  assert_true(@rowhost.cancel_keyed_row_read(cancelled))
  assert_false(@rowhost.cancel_keyed_row_read(cancelled))
  assert_true(
    @rowhost.accept_keyed_row_page(cancelled, @utf8.encode(wire))
    is Err(@rowhost.Closed),
  )
  let pages = begin(total).unwrap()
  for _ in 0..<3 {
    assert_eq(
      @rowhost.accept_keyed_row_page(pages, @utf8.encode("[]")).unwrap(),
      0,
    )
  }
  assert_true(
    @rowhost.accept_keyed_row_page(pages, @utf8.encode("[]"))
    is Err(@rowhost.KeyedLimit("pages")),
  )
  assert_eq(@rowhost.keyed_row_read_usage(pages).1, 3L)
  assert_true(@rowhost.complete_keyed_row_read(pages) is Err(@rowhost.Closed))
}
