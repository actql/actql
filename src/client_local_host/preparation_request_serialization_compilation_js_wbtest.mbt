///|
// Existing source-free terminal Serialization purpose, authored independently
// of its compiler output. This fixture opens no provider, Store or public Run.
let request_serialization_document : String =
  #|{"version":"actql/0.1","id":"request-content-compilation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}

///|
// Real checker/compiler and Local prefix, with an explicit original Resource
// admission. This is not a standard Host, Store or public Content fixture.
// Private component fixture, never a Host ABI or a physical admission.
struct RequestSerializationPlanFixture {
  parent : ClientRequestPreparation[Array[Int]]
  input : Array[Int]
  prepared : @publication_host.PreparedClientProgram
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]
  request : @publication_host.ClientRequestIdentity
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
}

///|
fn request_serialization_plan_fixture(
  current? : () -> Bool = () => true,
) -> RequestSerializationPlanFixture raise {
  let (parent, child, _, input) = registration_parent_fixture(
    text=request_serialization_document,
    current~,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("authored terminal Serialization check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let component = @publication_host.issue_prepared_client_serialization_plan_graph(
    prepared,
    0,
    1,
    policy,
    2,
    128,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let compilation = prepare_request_serialization_compilation(
    parent,
    input,
    component,
    contracts,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-serialization", "same-original", "2026-10-31T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-request-serialization",
  ).unwrap()
  let (_, execution, measurement) = client_local_execution_limits(max_rows=2)
  {
    parent,
    input,
    prepared,
    holder,
    request,
    compiled,
    definition,
    execution,
    measurement,
  }
}

///|
fn request_serialization_preparation_fixture(
  current? : () -> Bool = () => true,
  before_plan? : (ClientRequestPreparation[Array[Int]], Array[Int]) -> Unit = (
    _,
    _,
  ) => (),
  construct_plan? : (
    () -> Result[
      ClientInstalledManagedSerializationPreparation,
      ClientInstalledManagedRunIssue,
    ],
  ) -> ClientInstalledManagedSerializationPreparation raise = construct => {
    construct().unwrap()
  },
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  ClientInstalledManagedSerializationPreparation,
  @publication_host.ClientRequestIdentity,
) raise {
  let fixture = request_serialization_plan_fixture(current~)
  let {
    parent,
    input,
    prepared,
    holder,
    request,
    compiled,
    definition,
    execution,
    measurement,
  } = fixture
  before_plan(parent, input)
  let selected = construct_plan(() => {
    prepare_request_serialization_plan(
      parent,
      input,
      request,
      compiled,
      definition,
      execution,
      measurement,
      None,
    )
  })
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  (parent, input, prepared, selected, request)
}

///|
test "Content Plan retains its own record and limits only after both same-parent byte bounds admit them" {
  // Actual selected record: one header and ten original references. Actual
  // LedgerLimits: one header and six scalar words. Domain links were already
  // admitted by borrow_request_content_plan_input; no second link charge.
  let added = 2L * 16L + 10L * 8L + 6L * 8L
  for retention in [true, false] {
    let owner : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
    let original_input : Ref[Array[Int]?] = Ref(None)
    let blocker : Ref[@resources.CapacityReservation?] = Ref(None)
    let before : Ref[(Int64, Int64)] = Ref((0L, 0L))
    let spent = Ref(0L)
    let (parent, input, _, selected, _) = request_serialization_preparation_fixture(
      before_plan=(parent, input) => {
        owner.val = Some(parent)
        original_input.val = Some(input)
        let capacity = parent.program_capacity.unwrap()
        let extents = @resources.preparation_capacity_working_extents(
          capacity, input,
        ).unwrap()
        before.val = extents
        spent.val = parent.program_artifact_work_spent
        let limits = @resources.ledger_limits(parent.ledger)
        blocker.val = Some(
          @resources.reserve_capacity(
            parent.ledger,
            if retention {
              limits.retained_bytes - extents.0 - added + 1L
            } else {
              0L
            },
            if retention {
              0L
            } else {
              limits.execution_bytes - extents.1 - added + 1L
            },
          ).unwrap(),
        )
      },
      construct_plan=construct => {
        let parent = owner.val.unwrap()
        let input = original_input.val.unwrap()
        let result = construct()
        assert_true(
          if retention {
            result is Err(Preparation(Resource(RetentionLimit)))
          } else {
            result is Err(Preparation(Resource(ExecutionLimit)))
          },
        )
        assert_true(parent.program_content is NoContent)
        assert_true(parent.program_content_request is None)
        assert_true(parent.phase == ContentPlanReserved)
        assert_eq(parent.program_artifact_work_spent, spent.val)
        assert_eq(
          @resources.preparation_capacity_working_extents(
            parent.program_capacity.unwrap(),
            input,
          ),
          Ok(before.val),
        )
        @resources.settle_capacity(parent.ledger, blocker.val.unwrap()).unwrap()
        let selected = construct().unwrap()
        assert_eq(
          @resources.preparation_capacity_working_extents(
            parent.program_capacity.unwrap(),
            input,
          ),
          Ok((before.val.0 + added, before.val.1 + added)),
        )
        assert_eq(parent.program_artifact_work_spent, spent.val)
        selected
      },
    )
    assert_true(
      parent.program_content is SerializationContent(original) &&
      physical_equal(original, selected),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_true(physical_equal(original_input.val.unwrap(), input))
  }
}

///|
test "Content Plan growth fences original-current reentry and retains its failed original for cleanup" {
  let armed = Ref(false)
  let entered = Ref(false)
  let fenced = Ref(false)
  let owner : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let reenter : Ref[
    (() -> Result[
      ClientInstalledManagedSerializationPreparation,
      ClientInstalledManagedRunIssue,
    ])?,
  ] = Ref(None)
  let fixture = request_serialization_plan_fixture(current=() => {
    if armed.val {
      if !entered.val {
        entered.val = true
        let parent = owner.val.unwrap()
        fenced.val = parent.phase == Selecting &&
          reenter.val.unwrap()() is Err(ForeignOriginal) &&
          abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
      }
      false
    } else {
      true
    }
  })
  let parent = fixture.parent
  owner.val = Some(parent)
  let construct = () => {
    prepare_request_serialization_plan(
      parent,
      fixture.input,
      fixture.request,
      fixture.compiled,
      fixture.definition,
      fixture.execution,
      fixture.measurement,
      None,
    )
  }
  let before = request_preparation_accounting(parent)
  reenter.val = Some(construct)
  armed.val = true
  assert_true(construct() is Err(Preparation(_)))
  armed.val = false
  assert_true(entered.val && fenced.val)
  assert_true(parent.phase == ContentPlanReserved)
  assert_true(parent.program_content is NoContent)
  let absolute = parent.program_domain_quote.unwrap()
  assert_eq(absolute, (before.4 + 160L, before.5 + 160L))
  assert_eq(request_preparation_accounting(parent), before)
  // The original resource failure is sticky; a later true callback cannot
  // authorize construction or erase it. Retain the same quote for cleanup.
  assert_true(construct() is Err(Preparation(_)))
  assert_eq(parent.program_domain_quote, Some(absolute))
  assert_true(parent.program_content is NoContent)
  assert_eq(request_preparation_accounting(parent), before)
  reenter.val = None
  assert_false(
    @resources.return_preparation_body_borrow(fixture.holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "same Request source-free Content adopts one compiler and starts its retained prefix once with one current observation" {
  let calls = Ref(0)
  let during_start : Ref[ClientInstalledManagedRun?] = Ref(None)
  let reentry_fenced = Ref(false)
  let (parent, input, prepared, selected, request) = request_serialization_preparation_fixture(current=() => {
      calls.val += 1
      if during_start.val is Some(run) {
        reentry_fenced.val = retire_installed_managed_run(run)
          is Err(CleanupPending)
      }
      true
    },
  )
  let ledger = parent.ledger
  let spent = parent.program_artifact_work_spent
  assert_true(spent > 0L)
  guard parent.program_compilation is Some(@publication_host.Tasks(compilation)) else {
    fail("retained compiler original")
  }
  assert_true(
    @publication_host.client_compiled_run_matches_tasks(
      selected._observed_compiled,
      prepared,
      compilation,
    ),
  )
  let before = @resources.ledger_usage(ledger)
  complete_request_serialization_preparation(parent, input, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_true(run.ledger is Some(original) && physical_equal(original, ledger))
  assert_true(
    run.content is SerializationContent(original) &&
    physical_equal(original, selected),
  )
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
  let observed = calls.val
  during_start.val = Some(run)
  let prefix = start_installed_managed_serialization_prefix(
    run, prepared, selected,
  ).unwrap()
  during_start.val = None
  assert_eq(calls.val, observed + 1)
  assert_true(reentry_fenced.val)
  assert_true(physical_equal(prefix.ledger, ledger))
  assert_true(
    run.serialization_prefix is Some(original) &&
    physical_equal(original, prefix),
  )
  let after_start = @resources.ledger_usage(ledger)
  assert_true(
    start_installed_managed_serialization_prefix(run, prepared, selected)
    is Err(AlreadyBound),
  )
  assert_eq(calls.val, observed + 1)
  assert_eq(@resources.ledger_usage(ledger), after_start)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  let mut output : @execution.CompletedOutput? = None
  let mut polls = 0
  while output is None && polls < 1000 {
    polls += 1
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => output = Some(value)
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original source-free prefix did not complete")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 100).unwrap(),
    "{\"id\":2}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 10000, 1000, 100).unwrap(),
    "{\"id\":1}",
  )
  assert_true(client_serialization_prefix_work(prefix).unwrap() > 0L)
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.live_reservations, 0)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  assert_eq(retired.attempts, after_start.attempts)
  assert_true(
    start_installed_managed_serialization_prefix(run, prepared, selected)
    is Err(ForeignOriginal),
  )
}

///|
test "source-free Content refuses changed originals and retains an unreturned or pending prefix until its actual ACK" {
  let (parent, input, prepared, selected, request) = request_serialization_preparation_fixture()
  let changed = {
    ..selected,
    request: @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "other-request",
    ).unwrap(),
  }
  let before = request_preparation_accounting(parent)
  assert_true(
    complete_request_serialization_preparation(parent, input, changed)
    is Err(ForeignOriginal),
  )
  assert_eq(request_preparation_accounting(parent), before)
  complete_request_serialization_preparation(parent, input, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_true(
    start_installed_managed_serialization_prefix(run, prepared, changed)
    is Err(ForeignOriginal),
  )
  // An unreturned constructor has no physical stop proof. Keep its original
  // reservation and block Run retirement until the SAME child actually ACKs.
  let reservation = @resources.reserve_attempt(parent.ledger, 0L, 7L, 5L).unwrap()
  let prefix : ClientSerializationPrefix = {
    child: None,
    ledger: parent.ledger,
    reservation,
    final_work: None,
    cleanup_busy: false,
    child_cleaned: false,
    released: false,
    dependencies: [],
    pending_start: false,
    parent_busy: false,
    composed: None,
  }
  run.serialization_prefix = Some(prefix)
  assert_false(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.reservation_open(reservation))
  let closes = Ref(0)
  prefix.child = Some(
    @local.managed_provider_execution(
      _ => Ok(@local.managed_provider_continue(1L, 1L)),
      () => true,
      () => true,
      () => {
        closes.val += 1
        Ok(closes.val > 1)
      },
    ),
  )
  assert_false(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  assert_eq(closes.val, 2)
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "source-free Serialization compilation remains on original Request capacity and compiler output" {
  let (parent, child, _, input) = registration_parent_fixture(
    text=request_serialization_document,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("authored source-free Serialization check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let component = @publication_host.issue_prepared_client_serialization_plan_graph(
    prepared,
    0,
    1,
    policy,
    2,
    128,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let ledger = parent.ledger
  let capacity = parent.program_capacity.unwrap()
  let compilation = prepare_request_serialization_compilation(
    parent,
    input,
    component,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  assert_true(physical_equal(parent.ledger, ledger))
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  guard parent.program_compilation is Some(@publication_host.Tasks(original)) else {
    fail("same retained Serialization TaskCompilation")
  }
  assert_true(physical_equal(original, compilation))
  assert_true(
    physical_equal(
      @publication_host.client_task_compilation_serialization(compilation).unwrap(),
      component,
    ),
  )
  assert_true(parent.phase == ContentPlanReserved)
  assert_true(parent.program_artifact_work_spent > 0L)
  let spent = parent.program_artifact_work_spent
  assert_true(
    prepare_request_serialization_compilation(
      parent,
      input,
      component,
      contracts,
      manifests~,
      compilation_limits~,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
fn request_keyed_serialization_component(
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedKeyedPreparation,
) -> @publication_host.ClientSerializationPlanGraph {
  @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
    prepared,
    selected.serialization_task,
    selected.serialization_step,
    3,
    4096,
    1000000,
    @publication_host.client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
}

///|
test "same Request keyed Serialization retains its one original compiler through Content adoption and retirement" {
  let (parent, input, prepared, selected, request) = request_content_fixture()
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let component = request_keyed_serialization_component(prepared, selected)
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let before = @resources.ledger_usage(parent.ledger)
  // The source-free constructor remains confined to its original purpose.
  assert_true(
    prepare_request_serialization_compilation(
      parent,
      input,
      component,
      selected.installed_contracts,
      manifests~,
      compilation_limits=limits,
    )
    is Err(Installed(Unsupported)),
  )
  let compilation = prepare_request_keyed_serialization_compilation(
    parent,
    input,
    selected,
    component,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let spent = parent.program_artifact_work_spent
  assert_true(spent > 0L)
  assert_eq(spent, parent.program_artifact_plan_encoding_nodes.val)
  assert_true(
    @publication_host.client_task_compilation_serialization(compilation)
    is Some(original) &&
    physical_equal(original, component),
  )
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-keyed-content", "same-original", "2026-10-31T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  @publication_host.validate_client_run_binding(
    request, prepared, compiled, definition,
  ).unwrap()
  let compiled_usage = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_keyed_serialization_compilation(
      parent,
      input,
      selected,
      component,
      manifests~,
      compilation_limits=limits,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), compiled_usage)
  assert_eq(parent.program_artifact_work_spent, spent)
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  let held = borrow_request_program_preparation(parent).unwrap()
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_true(
    parent.program_compilation is None &&
    parent.program_domain_compilation_inputs is None,
  )
  assert_true(
    run.content
    is KeyedContent(original, Some(@publication_host.Tasks(artifact))) &&
    physical_equal(original, selected) &&
    physical_equal(artifact, compilation),
  )
  assert_true(
    run.ledger is Some(original) && physical_equal(original, parent.ledger),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, before.attempts)
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(run.content is NoContent)
  assert_true(
    @resources.preparation_body_borrow_value(held) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(@resources.return_preparation_body_borrow(held).unwrap())
  retire_installed_managed_run(run).unwrap()
  let retired = @resources.ledger_usage(parent.ledger)
  assert_eq(retired.live_reservations, 0)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  assert_eq(parent.program_artifact_work_spent, spent)
}

///|
test "keyed Request compiler refuses foreign input Plan coordinates and completion without changing its original artifact" {
  let (parent, input, prepared, selected, request) = request_content_fixture()
  let (foreign, _, other_prepared, other, _) = request_content_fixture()
  let component = request_keyed_serialization_component(prepared, selected)
  let other_component = request_keyed_serialization_component(
    other_prepared, other,
  )
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let before = request_preparation_accounting(parent)
  for
    (candidate_input, candidate, graph) in [
      ([77], selected, component),
      (input, other, other_component),
      (
        input,
        { ..selected, serialization_step: selected.serialization_step + 1, },
        component,
      ),
    ] {
    assert_true(
      prepare_request_keyed_serialization_compilation(
        parent,
        candidate_input,
        candidate,
        graph,
        manifests~,
        compilation_limits=limits,
      )
      is Err(Preparation(ForeignOriginal)),
    )
    assert_eq(request_preparation_accounting(parent), before)
  }
  let compilation = prepare_request_keyed_serialization_compilation(
    parent,
    input,
    selected,
    component,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let copied = { ..selected, }
  let after = request_preparation_accounting(parent)
  assert_true(
    complete_request_content_preparation(parent, input, request, copied)
    is Err(ForeignOriginal),
  )
  assert_eq(request_preparation_accounting(parent), after)
  assert_true(
    parent.program_compilation is Some(@publication_host.Tasks(original)) &&
    physical_equal(original, compilation),
  )
  abort_request_preparation_after_cleanup(foreign).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Content prefix constructor failure cannot select a replacement on the same Request" {
  let fixture = request_serialization_plan_fixture()
  let parent = fixture.parent
  let before = @resources.ledger_usage(parent.ledger)
  let work = parent.program_artifact_work_spent
  // A quote value, not an allocation or Resource admission. The real prefix
  // is prepared first; adding its positive retained extent to this valid
  // Int64 endpoint fails only at the original workspace-composition boundary.
  let overflow = @execution.execution_capacity_inventory(
    [{ unit: QuotedBytes, count: 9223372036854775807L, copies: 1, }],
    [],
    RetainedAlongsideExecution,
  ).unwrap()
  let first = prepare_request_serialization_plan(
    parent,
    fixture.input,
    fixture.request,
    fixture.compiled,
    fixture.definition,
    fixture.execution,
    fixture.measurement,
    Some(overflow),
  )
  let attempted_phase = parent.phase
  let replacement = prepare_request_serialization_plan(
    parent,
    fixture.input,
    fixture.request,
    fixture.compiled,
    fixture.definition,
    fixture.execution,
    fixture.measurement,
    None,
  )
  let after = @resources.ledger_usage(parent.ledger)
  assert_false(
    @resources.return_preparation_body_borrow(fixture.holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(first is Err(InsufficientCapacity))
  assert_true(replacement is Err(ForeignOriginal))
  assert_true(attempted_phase == ProgramBodyFailed)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.planning_work, before.planning_work)
  assert_eq(parent.program_artifact_work_spent, work)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "foreign Content compiler tuple cannot consume the pending original prefix selection" {
  let fixture = request_serialization_plan_fixture()
  let foreign = request_serialization_plan_fixture()
  let parent = fixture.parent
  let first = prepare_request_serialization_plan(
    parent,
    fixture.input,
    fixture.request,
    foreign.compiled,
    foreign.definition,
    fixture.execution,
    fixture.measurement,
    None,
  )
  let refused_phase = parent.phase
  let after_foreign = request_preparation_accounting(parent)
  let selected = prepare_request_serialization_plan(
    parent,
    fixture.input,
    fixture.request,
    fixture.compiled,
    fixture.definition,
    fixture.execution,
    fixture.measurement,
    None,
  )
  let after_original = request_preparation_accounting(parent)
  assert_false(
    @resources.return_preparation_body_borrow(fixture.holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_false(
    @resources.return_preparation_body_borrow(foreign.holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(foreign.parent).unwrap()
  assert_true(first is Err(ForeignOriginal))
  assert_true(refused_phase == ContentPlanReserved)
  assert_true(selected is Ok(_))
  assert_eq(after_original, after_foreign)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(foreign.parent.ledger).live_reservations, 0)
}
