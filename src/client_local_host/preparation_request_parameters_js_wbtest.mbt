///|
test "Request-owned Parameters retain default and original supplied values through the actual module and Run" {
  let text =
    #|{"version":"actql/0.1","id":"request-owned-parameters","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"value":"id + $n"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  for explicit in [false, true] {
    let supplied = if explicit {
      Some(funded_value_cursor("{\"n\":9}"))
    } else {
      None
    }
    let (parent, _, source, input) = registration_parent_fixture(
      text~,
      supplied~,
      computation_limits=Some(
        (
          @publication_host.client_standard_program_preparation_limits(),
          @publication_host.client_standard_effect_computation_limits(),
        ),
      ),
    )
    let declarations = parent.parameter_declarations.unwrap()
    assert_true(declarations.phase == RetainedSource)
    assert_true(physical_equal(parent.parameter_source.unwrap(), source))
    finish_request_computation_preparation(parent, input).unwrap()
    assert_true(
      parent.parameter_declarations is None && parent.parameter_source is None,
    )
    assert_true(
      declarations.phase == Retired &&
      declarations.input is None &&
      declarations.source is None,
    )
    let prepared = parent.compiled_program.unwrap()
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=_ => [],
    ).unwrap()
    let plan = parent.program_source_free.unwrap()
    let request = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "request-owned-parameters",
    ).unwrap()
    let run = begin_request_program_managed_run(parent, request).unwrap()
    let setup = open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
        true,
      )
      .unwrap()
      .unwrap()
    let output = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
      true
    }).unwrap()
    assert_eq(
      output.rows().unwrap(),
      if explicit {
        ["{\"id\":1,\"value\":10}"]
      } else {
        ["{\"id\":1,\"value\":8}"]
      },
    )
    assert_true(output.close())
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(parent.ledger).attempts, 1)
  }
}

///|
test "Request-owned Parameters preserve the original invalid default and failed reader until cleanup" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let text = request_check_wire.replace(
    old="\"id\":\"request-check\"",
    new="\"id\":\"request-check\",\"params\":{\"n\":{\"type\":\"number\",\"default\":\"bad\"}}",
  )
  request_check_source(parent, input, text~) |> ignore
  {
    let result = prepare_request_computation_check_preparation(
      parent,
      input,
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
    )
    guard result is Err(ParameterDeclarations(original)) else {
      fail(
        "Original invalid numeric default must not become a generic check phase failure",
      )
    }
    let declarations = parent.parameter_declarations.unwrap()
    let reader = parameter_declaration_preflight_outcome(declarations).unwrap().0.unwrap()
    assert_true(
      @parameters.finish_declaration_read(reader) is Err(same) &&
      same == original,
    )
    assert_true(
      parent.phase == ProgramCheckFailed && parent.program_check is None,
    )
    assert_true(
      parent.compiled_program is None && parent.parameter_source is None,
    )
  }
  let declarations = parent.parameter_declarations.unwrap()
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(declarations.phase == Retired && declarations.input is None)
  assert_true(
    parent.parameter_declarations is None && parent.parameter_source is None,
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request-owned Parameters refuse before the first declaration allocation with no external prelude" {
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    request_check_source(parent, input) |> ignore
    let limits = @resources.ledger_limits(parent.ledger)
    let base = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - base.0 - parameter_preflight_initial_bytes + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - base.1 - parameter_preflight_initial_bytes + 1L
      },
    ).unwrap()
    let result = prepare_request_program_check_preparation(
      parent,
      input,
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    )
    assert_true(
      if retention {
        result is Err(ParameterPreparation(Capacity(Resource(RetentionLimit))))
      } else {
        result is Err(ParameterPreparation(Capacity(Resource(ExecutionLimit))))
      },
    )
    assert_true(
      parent.parameter_declarations is None && parent.parameter_source is None,
    )
    assert_true(parent.program_check is None && parent.compiled_program is None)
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input).unwrap(),
      base,
    )
    @resources.settle_capacity(parent.ledger, short).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
