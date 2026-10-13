///|
// Independent declared Source facts, not keys inferred from the supplied pages.
fn source_relation_keys_declaration(
  drop_key? : Bool = false,
  scores? : Bool = false,
) -> @row_host.RowDeclaration {
  let schema_wire = if drop_key {
    "{\"id\":{\"nullable\":false,\"type\":\"number\"},\"payload\":{\"nullable\":false,\"type\":\"number\"}}"
  } else {
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}"
  }
  let schema_cid = if drop_key {
    // SHA-256 of the independently authored two-field map above.
    "sha256:ff8ac1ecfbda106baaa7a9338878d0b895b58dbcb93b6f96efaa58008b8d19d1"
  } else {
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513"
  }
  @row_host.generate_relation_row_declaration(
    "crm/main",
    "relation_key_fixture",
    "relation_key_fixture/0.1",
    [
      {
        resource: "r",
        resource_kind: "table",
        schema_wire,
        schema_cid,
        request_schema_wire: None,
        facts_wire: Some(if scores {
          "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]},\"relation_scores\":{\"payload\":{\"domain\":\"Relevance\",\"normalization\":\"Identity\",\"range\":[0,1]}}}"
        } else { "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}" }),
        acquisition_wire: None,
      },
    ],
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 1,
      // The declaration bound is its exact independently supplied field count.
      // Runtime, host, value, row, work and campaign limits stay unchanged.
      max_fields: if drop_key {
        2
      } else {
        1
      },
    },
  ).unwrap()
}

///|
fn source_relation_keys_requirement(
  declaration : @row_host.RowDeclaration,
  drop_key? : Bool = false,
  scores? : Bool = false,
) -> @planning.QueryRequirement raise {
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  let (wire, original_cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    [],
    host_policy="{\"capacity\":{\"max_aggregate_array_items\":10000,\"max_artifact_bytes\":10000,\"max_artifact_rows\":10000,\"max_effect_items\":10000,\"max_graph_input_edges\":10000,\"max_graph_input_nodes\":10000,\"max_graph_output_rows\":10000,\"max_graph_paths\":10000,\"max_infer_items\":10000,\"max_model_input_tokens_per_item\":10000,\"max_model_request_bytes_per_item\":10000,\"max_model_total_duration_ms\":10000,\"max_nested_value_bytes\":10000,\"max_nested_value_depth\":10000,\"max_relation_output_rows\":10000,\"max_temporal_matches_per_key\":10000,\"max_temporal_output_rows\":10000,\"version\":\"actql-capacity-host-policy/0.1\"}}",
  )
  let body = wire
    .replace(old=",\"evidence_bundle_cid\":\"" + original_cid + "\"", new="")
    .replace(
      old="\"connector_capabilities\":[]",
      new="\"connector_capabilities\":[" + capabilities.join(",") + "]",
    )
    .replace(
      old="\"schema_snapshots\":[]",
      new="\"schema_snapshots\":[" + schemas.join(",") + "]",
    )
  let cid = text_cid(body)
  let complete = body.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let projected_program =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":[{"value":"payload"}],"as":"captured"}],"results":{"r":{"from":"captured","fields":["value"]}}}],"results":{"out":{"from":{"stage":"a","result":"r"}}}}
  let checked = query_checked_program_fixture(
    catalog=Some(query_catalog_from_wire(complete, expected=cid)),
    program_text=if drop_key { Some(projected_program) } else { None },
  )
  let sequence = query_checked_sequence(checked)
  let preparation = @lower.bound_preparation(
    @query.query_sequence_owner(sequence),
  )
  // The original SourceView input and its pending key obligation survive.
  assert_true(
    @pipeline.input_contract_at(@lower.pipeline(preparation), 0)
    is Some(@pipeline.SourceViewInput(_, _, _, _)),
  )
  assert_true(@lower.preparation_input_keys(preparation, 0) is Some(_))
  if scores {
    let original = @lower.preparation_input_ranking(preparation, 0).unwrap()
    let declaration = @vector.ranking_score_at(original, @schema.Unqualified("payload")).unwrap()
    assert_eq(@vector.declared_score_contract(declaration).domain, "Relevance")
    let projected = @pipeline.ranking_evidence(@lower.pipeline(preparation), @pipeline.Step(1)).unwrap()
    assert_true(physical_equal(
      @vector.ranking_score_at(projected, @schema.Unqualified("value")).unwrap(), declaration,
    ))
    assert_true(@vector.ranking_score_at(projected, @schema.Unqualified("payload")) is None)
  }
  @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
}

