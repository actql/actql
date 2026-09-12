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
