///|
test "original Local CSV bytes become one typed Whole page under the quoted RowRun" {
  let wire =
    #|{"version":"actql-connectors/0.1","connections":{"local":{"connector":"local","root":"./data","tables":{"small":{"path":"small.csv","key":["id"],"columns":{"id":"int64","name":"string"}}}}}}
  let original = admit_client_project_connections(wire).unwrap()
  let quoted = Ref(0)
  let local_files = original
    .funded_local_files(
      0,
      100,
      2,
      _ => {
        quoted.val += 1
        Ok(())
      },
      cause => client_project_local_files_issue_code(cause),
    )
    .unwrap()
  assert_eq(quoted.val, 2)
  let resolved_root = "/original-project/data"
  let catalog_limits : @row_host.LocalFileSourceDeclarationLimits = {
    max_files: 3,
    max_entries: 8,
    max_pages: 2,
    max_attempts: 2,
    max_listing_bytes: 65536,
    max_duration_ms: 1000,
    max_path_bytes: 100,
    max_page_bytes: 256,
  }
  fn issue_catalog() -> ClientProjectLocalFileCatalog raise {
    let first = local_files
      .catalog_specification_capacity(resolved_root, catalog_limits)
      .unwrap()
    assert_true(first > 0L)
    let construction = local_files
      .prepare_catalog_specification(resolved_root, catalog_limits)
      .unwrap()
    assert_true(construction.construction_capacity().unwrap() > 0L)
    let catalog = construction.issue().unwrap()
    assert_true(construction.issue() is Err(InvalidState))
    assert_true(construction.construction_capacity() is Err(InvalidState))
    catalog
  }
  let catalog = issue_catalog()
  let declaration = catalog.declaration
  let classified = local_files
    .prepare_catalog_specification(
      resolved_root,
      catalog_limits,
      csv_classification=Some(("small", @environment.Internal)),
    )
    .unwrap()
    .issue()
    .unwrap().declaration
  for resource in ["contents", "files", "small"] {
    let source_ref = "connector://local/" + resource + "#records"
    let original_view = @row_host.row_declaration_view(declaration, source_ref).unwrap()
    let selected_view = @row_host.row_declaration_view(classified, source_ref).unwrap()
    assert_eq(original_view.classification, "unknown")
    assert_eq(
      original_view.carrier_schema_cid,
      selected_view.carrier_schema_cid,
    )
    if resource == "small" {
      assert_eq(selected_view.classification, "internal")
      assert_true(
        original_view.data_policy_cid != selected_view.data_policy_cid,
      )
    } else {
      assert_eq(original_view.data_policy_cid, selected_view.data_policy_cid)
    }
  }
  for
    (name, classification) in [
      ("contents", @environment.Internal),
      ("small", @environment.Unknown),
    ] {
    assert_true(
      local_files.prepare_catalog_specification(
        resolved_root,
        catalog_limits,
        csv_classification=Some((name, classification)),
      )
      is Err(_),
    )
  }
  let views = declaration.views.map(view => view.resource)
  assert_eq(views.length(), 3)
  for resource in ["contents", "files", "small"] {
    assert_true(views.contains(resource))
  }
  let (_, mapping_wire, _) = @row_host.local_file_store_declaration_wires(
    declaration,
  ).unwrap()
  let mapping = scalar_profile_cursor(mapping_wire)
  let command = @decode.lookup_original_field(mapping, "store_command").unwrap()
  assert_eq(
    @decode.text(@decode.lookup_original_field(command, "catalog_cid").unwrap()),
    Ok(declaration.catalog_cid),
  )
  let base_wire = client_local_product_assets().environment
  let base_fields = @json.parse(base_wire)
  guard base_fields is Object(base_fields) &&
    base_fields.get("evidence_bundle_cid") is Some(String(evidence)) else {
    fail("original CSV Check base")
  }
  let base = admit_client_check_environment(
    base_wire,
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let account_wire =
    #|{"version":"actql-execution-account-config/0.1","account_id":"local","entries":[{"entry_id":"csv","outcome":"allow","principal":{"any_of":["reader"]},"connection":{"any_of":["local"]},"resource":{"any_of":["small"]},"operation":{"any_of":["read"]},"exclusions":[]}]}
  let account = @authorization.admit_account_configuration_json(account_wire).unwrap()
  let catalogs = [catalog]
  let check = prepare_funded_client_project_local_file_check(
    base,
    catalogs,
    account,
    "reader",
    _ => Ok(()),
    issue => issue,
  ).unwrap()
  let (_, _, limits) = client_composed_effect_base_fixture()
  let prepared = match
    prepare_effect_free_client_program(
      (
        #|{"version":"actql/0.1","id":"original-csv-whole","stages":[{"id":"read","inputs":{"rows":{"connector":"local","resource":"small","view":"records"}},"steps":[{"select":["id","name"],"as":"selected"},{"sort":[{"id":"asc"}],"as":"sorted"}],"results":{"out":{"from":"sorted","fields":["id","name"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
      ),
      Json,
      check.environment,
      None,
      limits.program,
    ) {
    Ok(value) => value
    Err(Check(issue)) =>
      match @checked.diagnostic_cause(issue) {
        @checked.LocalConstructionFailure::Environment(failure) => raise failure
        cause => raise cause
      }
    Err(Syntax(issue)) => fail(@debug.to_string(issue))
    Err(_) => fail("Local CSV checked program preparation")
  }
  let acquisition = prepare_client_source_acquisition(prepared, 0, 0).unwrap()
  let sequence = @lower.prepare_sequence(
    @strategy.graph_task_owner(prepared.graph, 0).unwrap(),
    run_materials_limits().sequence,
  ).unwrap()
  let page : @row_host.RowPageLimits = {
    max_bytes: 256,
    max_rows: 3,
    max_nodes: 64,
    max_depth: 8,
  }
  fn prepare_selected(
    declared : @row_host.RowDeclaration,
  ) -> @row_host.RowInputAcquisition {
    @row_host.prepare_row_input_acquisition(
      acquisition,
      @checked.source_identity(@strategy.graph_program(prepared.graph)),
      sequence,
      whole_source_capture_contracts(),
      declared,
      {
        max_rows: 3,
        page,
        retention: {
          max_nodes: 128,
          max_text_bytes: 128,
          max_depth: 8,
          max_work: 10000,
        },
        wire: {
          max_columns: 2,
          max_order_work: 128,
          max_bytes: 256,
          max_nodes: 64,
          max_depth: 8,
        },
      },
    ).unwrap()
  }
  let selected = prepare_selected(declaration)
  let raw = b"id,name\n1,A\n2,B\n3,C\n"
  let source_limits : ClientProjectLocalCsvSourceLimits = {
    max_file_bytes: raw.length().to_int64(),
    max_page_bytes: 256,
    max_files: 3L,
    max_page_rows: 3L,
  }
  let equal_account = @authorization.admit_account_configuration_json(
    account_wire,
  ).unwrap()
  let attempts = Ref(0)
  let issue = issue => @debug.to_string(issue)
  assert_true(
    check.prepare_csv_source(
      acquisition,
      equal_account,
      "reader",
      source_limits,
      _ => {
        attempts.val += 1
        Ok(())
      },
      issue,
    )
    is Err("ForeignOriginal"),
  )
  assert_true(
    check.prepare_csv_source(
      acquisition,
      account,
      "other",
      source_limits,
      _ => {
        attempts.val += 1
        Ok(())
      },
      issue,
    )
    is Err("ForeignOriginal"),
  )
  assert_eq(attempts.val, 0)
  // A caller can change its original vector after Check, but this Check owns
  // its selected copy. Equal bytes never substitute the installed declaration.
  let foreign = issue_catalog()
  assert_eq(foreign.declaration.catalog, declaration.catalog)
  catalogs[0] = foreign
  let denied_wire =
    #|{"version":"actql-execution-account-config/0.1","account_id":"local","entries":[{"entry_id":"csv","outcome":"deny","principal":{"any_of":["reader"]},"connection":{"any_of":["local"]},"resource":{"any_of":["small"]},"operation":{"any_of":["read"]},"exclusions":[]}]}
  let denied = @authorization.admit_account_configuration_json(denied_wire).unwrap()
  let denied_check = prepare_funded_client_project_local_file_check(
    base,
    [catalog],
    denied,
    "reader",
    _ => Ok(()),
    issue => issue,
  ).unwrap()
  assert_true(
    denied_check.prepare_csv_source(
      acquisition,
      denied,
      "reader",
      source_limits,
      _ => Ok(()),
      issue,
    )
    is Err("ReadDenied"),
  )
  let paid = Ref(0L)
  let source = check
    .prepare_csv_source(
      acquisition,
      account,
      "reader",
      source_limits,
      demand => {
        paid.val = @execution.preparation_representation_cost(demand).unwrap()
        Ok(())
      },
      issue,
    )
    .unwrap()
  assert_true(physical_equal(source.declaration(), declaration))
  assert_true(
    check.prepare_csv_source(
      acquisition,
      account,
      "reader",
      source_limits,
      demand => {
        let need = @execution.preparation_representation_cost(demand).unwrap()
        if need <= paid.val - 1L {
          Ok(())
        } else {
          Err("one short")
        }
      },
      issue,
    )
    is Err("one short"),
  )
  assert_true(
    source.bind_input(prepare_selected(foreign.declaration))
    is Err(Row(ForeignDeclaration)),
  )
  let csv = source.bind_input(selected).unwrap()
  assert_true(csv.matches_check(check))
  let copy_check = prepare_funded_client_project_local_file_check(
    base,
    [catalog],
    account,
    "reader",
    _ => Ok(()),
    issue => issue,
  ).unwrap()
  assert_false(csv.matches_check(copy_check))
  let quote = source.transport
  let provider = @execution.execution_capacity(1024L, 2048L)
  let capacity = @row_host.row_input_acquisition_capacity(selected, provider).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity) +
    quote.execution_bytes
  for
    scenario in [
      "initial-one-short", "initial-exact", "transfer-one-short", "valid", "malformed",
      "failed-zero", "failed-prefix", "failed-unknown", "abandoned-before-offer",
      "abandoned-known", "abandoned-unknown", "valid-short",
    ] {
    let initial_only = scenario == "initial-one-short" ||
      scenario == "initial-exact"
    let ledger = @resources.create_ledger({
      planning_work: 100,
      attempts: 1,
      holdings: 1,
      transfer_bytes: quote.transfer_bytes,
      retained_bytes: if initial_only {
        retained
      } else {
        16777216L
      },
      execution_bytes: match scenario {
        "initial-one-short" => execution - 1L
        "initial-exact" => execution
        _ => 33554432L
      },
    }).unwrap()
    let started = @row_host.start_accounted_row_input_acquisition(
      selected,
      provider,
      "local-csv",
      _ => true,
      ledger,
      if scenario == "transfer-one-short" {
        quote.transfer_bytes - 1L
      } else {
        quote.transfer_bytes
      },
      quote.execution_bytes,
    )
    if scenario == "initial-one-short" {
      assert_true(started is Err(Physical(ExecutionLimit)))
      let usage = @resources.ledger_usage(ledger)
      assert_eq(usage.attempts, 0)
      assert_eq(usage.transferred_bytes, 0L)
      assert_eq(usage.reserved_execution_bytes, 0L)
      continue
    }
    let run = started.unwrap()
    @row_host.begin_row_run_with_page_limits(run, page, 3).unwrap()
    let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
    let stop_count = Ref(0)
    let stop_allowed = Ref(true)
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => {
      stop_count.val += 1
      stop_allowed.val
    }).unwrap()
    if scenario == "valid" {
      let different_acquisition = prepare_selected(declaration)
      let other_csv = source.bind_input(different_acquisition).unwrap()
      assert_true(
        other_csv.prepare_response(borrow) is Err(Row(ForeignDeclaration)),
      )
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
    }
    let (root, relative, receiver) = csv.prepare_response(borrow).unwrap()
    assert_eq(root, resolved_root)
    assert_eq(relative, "small.csv")
    if scenario == "initial-exact" {
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        execution,
      )
      @row_host.close_accounted_row_run(run).unwrap()
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
      assert_true(stop_count.val > 0)
      continue
    }
    if scenario == "transfer-one-short" {
      assert_true(
        @row_host.begin_local_csv_whole_response(receiver)
        is Err(Row(Physical(TransferLimit))),
      )
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
      @row_host.close_accounted_row_run(run).unwrap()
      continue
    }
    if scenario == "abandoned-before-offer" {
      @row_host.retire_local_csv_whole_response(receiver, Some(0L)).unwrap()
      @row_host.close_accounted_row_run(run).unwrap()
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
      assert_eq(stop_count.val, 1)
      continue
    }
    let (_, _, copied_response) = csv.prepare_response(borrow).unwrap()
    assert_true(
      @row_host.accept_local_csv_whole_response(receiver, raw)
      is Err(Row(InvalidState)),
    )
    @row_host.begin_local_csv_whole_response(receiver).unwrap()
    assert_true(
      @row_host.begin_local_csv_whole_response(copied_response)
      is Err(Row(InvalidState)),
    )
    assert_true(
      @row_host.begin_local_csv_whole_response(receiver)
      is Err(Row(InvalidState)),
    )
    if scenario.has_prefix("failed-") || scenario.has_prefix("abandoned-") {
      let observed = match scenario {
        "failed-zero" => Some(0L)
        "failed-prefix" | "abandoned-known" => Some(8L)
        _ => None
      }
      if scenario.has_prefix("abandoned-") {
        @row_host.retire_local_csv_whole_response(receiver, observed).unwrap()
        @row_host.retire_local_csv_whole_response(receiver, None).unwrap()
      } else {
        @row_host.fail_local_csv_whole_response(receiver, observed).unwrap()
      }
      assert_true(
        @row_host.fail_local_csv_whole_response(receiver, observed)
        is Err(Row(InvalidState)),
      )
      assert_true(
        @row_host.accept_local_csv_whole_response(receiver, raw)
        is Err(Row(InvalidState)),
      )
      assert_true(@row_host.capture_row_run(run) is Err(_))
      let settled = @resources.ledger_usage(ledger)
      assert_eq(settled.attempts, 1)
      assert_eq(settled.transferred_bytes, observed.unwrap_or(0L))
      assert_eq(
        settled.uncertain_transfer_bytes,
        if observed is None {
          quote.transfer_bytes
        } else {
          0L
        },
      )
      assert_eq(settled.reserved_transfer_bytes, 0L)
      stop_allowed.val = false
      assert_true(
        @row_host.close_accounted_row_run(run)
        is Err(Evidence(UnverifiedTransport)),
      )
      assert_eq(
        @resources.ledger_usage(ledger).transferred_bytes,
        settled.transferred_bytes,
      )
      assert_eq(
        @resources.ledger_usage(ledger).uncertain_transfer_bytes,
        settled.uncertain_transfer_bytes,
      )
      stop_allowed.val = true
      @row_host.close_accounted_row_run(run).unwrap()
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
      continue
    }
    if scenario == "malformed" {
      let malformed = b"id,name\n1,A\n02,B\n3,C"
      assert_eq(malformed.length(), raw.length())
      assert_true(
        @row_host.accept_local_csv_whole_response(receiver, malformed)
        is Err(Csv(InvalidLocalCsvInt64)),
      )
      assert_true(
        @row_host.accept_local_csv_whole_response(receiver, raw)
        is Err(Row(InvalidState)),
      )
      assert_true(@row_host.capture_row_run(run) is Err(_))
      @row_host.close_accounted_row_run(run).unwrap()
      assert_true(stop_count.val > 0)
      let closed = @resources.ledger_usage(ledger)
      assert_eq(closed.attempts, 1)
      assert_eq(closed.transferred_bytes, raw.length().to_int64())
      assert_eq(closed.reserved_execution_bytes, 0L)
      continue
    }
    let received = if scenario == "valid-short" {
      raw[:raw.length() - 1].to_owned()
    } else {
      raw
    }
    assert_true(
      @row_host.accept_local_csv_whole_response(receiver, received) is Ok(3),
    )
    assert_true(
      @row_host.accept_local_csv_whole_response(receiver, raw)
      is Err(Row(InvalidState)),
    )
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      received.length().to_int64(),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_transfer_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).attempts, 1)
    @row_host.finish_row_run(run).unwrap()
    assert_true(whole_row_validate(run))
    let source = @row_host.row_capture_source(
      @row_host.capture_row_run(run).unwrap(),
    ).unwrap()
    assert_true(
      @query.captured_source_matches_input_acquisition(source, acquisition),
    )
    assert_eq(@query.captured_source_row_count(source), Some(3))
    let rows = @query.captured_source_storage(source, 3, 8).unwrap()
    for index, label in ["A", "B", "C"] {
      assert_true(
        @execution.producer_storage_cell(rows, index, 0)
        is Some(Captured(Signed64(id))) &&
        id == (index + 1).to_int64(),
      )
      assert_true(
        @execution.producer_storage_cell(rows, index, 1) is Some(Text(name)) &&
        name == label,
      )
    }
    @row_host.close_accounted_row_run(run).unwrap()
    assert_true(stop_count.val > 0)
    assert_false(@query.captured_source_available(source))
    let closed = @resources.ledger_usage(ledger)
    assert_eq(closed.reserved_execution_bytes, 0L)
    assert_eq(closed.reserved_transfer_bytes, 0L)
    assert_eq(closed.transferred_bytes, received.length().to_int64())
  }
}