///|
fn source_relation_keys_run(
  nonce : String,
  drop_key? : Bool = false,
  scores? : Bool = false,
) -> (@row_host.RowRun, @resources.Ledger) raise {
  let declaration = source_relation_keys_declaration(drop_key~, scores~)
  let requirement = source_relation_keys_requirement(declaration, drop_key~, scores~)
  let (query, evidence) = query_evidence_test_bodies()
  let acquisition = @row_host.prepare_row_acquisition(
    declaration,
    requirement,
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 1024L,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition),
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    128L,
  }).unwrap()
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    nonce,
    _ => true,
    ledger,
    1024L,
    128L,
  ).unwrap()
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  (run, ledger)
}

///|
test "SourceView declared key validates the complete two-page acquisition before capture" {
  for bounded in [false, true] {
    let (run, ledger) = source_relation_keys_run(
      "source-key-valid-" + bounded.to_string(),
    )
    for page in ["[{\"id\":2}]", "[{\"id\":3}]"] {
      assert_eq(
        @row_host.accept_row_run_page(run, @utf8.encode(page)).unwrap(),
        1,
      )
    }
    @row_host.finish_row_run(run).unwrap()
    if bounded {
      @row_host.begin_row_capture(run).unwrap()
      let mut completed = false
      let mut previous_work = 0L
      for _ in 0..<10000 {
        let (done, work) = @row_host.advance_row_capture(run, 1).unwrap()
        assert_true(work >= previous_work)
        previous_work = work
        if done {
          completed = true
          break
        }
      }
      assert_true(completed)
    }
    let capture = @row_host.capture_row_run(run).unwrap()
    let source = @row_host.row_capture_source(capture).unwrap()
    assert_eq(@query.captured_source_statistics(source).unwrap().rows, 2)
    let usage = @resources.ledger_usage(ledger)
    // Re-reading the same live capture does not acquire or charge another page.
    assert_true(@row_host.row_capture_source(capture) is Ok(_))
    assert_eq(@resources.ledger_usage(ledger), usage)
    if bounded {
      @row_host.close_row_run(run)
      let mut cleaned = false
      for _ in 0..<10000 {
        if @row_host.advance_row_capture_cleanup(run, 1).unwrap() {
          cleaned = true
          break
        }
      }
      assert_true(cleaned)
    }
    @row_host.close_accounted_row_run(run).unwrap()
    assert_true(@query.captured_source_statistics(source) is None)
    row_page_assert_closed(run, ledger)
  }
}

///|
test "SourceView key rejects identical duplicate pages even when the filter removes both rows" {
  for id in [2, 0] {
    let (run, ledger) = source_relation_keys_run(
      "source-key-duplicate-" + id.to_string(),
    )
    let page = @utf8.encode("[{\"id\":" + id.to_string() + "}]")
    for _ in 0..<2 {
      assert_eq(@row_host.accept_row_run_page(run, page).unwrap(), 1)
    }
    @row_host.finish_row_run(run).unwrap()
    assert_true(
      @row_host.capture_row_run(run)
      is Err(
        Evidence(
          Attempt(
            Residual(Execution(Execution(InputKey(0, DuplicateKey(0, 1)))))
          )
        )
      ),
    )
    row_page_assert_closed(run, ledger)
  }
}

///|
test "dropping the input key cannot discard the original SourceView validation obligation" {
  let (run, ledger) = source_relation_keys_run(
    "source-key-projection",
    drop_key=true,
  )
  // The projected values differ: validating or ordering only the output would
  // miss the duplicate input key. This is ordinary select, not an expression.
  assert_eq(
    @row_host.accept_row_run_page(
      run,
      @utf8.encode("[{\"id\":2,\"payload\":5},{\"id\":2,\"payload\":6}]"),
    ).unwrap(),
    2,
  )
  @row_host.finish_row_run(run).unwrap()
  assert_true(
    @row_host.capture_row_run(run)
    is Err(
      Evidence(
        Attempt(Residual(Execution(Execution(InputKey(0, DuplicateKey(0, 1))))))
      )
    ),
  )
  row_page_assert_closed(run, ledger)
}

