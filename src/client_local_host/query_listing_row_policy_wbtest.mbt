///|
// Real checked Catalog/Query/RowRun/Resource originals. The physical page and
// reference-issuer ports are deterministic fixtures, not installed I/O or ACK.
test "ordinary listing101 residual uses the original finite policy while explicit100 remains narrower" {
  for explicit in [false, true] {
    let (declaration, prepared, _, _, _, _, original) = original_keyed_run_fixture(
      selector_free=true,
      listing_maximum=1000L,
      listing_bytes=1000000L,
    )
    assert_eq(@planning.query_requirement_guards(original).max_rows, 1000)
    let original_cid = @planning.query_requirement_cid(original)
    let query_sequence = @planning.query_material_owner(
      @planning.query_requirement_material(original),
    )
    let query = @query.query_sequence_requirement(query_sequence)
    let requirement = if explicit {
      // This is a distinct explicitly selected requirement BEFORE its own
      // wire/CID or capture is constructed; never mutate the old original.
      @publication_host.prepare_client_query_requirement(
        prepared,
        @query.query_generated_sequence(query_sequence),
        0,
        1,
        { max_rows: 100, max_value_bytes: 10000, },
        installed_local_query_requirement_limits(query).unwrap(),
      ).unwrap()
    } else {
      original
    }
    assert_eq(@planning.query_requirement_cid(original), original_cid)
    assert_eq(@planning.query_requirement_guards(original).max_rows, 1000)
    if explicit {
      assert_true(@planning.query_requirement_cid(requirement) != original_cid)
      assert_eq(@planning.query_requirement_guards(requirement).max_rows, 100)
    }
    let acquisition = @row_source_host.prepare_row_acquisition(
      declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
    ).unwrap()
    assert_eq(
      @row_source_host.row_acquisition_max_rows(acquisition),
      if explicit {
        100
      } else {
        1000
      },
    )
    // Same physical original stays1000 in both cases; a larger physical
    // ceiling cannot override the explicitly selected logical100 guard.
    assert_eq(
      @row_source_host.row_acquisition_listing_report_bounds(acquisition).unwrap().0,
      1000L,
    )
    let rows : Array[Json] = []
    for index in 0..<101 {
      let name = "row-" + index.to_string() + ".jsonl"
      let reference : Json = {
        "$actql_ref": "resource",
        "authority_scope_cid": "sha256:" + "b".repeat(64),
        "boundary_cid": "sha256:" + "c".repeat(64),
        "identity_cid": "sha256:" + @sha.hex(@utf8.encode(name)),
        "provider_identity_cid": "sha256:" + "a".repeat(64),
        "provider_namespace": "file-fixture",
        "resource_kind": "file",
        "version": "actql-resource-ref/0.1",
      }
      rows.push({
        "resource": reference,
        "name": name,
        "path": name,
        "version": "v1",
        "media_type": Json::null(),
        "size_bytes": 9,
        "modified_at": Json::null(),
      })
    }
    let body = @utf8.encode(
      (
        {
          "items": rows,
          "request_token": Json::null(),
          "next_token": Json::null(),
        } : Json).stringify(),
    )
    let retained = @row_source_host.row_acquisition_retained_capacity(
      acquisition,
    )
    let execution = @row_source_host.row_acquisition_execution_capacity(
      acquisition,
    )
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 1,
      transfer_bytes: body.length().to_int64(),
      retained_bytes: retained,
      execution_bytes: execution + body.length().to_int64(),
    }).unwrap()
    let run = @row_source_host.start_accounted_row_acquisition(
      acquisition,
      "listing101-original",
      _ => true,
      ledger,
      body.length().to_int64(),
      body.length().to_int64(),
    ).unwrap()
    let issuer = @admitted.bind_reference_issuer((_, _) => true, _ => true)
    @row_source_host.begin_row_run(
      run,
      body.length(),
      101,
      101,
      reference_issuer=Some(issuer),
    ).unwrap()
    @row_source_host.begin_row_run_listing_request(run, None, 0L).unwrap()
    @row_source_host.begin_row_run_listing_page(run, body, 0L).unwrap()
    let mut page_complete = false
    for _ in 0..<100000 {
      match
        @row_source_host.advance_row_run_listing_page(run, 64, 0L).unwrap() {
        @row_source_host.ListingPageContinue(_) => ()
        @row_source_host.ListingPageComplete(rows~, ..) => {
          assert_eq(rows, 101)
          page_complete = true
          break
        }
      }
    }
    assert_true(page_complete)
    @row_source_host.finish_row_run(run).unwrap()
    @row_source_host.begin_row_capture(run).unwrap()
    let mut captured = false
    let mut refused = false
    for _ in 0..<100000 {
      match @row_source_host.advance_row_capture(run, 64) {
        Ok((true, _)) => {
          captured = true
          break
        }
        Ok((false, _)) => ()
        Err(
          @row_source_host.Residual(@connector.Execution(@execution.InputSet))
        ) => {
          refused = true
          break
        }
        Err(
          @row_source_host.Residual(@connector.Execution(@execution.InputLimit))
        ) => fail("original residual InputLimit")
        Err(
          @row_source_host.Residual(
            @connector.Execution(@execution.Rows(step, row_issue))
          )
        ) => {
          let detail = match row_issue {
            @execution.OwnerMismatch => "OwnerMismatch"
            @execution.InputMismatch => "InputMismatch"
            @execution.InvalidRows => "InvalidRows"
            @execution.RowLimit => "RowLimit"
            @execution.InvalidRowLimits => "InvalidRowLimits"
            @execution.MissingOrderedResourceContext =>
              "MissingOrderedResourceContext"
            @execution.LogicalRows(issue) =>
              "LogicalRows " + @debug.to_string(issue)
            @execution.Evaluation(row, field, _) =>
              "Evaluation row=" +
              row.to_string() +
              " field=" +
              field.to_string()
            @execution.Comparison(_) => "Comparison"
            _ => "other"
          }
          fail("original residual Rows step=" + step.to_string() + " " + detail)
        }
        Err(
          @row_source_host.Residual(
            @connector.Execution(@execution.Capture(step, _))
          )
        ) => fail("original residual Capture step=" + step.to_string())
        Err(@row_source_host.Residual(@connector.Execution(_))) =>
          fail("original residual other Execution")
        Err(@row_source_host.Residual(@connector.Guard(_))) =>
          fail("original residual Guard")
        Err(@row_source_host.Residual(@connector.ControlWorkLimit)) =>
          fail("original residual ControlWorkLimit")
        Err(@row_source_host.Residual(_)) =>
          fail("original residual other FixedCompute")
        Err(@row_source_host.ResidualWork(_)) =>
          fail("original residual work report")
        Err(_) => fail("unexpected original listing RowHost failure")
      }
    }
    assert_eq(captured, !explicit)
    assert_eq(refused, explicit)
    if !explicit {
      let capture = @row_source_host.capture_row_run(run).unwrap()
      let source = @row_source_host.row_capture_source(capture).unwrap()
      assert_eq(@query.captured_source_row_count(source), Some(101))
    }
    // Close/reclaim only this original component; pending cleanup retains its
    // reservation, rather than treating a stopped constructor as physical ACK.
    if @row_source_host.close_accounted_row_run(run) is Err(_) {
      assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
      let mut cleaned = false
      for _ in 0..<100000 {
        if @row_source_host.advance_row_capture_cleanup(run, 64).unwrap() {
          cleaned = true
          break
        }
      }
      assert_true(cleaned)
      @row_source_host.close_accounted_row_run(run).unwrap()
    }
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}