///|
test "funded Local Project member refuses an unpaid or malformed second table" {
  let wire =
    #|{"version":"actql-connectors/0.1","connections":{"local":{"connector":"local","root":"./data","tables":{"small":{"path":"small.csv","columns":{"id":"int64"}},"other":{"path":"other.csv","columns":{"name":"wrong-type"}}}}}}
  let original = admit_client_project_connections(wire).unwrap()
  let quotes = Ref(0)
  let stop_at = Ref(1)
  fn fund(_inventory) {
    quotes.val += 1
    if quotes.val == stop_at.val {
      Err("no capacity")
    } else {
      Ok(())
    }
  }
  fn issue(cause) {
    client_project_local_files_issue_code(cause)
  }
  let first = original.funded_local_files(0, 100, 2, fund, issue)
  assert_true(first is Err("no capacity"))
  assert_eq(quotes.val, 1)
  quotes.val = 0
  stop_at.val = 2
  let table_refused = original.funded_local_files(0, 100, 2, fund, issue)
  assert_true(table_refused is Err("no capacity"))
  assert_eq(quotes.val, 2)
  quotes.val = 0
  stop_at.val = 0
  let invalid = original.funded_local_files(0, 100, 2, fund, issue)
  assert_true(invalid is Err("InvalidLocalCsvColumns"))
  assert_true(quotes.val >= 2)
  assert_eq(
    resolve_client_project_path(
      "/original-project",
      "./data",
      ordinary_file=true,
      ordinary_directory=true,
    ),
    Some("/original-project/data"),
  )
  assert_eq(
    resolve_client_project_path(
      "/",
      "../data",
      ordinary_file=true,
      ordinary_directory=true,
    ),
    None,
  )
}

