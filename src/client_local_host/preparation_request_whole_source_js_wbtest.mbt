///|
let request_whole_source_document : String =
  #|{"version":"actql/0.1","id":"same-original-whole-join","stages":[{"id":"left","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"right","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"joined","inputs":{"left":{"result":{"stage":"left","result":"rows"}},"right":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}

///|
fn request_whole_source_fixture(
  current? : () -> Bool = () => true,
  reserve_plan? : Bool = true,
  text? : String = request_whole_source_document,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  @publication_host.ClientRequestIdentity,
) raise {
  let declaration = pure_provider_declaration()
  let (parent, child, _, input) = registration_parent_fixture(
    text~,
    environment=Some(pure_provider_environment(declaration)),
    current~,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("the original Whole Program must check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  continue_request_program_preparation(parent, input).unwrap() |> ignore
  if reserve_plan {
    reserve_request_program_plan(parent, input).unwrap()
  }
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-original-whole-join",
  ).unwrap()
  (parent, input, prepared, request)
}

///|
test "Native file Request keeps both Whole inputs sharing one Compute" {
  let text =
    #|{"version":"actql/0.1","id":"same-task-whole-join","stages":[{"id":"joined","inputs":{"left":{"connector":"pure-provider","resource":"records"},"right":{"connector":"pure-provider","resource":"records"}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}
  let (parent, input, prepared, request) = request_whole_source_fixture(text~)
  guard prepare_request_native_file_source_inputs(parent, input, request, None).unwrap()
    is WholeSourceInputs(direct, sources) else {
    fail("both authenticated occurrences require Whole construction")
  }
  assert_eq(sources.length(), 2)
  let left = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 0,
  ).unwrap()
  let right = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 1,
  ).unwrap()
  assert_eq(left.0, right.0)
  assert_eq(left.2, right.2)
  assert_true(left.1 != right.1)
  for index in 0..<sources.length() {
    let (stage, source_index, _) = @publication_host.client_direct_acquisition_occurrence_at(
      direct, index,
    ).unwrap()
    assert_true(
      @publication_host.client_source_acquisition_matches_program(
        prepared,
        stage,
        source_index,
        sources[index],
      ),
    )
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request Whole quotation scratch is reserved before its first domain grow" {
  // Independent fixed constructor inventory: H232/R104/W468 under the
  // existing16/8/8 logical representation tariff, not a policy allowance.
  assert_eq(request_whole_source_initial_quotation_bytes, 8288L)
  for axis in 0..<2 {
    for shortage in [0L, 1L] {
      let (parent, input, _, _) = request_whole_source_fixture(
        reserve_plan=false,
      )
      let (r, e) = request_program_plan_quote(parent, input).unwrap()
      let (old_r, old_e) = @resources.preparation_capacity_working_extents(
        parent.program_capacity.unwrap(),
        input,
      ).unwrap()
      let additional = if axis == 0 { r - old_r } else { e - old_e }
      assert_true(additional >= request_whole_source_initial_quotation_bytes)
      let usage = @resources.ledger_usage(parent.ledger)
      let limits = @resources.ledger_limits(parent.ledger)
      let available = if axis == 0 {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes
      }
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if axis == 0 {
          available - additional + shortage
        } else {
          0L
        },
        if axis == 1 {
          available - additional + shortage
        } else {
          0L
        },
      ).unwrap()
      let result = reserve_request_program_plan(parent, input)
      if shortage == 0L {
        assert_true(result is Ok(_))
        assert_true(parent.phase == ProgramPlanReserved)
      } else {
        assert_true(result is Err(Capacity(_)))
        assert_true(parent.phase == ProgramPlanQuoted)
      }
      assert_true(parent.program_domain_quote is None)
      assert_true(!parent.program_body_attempted)
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "Request Whole domain retains each original route before its plural Plan" {
  let (parent, input, prepared, request) = request_whole_source_fixture()
  let original_capacity = parent.program_capacity.unwrap()
  let (direct, sources) = reserve_request_whole_source_construction(
    parent, input, request,
  ).unwrap()
  assert_eq(sources.length(), 2)
  assert_true(parent.phase == ProgramPlanReserved)
  assert_true(parent.program_domain_quote is None)
  assert_true(
    physical_equal(original_capacity, parent.program_capacity.unwrap()),
  )
  for index in 0..<sources.length() {
    let (stage, source_index, _) = @publication_host.client_direct_acquisition_occurrence_at(
      direct, index,
    ).unwrap()
    assert_true(
      @publication_host.client_source_acquisition_matches_program(
        prepared,
        stage,
        source_index,
        sources[index],
      ),
    )
  }
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let declaration = pure_provider_declaration()
  let capacities = sources.map(source => {
    prepare_installed_whole_source_capacity(
      prepared,
      source,
      declaration,
      contracts,
      installed_row_input_policy(4, 4096, 256, 16, 4),
      None,
    ).unwrap()
  })
  let plan = prepare_installed_managed_whole_sources_plan(
    prepared,
    request,
    capacities,
    [4096L, 4096L],
    [4096L, 4096L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=true,
    provider_factory=_ => [],
    runtime_admission=true,
  ).unwrap()
  assert_eq(plan.whole_sources.length(), 2)
  assert_eq(plan.captures.length(), 0)
  for index in 0..<capacities.length() {
    assert_true(
      physical_equal(
        prepared_installed_managed_whole_source_capacity(plan, index).unwrap(),
        capacities[index],
      ),
    )
    assert_true(
      prepared_installed_managed_capture_acquisition(plan, index) is None,
    )
  }
  assert_true(
    prepared_installed_managed_whole_source_capacity(plan, -1) is None,
  )
  assert_true(
    prepared_installed_managed_whole_source_capacity(plan, capacities.length())
    is None,
  )
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let owner = begin_request_capture_managed_run(parent, request).unwrap()
  let logical_graph = @publication_host.prepared_client_graph(prepared)
  assert_true(@strategy.graph_captured_prefix(logical_graph) > 0)
  assert_true(source_input_local_tasks_control_capacity(logical_graph) is None)
  let (physical_graph, _, _, _) = installed_managed_capture_publication_geometry_original(
    owner, prepared, request,
  ).unwrap()
  assert_true(
    @strategy.source_inputs_dag_matches_original(physical_graph, logical_graph),
  )
  assert_eq(@strategy.graph_captured_prefix(physical_graph), 0)
  assert_true(
    source_input_local_tasks_control_capacity(physical_graph) is Some(_),
  )
  // No DAG was opened and no physical Source exists in this component. Port
  // retirement may report that narrow absence; it must not accept Query's
  // distinct purpose or retire/reissue the managed Run/request itself.
  assert_true(owner.source_free_captured is None)
  assert_true(retire_installed_whole_source_ports(owner, prepared, request))
  assert_false(retire_installed_query_capture_ports(owner, prepared, request))
  assert_true(owner.original is Some(_))
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request Whole domain exact and one-short keep the same original reservation" {
  for axis in 0..<2 {
    for shortage in [0L, 1L] {
      let (parent, input, prepared, request) = request_whole_source_fixture()
      let direct = installed_direct_occurrences_owned(Pure(prepared)).unwrap()
      let count = @publication_host.client_direct_acquisition_occurrence_count(
        direct,
      )
      let bound = @checked.source_execution_count(
        @strategy.graph_program(
          @publication_host.prepared_client_graph(prepared),
        ),
      )
      let (old_r, old_e) = installed_direct_occurrences_layout(
        @strategy.graph_captured_prefix(
          @publication_host.prepared_client_graph(prepared),
        ),
      ).unwrap()
      let (new_r, new_e) = installed_direct_occurrences_layout(bound).unwrap()
      let mut bytes = Int64::max(
        Int64::max(0L, new_r - old_r),
        Int64::max(0L, new_e - old_e),
      )
      bytes += request_whole_source_observer_bytes().unwrap()
      bytes += request_whole_source_route_frontier_bytes(
        count,
        request_whole_source_route_scan_count(prepared, direct).unwrap(),
      ).unwrap()
      for index in 0..<count {
        let (stage, source_index, _) = @publication_host.client_direct_acquisition_occurrence_at(
          direct, index,
        ).unwrap()
        guard select_installed_source_input(
            prepared, request, stage, source_index,
          ).unwrap()
          is @sourceviews.WholeInputRoute(source) else {
          fail("the original complete input cannot be rewritten as Query")
        }
        bytes += request_whole_source_input_construction_bytes(source).unwrap()
      }
      let usage = @resources.ledger_usage(parent.ledger)
      let limits = @resources.ledger_limits(parent.ledger)
      let available = if axis == 0 {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes
      }
      assert_true(available >= bytes)
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if axis == 0 {
          available - bytes + shortage
        } else {
          0L
        },
        if axis == 1 {
          available - bytes + shortage
        } else {
          0L
        },
      ).unwrap()
      let result = reserve_request_whole_source_construction(
        parent, input, request,
      )
      if shortage == 0L {
        assert_true(result is Ok(_))
        assert_true(parent.phase == ProgramPlanReserved)
      } else {
        assert_true(result is Err(Preparation(Capacity(_))))
        assert_true(parent.phase == ProgramBodyFailed)
      }
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "Request Whole domain does not revive its original after current loss" {
  let current = Ref(true)
  let (parent, input, _, request) = request_whole_source_fixture(current=() => {
    current.val
  })
  current.val = false
  assert_true(
    reserve_request_whole_source_construction(parent, input, request) is Err(_),
  )
  assert_true(parent.phase != ProgramPlanReserved)
  current.val = true
  assert_true(
    reserve_request_whole_source_construction(parent, input, request) is Err(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static JOIN Plan describes the original Sources without preparing a Run" {
  let (parent, input, prepared, _) = request_whole_source_fixture()
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 2)
  let before = parent.phase
  let wire = request_prepared_static_plan_view(
    parent,
    input,
    request_program_module_manifests(),
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(wire.contains("actql-plan-view/0.1"), msg=wire)
  assert_true(wire.contains("\"compiled_plan_cid\""), msg=wire)
  assert_true(!wire.contains("\"run_ref\""), msg=wire)
  assert_true(parent.phase == before)
  assert_true(parent.submitted_intent is None)
  assert_true(!parent.program_body_attempted)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