///|
test "SourceView key domain rejects NULL and missing input fields before capture" {
  let (null_run, null_ledger) = source_relation_keys_run("source-key-null")
  assert_true(
    @row_host.accept_row_run_page(null_run, @utf8.encode("[{\"id\":null}]"))
    is Err(Source(Value("id"))),
  )
  row_page_assert_closed(null_run, null_ledger)
  let (missing_run, missing_ledger) = source_relation_keys_run(
    "source-key-missing",
  )
  assert_true(
    @row_host.accept_row_run_page(missing_run, @utf8.encode("[{}]"))
    is Err(Source(MissingField("id"))),
  )
  row_page_assert_closed(missing_run, missing_ledger)
}

///|
test "cancelling a partial SourceView acquisition cannot issue a key-validated capture" {
  let (run, ledger) = source_relation_keys_run("source-key-cancel")
  @row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":2}]")).unwrap()
  |> ignore
  @row_host.abort_row_run(run)
  row_page_assert_closed(run, ledger)
}

///|
test "installed bounded Source capture cannot publish duplicates hidden by its filter" {
  let (run, ledger) = source_relation_keys_run("source-key-bounded-duplicate")
  for _ in 0..<2 {
    @row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":0}]")).unwrap()
    |> ignore
  }
  @row_host.finish_row_run(run).unwrap()
  @row_host.begin_row_capture(run).unwrap()
  let mut rejected = false
  let mut previous_work = 0L
  for _ in 0..<10000 {
    match @row_host.advance_row_capture(run, 1) {
      Err(Residual(Execution(InputKey(0, DuplicateKey(0, 1))))) => {
        rejected = true
        break
      }
      Ok((done, work)) => {
        assert_true(work >= previous_work)
        previous_work = work
        if done {
          break
        }
      }
      _ => fail("unexpected bounded Source capture failure")
    }
  }
  let unexpected_rows = if rejected {
    assert_true(@row_host.capture_row_run(run) is Err(_))
    None
  } else {
    match @row_host.capture_row_run(run) {
      Ok(capture) =>
        Some(
          @query.captured_source_statistics(
            @row_host.row_capture_source(capture).unwrap(),
          ).unwrap().rows,
        )
      Err(_) => None
    }
  }
  @row_host.close_row_run(run)
  let reserved = @resources.ledger_usage(ledger).reserved_execution_bytes
  assert_true(reserved > 0L)
  let mut closed = false
  let mut pending = false
  for _ in 0..<10000 {
    if @row_host.advance_row_capture_cleanup(run, 1).unwrap() {
      closed = true
      break
    }
    pending = true
    assert_eq(
      @resources.ledger_usage(ledger).reserved_execution_bytes,
      reserved,
    )
  }
  assert_true(pending)
  assert_true(closed)
  row_page_assert_closed(run, ledger)
  let capture_detail = match unexpected_rows {
    Some(rows) => rows.to_string()
    None => "none"
  }
  assert_true(
    rejected,
    msg="a filtered subset is not proof of the declared input key; unexpected captured rows=" +
      capture_detail,
  )
}

///|
test "bounded Source capture cancellation keeps ownership until cleanup confirms" {
  let (run, ledger) = source_relation_keys_run("source-key-bounded-cancel")
  @row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":2},{\"id\":3}]")).unwrap()
  |> ignore
  @row_host.finish_row_run(run).unwrap()
  @row_host.begin_row_capture(run).unwrap()
  assert_true(@row_host.advance_row_capture(run, 1) is Ok((false, _)))
  let reserved = @resources.ledger_usage(ledger).reserved_execution_bytes
  assert_true(reserved > 0L)
  @row_host.abort_row_run(run)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, reserved)
  assert_true(@row_host.capture_row_run(run) is Err(InvalidState))
  @row_host.close_row_run(run)
  let mut closed = false
  for _ in 0..<10000 {
    if @row_host.advance_row_capture_cleanup(run, 1).unwrap() {
      closed = true
      break
    }
  }
  assert_true(closed)
  row_page_assert_closed(run, ledger)
}

///|
test "native filtered acquisition refuses pending SourceView key validation before provider access" {
  let requirement = source_relation_keys_requirement(
    source_relation_keys_declaration(),
  )
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  assert_true(
    @duckdb.compile_native_filter_select(
      @query.query_sequence_owner(sequence),
      "main",
      "records",
      native_compile_limits(),
    )
    is Err(UnsupportedShape),
  )
}