///|
test "funded Local Project selection retains every supported table" {
  let wire =
    #|{"version":"actql-connectors/0.1","connections":{"local":{"connector":"local","root":"./data","tables":{"small":{"path":"small.csv","columns":{"id":"int64"}},"named":{"path":"names.csv","columns":{"name":"string"}}}}}}
  let original = admit_client_project_connections(wire).unwrap()
  let quoted = Ref(0)
  let files = original
    .funded_local_files(
      0,
      100,
      2,
      _ => {
        quoted.val += 1
        Ok(())
      },
      client_project_local_files_issue_code,
    )
    .unwrap()
  assert_eq(quoted.val, 3)
  assert_eq(files.csv_tables.map(table => table.view.resource), [
    "small", "named",
  ])

  let wire =
    #|{"version":"actql-connectors/0.1","connections":{"local":{"connector":"local","root":"./data","tables":{"dataset":{"format":"iceberg","path":"metadata.json"}}}}}
  let original = admit_client_project_connections(wire).unwrap()
  assert_true(
    original.funded_local_files(
      0,
      100,
      2,
      _ => Ok(()),
      client_project_local_files_issue_code,
    )
    is Err("InvalidLocalFilesConnection"),
  )
  assert_eq(original.local_files(0, 100, 2).unwrap().csv_tables.length(), 0)
}
