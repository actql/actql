///|
fn request_model_module_declaration() -> @row_source_host.RowDeclaration {
  @row_source_host.generate_row_declaration(
    "model/source-fixture",
    "model_fixture",
    "model_fixture/0.1",
    [
      {
        resource: "r",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "number", nullable: false, },
          { name: "amount", value_type: "number", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 2,
    },
  ).unwrap()
}

///|
// Real Request/compiler/Source declaration/module/Scope owners. Installation
// and Resource admission are explicit component fixtures, not ordinary IO.
fn request_model_module_fixture(
  captured : Bool,
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  @publication_host.ClientTaskCompilation,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @row_source_host.RowDeclaration,
) raise {
  let declaration = request_model_module_declaration()
  let (parent, input, prepared) = request_model_input_fixture(
    captured~,
    current~,
    declaration=if captured { Some(declaration) } else { None },
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  if captured {
    for stage in 0..<2 {
      let facts = @publication_host.prepared_client_source_evidence_facts(
        prepared, stage, 0,
      ).unwrap()
      assert_eq(facts.source_ref, declaration.views[0].source_ref)
      assert_eq(facts.source_contract_cid, declaration.views[0].view_cid)
    }
  }
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let compilation = prepare_request_model_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  // The first real compiled Run/Definition below must already be backed by
  // this SAME capacity, alongside the original Graph and compiler output.
  assert_true(
    parent.program_invocation_quote is Some((r, e)) &&
    @resources.preparation_capacity_working_extents(
      parent.program_capacity.unwrap(),
      input,
    ) ==
    Ok((r, e)),
  )
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "model-module-fixture", "same-original", "2026-10-31T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "model-module-fixture",
  ).unwrap()
  (
    parent, input, prepared, compilation, compiled, definition, request, contracts,
    holder, declaration,
  )
}

///|
test "Model module constructor reserves before factory and retains same module through Scope adoption and retirement" {
  for captured in [false, true] {
    let (
      parent,
      input,
      prepared,
      compilation,
      compiled,
      definition,
      request,
      contracts,
      holder,
      declaration,
    ) = request_model_module_fixture(captured)
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let calls = Ref(0)
    let observed = Ref(true)
    let factory = (_ : @execution.ExecutionCapacity) => {
      calls.val += 1
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      observed.val = observed.val &&
        parent.phase == Selecting &&
        during.0 > before.0 &&
        during.1 > before.1
      observed.val = observed.val &&
        abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
      []
    }
    let graph = compilation.infers[0]
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared,
    ).unwrap()
    let plan = if captured {
      let original = match
        prepare_request_model_capture_module(
          parent,
          input,
          request,
          compiled,
          definition,
          compilation,
          [declaration, declaration],
          original_row_query_contract_fixture,
          original_row_evidence_contract_fixture,
          [4096L, 4096L],
          [2048L, 2048L],
          contracts,
          true,
          0,
          factory,
        ) {
        Ok(value) => value
        Err(ModelSource(@row_source_host.Source(reason))) =>
          fail("original Source: " + @debug.to_string(reason))
        Err(issue) => {
          let original : Error = issue
          fail(@debug.to_string(original))
        }
      }
      assert_true(
        parent.program_captured is Some(same) && physical_equal(same, original),
      )
      assert_eq(original.captures.length(), 2)
      for index in 0..<2 {
        let capture = original.captures[index]
        assert_true(
          capture.acquisition is Some(acquisition) &&
          physical_equal(
            @row_source_host.row_acquisition_requirement(acquisition),
            capture.requirement,
          ),
        )
      }
      prepare_installed_mock_model_capture_plan_binding(
        original, compiled, definition, occurrence, graph, effect_model_plan_limits,
        500L, 700L, 20, 20, 20,
      ).unwrap()
    } else {
      let original = prepare_request_model_source_free_module(
        parent, input, request, compiled, definition, compilation, contracts, true,
        0, factory,
      ).unwrap()
      assert_true(
        parent.program_source_free is Some(same) &&
        physical_equal(same, original),
      )
      prepare_installed_mock_model_source_free_plan(
        original, request, compiled, definition, occurrence, graph, effect_model_plan_limits,
        500L, 700L, 20, 20, 20,
      ).unwrap()
    }
    assert_eq(calls.val, 1)
    assert_true(observed.val)
    assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
    let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
    complete_request_model_preparation(parent, input, plan).unwrap()
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    let run = begin_request_model_managed_run(parent, request, scope).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope, compiled, definition, graph, true,
      ).unwrap(),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
// The component remains an explicit constructor port. Real Request capacity
// and original lowering are exercised here; ordinary physical IO is separate.
test "source-free Model component enters its one module after original input and capacity are retained" {
  let (
    parent,
    input,
    _,
    compilation,
    compiled,
    definition,
    request,
    contracts,
    holder,
    _,
  ) = request_model_module_fixture(false)
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let backed = Ref(false)
  let input_prefix : Ref[@execution.GeneratedSequence?] = Ref(None)
  let original = prepare_request_model_source_free_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    contracts,
    true,
    1,
    _ => [],
    component_factory=Some((extent, prefix, _) => {
      calls.val += 1
      input_prefix.val = Some(prefix)
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      )
      backed.val = parent.phase == Selecting &&
        during is Ok((r, e)) &&
        r > before.0 &&
        e > before.1
      @local.managed_provider(_ => false, _ => Some(extent), (_, _, _, _, _) => {
        Err(@connector.ComputeUnsupported)
      })
    }),
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_true(backed.val && input_prefix.val is Some(_))
  assert_true(
    parent.program_source_free is Some(same) && physical_equal(same, original),
  )
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model module current refusal enters no factory and preserves original failed Request custody" {
  let armed = Ref(false)
  let (
    parent,
    input,
    _,
    compilation,
    compiled,
    definition,
    request,
    contracts,
    holder,
    _,
  ) = request_model_module_fixture(false, current=() => !armed.val)
  let calls = Ref(0)
  armed.val = true
  assert_true(
    prepare_request_model_source_free_module(
      parent,
      input,
      request,
      compiled,
      definition,
      compilation,
      contracts,
      true,
      0,
      _ => {
        calls.val += 1
        []
      },
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_eq(calls.val, 0)
  assert_true(
    parent.phase == ProgramBodyFailed &&
    parent.program_source_free is None &&
    parent.program_compilation is Some(_),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model captured module retains original protocol refusal without factory or second constructor" {
  let (
    parent,
    input,
    _,
    compilation,
    compiled,
    definition,
    request,
    contracts,
    holder,
    declaration,
  ) = request_model_module_fixture(true)
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let invoke = () => {
    prepare_request_model_capture_module(
      parent,
      input,
      request,
      compiled,
      definition,
      compilation,
      [declaration, declaration],
      "{}",
      original_row_evidence_contract_fixture,
      [4096L, 4096L],
      [2048L, 2048L],
      contracts,
      true,
      0,
      _ => {
        calls.val += 1
        []
      },
    )
  }
  assert_true(invoke() is Err(ModelSource(@row_source_host.InvalidContracts)))
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(invoke() is Err(Preparation(ForeignOriginal)))
  assert_eq(calls.val, 0)
  assert_true(
    parent.phase == ProgramBodyFailed && parent.program_captured is None,
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model compiler metadata grow refusal keeps emitted artifact on original failed Request before Run issuance" {
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let observed = Ref(false)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    if selected.val is Some(owner) &&
      owner.program_compilation is Some(_) &&
      owner.program_invocation_quote is Some(_) {
      observed.val = true
      false
    } else {
      true
    }
  })
  let held = borrow_request_model_plan_input(parent, input).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  selected.val = Some(parent)
  assert_true(
    prepare_request_model_compilation(
      parent,
      input,
      graph,
      contracts,
      manifests~,
      compilation_limits=limits,
    )
    is Err(Preparation(Capacity(_))),
  )
  selected.val = None
  assert_true(
    observed.val &&
    parent.phase == ProgramBodyFailed &&
    parent.program_compilation is Some(@publication_host.Tasks(original)) &&
    physical_equal(original.infers[0], graph) &&
    parent.program_invocation_quote is Some(_),
  )
  assert_true(
    parent.program_source_free is None && parent.program_captured is None,
  )
  assert_false(@resources.return_preparation_body_borrow(held).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model Scope refuses a copied module even with same original compiler and unchanged Plan fields" {
  let (parent, input, plan, held) = request_model_fixture()
  let original = plan.source_free.unwrap()
  let copied = { ..original, configuration: original.configuration, }
  let foreign = { ..plan, source_free: Some(copied), }
  let before = request_preparation_accounting(parent)
  assert_true(
    prepare_request_model_read_scope(parent, input, foreign)
    is Err(ForeignOriginal),
  )
  assert_true(parent.program_model is None && parent.phase == ModelPlanReserved)
  assert_eq(request_preparation_accounting(parent), before)
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  complete_request_model_preparation(parent, input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(held).unwrap())
  let run = begin_request_model_managed_run(parent, plan.request, scope).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      plan.compiled,
      plan.definition,
      plan.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
