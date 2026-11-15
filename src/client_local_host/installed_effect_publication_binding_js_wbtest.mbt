///|
// Real same Request/Plan/Run numeric ownership with explicit component Source
// and typed authorization ports. No ordinary Account/physical ACK claim.
struct EffectPublicationSourceOriginal {
  parent : ClientRequestPreparation[Array[Int]]
  plan : ClientInstalledEffectManagedPlan
  run : ClientInstalledManagedRun
}

///|
fn effect_publication_source_document(document : String, count : Int) -> String {
  let inputs = StringBuilder()
  for index in 0..<count {
    if index > 0 {
      inputs.write_string(",")
    }
    inputs.write_string(
      "\"i" +
      index.to_string() +
      "\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}",
    )
  }
  document.replace(
    old="\"id\":\"apply\",\"inputs\":{\"input\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}},\"steps\":",
    new="\"id\":\"apply\",\"inputs\":{" +
      inputs.to_string() +
      "},\"from\":\"i0\",\"steps\":",
  )
}

///|
fn effect_publication_source_check(
  document : String,
  environment : @checked.CheckEnvironment,
  graph_work : Int,
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(536870912L),
    execution_bytes=Some(536870912L),
  ).unwrap()
  let (parent, input) = native_driver_parent(
    document,
    initial_limits=Some(limits),
  )
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let original = @publication_host.client_standard_effect_computation_limits()
  let selected = {
    ..original,
    program: { ..original.program, max_graph_work: graph_work, },
  }
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    selected,
  ).unwrap()
  (parent, input)
}

///|
fn effect_publication_source_original() -> EffectPublicationSourceOriginal raise {
  let parent : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let input : Ref[Array[Int]?] = Ref(None)
  let plan = effect_operation_source_plan_fixture(
    runtime_admission=true,
    document_for=Some(document => {
      effect_publication_source_document(document, 2)
    }),
    prepare_original=Some((document, selected_environment) => {
      let (owner, original_input) = effect_publication_source_check(
        document, selected_environment, 1000000,
      )
      finish_request_computation_preparation(owner, original_input).unwrap()
      let prepared = owner.compiled_effect.unwrap()
      reserve_request_effect_plan(owner, original_input).unwrap()
      parent.val = Some(owner)
      input.val = Some(original_input)
      prepared
    }),
  )
  let parent = parent.val.unwrap()
  let input = input.val.unwrap()
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let run = begin_request_effect_managed_run(parent, plan.request).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), parent.ledger))
  assert_eq(@resources.ledger_limits(parent.ledger).retained_bytes, 536870912L)
  assert_eq(@resources.ledger_limits(parent.ledger).execution_bytes, 536870912L)
  retain_installed_effect_operation_controls_before_construction(
    run,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  |> ignore
  { parent, plan, run, }
}

///|
fn effect_publication_source_capture(
  original : EffectPublicationSourceOriginal,
) -> (
  ClientInstalledSourceRead,
  @row_source_host.RowSourceCapture,
  @query.CapturedInputSource,
) raise {
  let plan = original.plan
  let (read, _, acquisition, _) = begin_installed_effect_managed_source_read(
    original.run,
    plan.declarations[0],
    0,
  ).unwrap()
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "dependency-boundary-original",
    _ => true,
    1024L,
    2048L,
  ).unwrap()
  @row_source_host.begin_row_run(rows, 128, 3, 3).unwrap()
  assert_eq(
    @row_source_host.accept_row_run_page(
      rows,
      @utf8.encode("[{\"id\":3},{\"id\":5}]"),
    ).unwrap(),
    2,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut done = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  (read, capture, @row_source_host.row_capture_source(capture).unwrap())
}

///|
fn effect_publication_binding_materials(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> (
  @publication_host.ClientEffectCompilation,
  @publication_host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @publication_host.PreparedClientEffectRun,
) {
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "scope", "effect-publication-binding", "2026-11-15T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let bound = @publication_host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap()
  (compilation, allowed, definition, bound)
}

///|
struct EffectPublicationValuesOriginal {
  parent : ClientRequestPreparation[Array[Int]]
  prepared : @publication_host.PreparedClientEffectComputation
  request : @publication_host.ClientRequestIdentity
  plan : ClientInstalledEffectManagedPlan
  run : ClientInstalledManagedRun
  compilation : @publication_host.ClientEffectCompilation
  allowed : @publication_host.ClientEffectAllowedRun
  definition : @publication.PublicationContract
  bound : @publication_host.PreparedClientEffectRun
  captured : @strategy.CapturedEffectRunDAG
  issued : @publication_host.ClientEffectSourceFreeInvocationOriginal
}

///|
fn effect_publication_values_original(
  current? : () -> Bool = () => true,
) -> EffectPublicationValuesOriginal raise {
  let (parent, input, prepared) = request_effect_compile_fixture(current~)
  reserve_request_effect_plan(parent, input).unwrap()
  let (plan, request) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let run = begin_request_effect_managed_run(parent, request).unwrap()
  retain_installed_effect_operation_controls_before_construction(
    run, prepared, request, plan,
  ).unwrap()
  |> ignore
  let (compilation, allowed, definition, bound) = effect_publication_binding_materials(
    prepared,
  )
  // The SAME Request Plan quote funded this exact receipt before the actual
  // managed DAG existed. Preserve its original issuer values, without admit.
  let issued = @publication_host.issue_client_effect_source_free_invocation_original(
    compilation,
    // Exact existing Local Values Host policy identity from local-values-plan.
    // Source-free Values has no checked Source provenance policy to unwrap.
    "sha256:" +
    @sha.hex(
      @utf8.encode(
        "{\"version\":\"actql-installed-local-policy/0.1\",\"name\":\"local-result-data\"}",
      ),
    ),
    1000000,
    100000,
    64,
  ).unwrap()
  let (_, captured, _) = open_installed_effect_managed_host(run, bound, [])
    .unwrap()
    .unwrap()
  {
    parent,
    prepared,
    request,
    plan,
    run,
    compilation,
    allowed,
    definition,
    bound,
    captured,
    issued,
  }
}

///|
fn bind_effect_publication_values(
  original : EffectPublicationValuesOriginal,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  bind_installed_effect_source_free_invocation(
    original.run,
    original.prepared,
    original.request,
    original.plan,
    original.bound,
    original.captured,
    original.compilation,
    @publication_host.client_effect_allowed_run_admission(original.allowed),
    original.definition,
    original.issued,
  )
}

///|
fn close_effect_publication_values(
  original : EffectPublicationValuesOriginal,
) -> Unit raise {
  assert_true(retire_installed_effect_captured_consumers(original.run).unwrap())
  retire_installed_managed_run(original.run).unwrap()
  assert_true(
    original.run.publication_definition is None &&
    original.run.publication_invocation is None,
  )
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).live_reservations,
    0,
  )
}

///|
test "closed Values publication retains exact early issuer tuple on same Request Run once" {
  let calls = Ref(0)
  let original = effect_publication_values_original(current=() => {
    calls.val += 1
    true
  })
  let before = calls.val
  let usage = @resources.ledger_usage(original.parent.ledger)
  let value = bind_effect_publication_values(original).unwrap()
  assert_eq(calls.val - before, 1)
  assert_true(
    physical_equal(
      value.0,
      @publication_host.client_effect_source_free_invocation_original_observation(
        original.issued,
      ),
    ),
  )
  assert_true(
    physical_equal(
      value.1,
      @publication_host.client_effect_source_free_invocation_original_invocation(
        original.issued,
      ),
    ),
  )
  assert_true(
    physical_equal(
      original.run.publication_definition.unwrap(),
      original.definition,
    ),
  )
  assert_true(
    physical_equal(original.run.publication_invocation.unwrap(), value.1),
  )
  assert_true(
    @resources.ledger_usage(original.parent.ledger).reserved_retention_bytes >
    usage.reserved_retention_bytes,
  )
  let now = calls.val
  assert_true(bind_effect_publication_values(original) is Err(WrongPhase))
  assert_eq(calls.val, now)
  close_effect_publication_values(original)
}

///|
test "closed Values publication rejects foreign owner Plan receipt and equal Definition copy before current" {
  let calls = Ref(0)
  let original = effect_publication_values_original(current=() => {
    calls.val += 1
    true
  })
  let foreign = effect_publication_values_original()
  let copy = @publication.admit_publication_contract(
    "run_definition",
    @publication.publication_contract_json(original.definition),
    1000000,
    100000,
    64,
  ).unwrap()
  let before = calls.val
  let usage = @resources.ledger_usage(original.parent.ledger)
  let admission = @publication_host.client_effect_allowed_run_admission(
    original.allowed,
  )
  assert_true(
    bind_installed_effect_source_free_invocation(
      { ..original.run, },
      original.prepared,
      original.request,
      original.plan,
      original.bound,
      original.captured,
      original.compilation,
      admission,
      original.definition,
      original.issued,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    bind_installed_effect_source_free_invocation(
      original.run,
      original.prepared,
      original.request,
      foreign.plan,
      original.bound,
      original.captured,
      original.compilation,
      admission,
      original.definition,
      original.issued,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    bind_installed_effect_source_free_invocation(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      original.bound,
      original.captured,
      original.compilation,
      admission,
      original.definition,
      foreign.issued,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    bind_installed_effect_source_free_invocation(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      original.bound,
      original.captured,
      original.compilation,
      admission,
      copy,
      original.issued,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(calls.val, before)
  assert_eq(@resources.ledger_usage(original.parent.ledger), usage)
  close_effect_publication_values(foreign)
  close_effect_publication_values(original)
}

///|
test "closed publication current fence blocks reentry and never publishes after current loss" {
  let action : Ref[() -> Unit] = Ref(() => ())
  let alive = Ref(true)
  let calls = Ref(0)
  let original = effect_publication_values_original(current=() => {
    calls.val += 1
    (action.val)()
    alive.val
  })
  let refused = Ref(false)
  action.val = () => {
    refused.val = bind_effect_publication_values(original) is Err(WrongPhase)
  }
  let before = calls.val
  bind_effect_publication_values(original).unwrap() |> ignore
  assert_true(refused.val)
  assert_eq(calls.val - before, 1)
  action.val = () => ()
  close_effect_publication_values(original)
  let lost = effect_publication_values_original(current=() => alive.val)
  alive.val = false
  assert_true(bind_effect_publication_values(lost) is Err(_))
  assert_true(
    lost.run.publication_definition is None &&
    lost.run.publication_invocation is None,
  )
  // The original failed owner remains available only for its cleanup. This
  // test never revives current and retries the publication issuer.
  close_effect_publication_values(lost)
}

///|
test "trusted Model transition rejects foreign receipt changed tuple reuse and abort without granting authority" {
  let early = installed_effect_early_publication_receipt_capacity()
  assert_eq(@execution.execution_capacity_retained_bytes(early), 48L)
  assert_eq(@execution.execution_capacity_execution_bytes(early), 80L)
  let ordinary = installed_effect_publication_binding_capacity(false)
  let model = installed_effect_publication_binding_capacity(true)
  assert_eq(@execution.execution_capacity_retained_bytes(ordinary), 64L)
  assert_eq(@execution.execution_capacity_execution_bytes(ordinary), 128L)
  // Includes the sealed record AND its explicitly boxed self Some carrier.
  assert_eq(@execution.execution_capacity_retained_bytes(model), 240L)
  assert_eq(@execution.execution_capacity_execution_bytes(model), 304L)
  let original = effect_publication_values_original()
  let observation = @publication_host.client_effect_source_free_invocation_original_observation(
    original.issued,
  )
  let invocation = @publication_host.client_effect_source_free_invocation_original_invocation(
    original.issued,
  )
  let transition = begin_installed_effect_model_publication_transition(
    original.run,
    original.prepared,
    original.request,
    original.plan,
    original.bound,
    original.captured,
    original.compilation,
    @publication_host.client_effect_allowed_run_admission(original.allowed),
    original.definition,
    observation,
    invocation,
  ).unwrap()
  // These are receipt-control negatives using genuine issued Values DATA.
  // They do not substitute for the CLOSED opaque Model-binding positive.
  let copy = { ..transition, }
  assert_true(
    finish_installed_effect_model_publication_transition(
      copy, observation, invocation,
    )
    is Err(WrongPhase),
  )
  let foreign = effect_publication_values_original()
  assert_true(
    finish_installed_effect_model_publication_transition(
      transition,
      @publication_host.client_effect_source_free_invocation_original_observation(
        foreign.issued,
      ),
      invocation,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    original.run.publication_definition is Some(definition) &&
    physical_equal(definition, original.definition) &&
    original.run.publication_invocation is None,
  )
  assert_false(original.run.effect_operation_opening)
  // A consumed-start Definition is not an issued publication. The ordinary
  // complete dependency entrance still refuses this failed original.
  let failed_usage = @resources.ledger_usage(original.parent.ledger)
  assert_true(
    prepare_installed_effect_dependency_inventory(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      [],
      [],
      [],
      [],
      1000000,
      100000,
      64,
    )
    is Err(Retired),
  )
  assert_eq(@resources.ledger_usage(original.parent.ledger), failed_usage)
  assert_true(
    finish_installed_effect_model_publication_transition(
      transition, observation, invocation,
    )
    is Err(WrongPhase),
  )
  assert_true(bind_effect_publication_values(original) is Err(WrongPhase))
  abort_installed_effect_model_publication_transition(transition)
  close_effect_publication_values(foreign)
  close_effect_publication_values(original)
}

///|
test "closed Source publication uses actual captured generation and original issuer before dependency export" {
  let original = effect_publication_source_original()
  let plan = original.plan
  let (read, capture, source) = effect_publication_source_capture(original)
  let (compilation, allowed, definition, bound) = effect_publication_binding_materials(
    plan.prepared,
  )
  let (_, captured, _) = open_installed_effect_managed_host(
      original.run,
      bound,
      [source],
    )
    .unwrap()
    .unwrap()
  let limits = original_keyed_content_workspace().export_limits
  let identity = @query.identify_captured_source_relation(
    source,
    3,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let requirement = plan.captures[0].requirement
  let logical = @publication_host.issue_captured_source_input_logical(
    plan.graph,
    source,
    identity,
    requirement,
  ).unwrap()
  let facts = @planning.query_source_evidence_fact_values(
    @planning.query_requirement_source_evidence_facts(requirement).unwrap(),
  )
  let authority = "sha256:" + "c".repeat(64)
  let evidence = @row_source_host.issue_row_source_evidence(
    plan.acquisitions[0],
    capture,
    identity,
    logical,
    authority,
    facts[3],
    "2026-11-15T00:00:01.000Z",
  ).unwrap()
  let value = issue_installed_effect_captured_invocation(
    original.run,
    plan.prepared,
    plan.request,
    plan,
    bound,
    captured,
    compilation,
    @publication_host.client_effect_allowed_run_admission(allowed),
    definition,
    source,
    @publication.run_evidence_value_json(evidence),
    @publication.run_evidence_value_json(logical),
    facts[0],
    facts[1],
    authority,
    facts[3],
    "2026-11-15T00:00:00.000Z",
    "2026-11-15T00:00:01.000Z",
    1000000,
    100000,
    64,
  ).unwrap()
  assert_true(
    physical_equal(original.run.publication_definition.unwrap(), definition),
  )
  assert_true(
    physical_equal(original.run.publication_invocation.unwrap(), value.1),
  )
  assert_true(
    @publication.run_evidence_value_json(value.0).contains(
      @publication.run_evidence_value_identity(evidence),
    ),
  )
  assert_true(retire_installed_effect_captured_consumers(original.run).unwrap())
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(original.run).unwrap()
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).live_reservations,
    0,
  )
}

///|
// Actual original Run/Plan/body and canonical issued evidence. This is a
// constructor/backing component, not a physical Source or publication ACK.
test "keyed complete evidence geometry grows the same original publication body" {
  let original = effect_publication_values_original()
  let body = effect_unit_publication_body(
    original.run,
    original.plan,
    original.request,
  ).unwrap()
  let observation = @publication_host.client_effect_source_free_invocation_original_observation(
    original.issued,
  )
  let invocation = @publication_host.client_effect_source_free_invocation_original_invocation(
    original.issued,
  )
  for
    (name, wire) in [
      ("observation_set", @publication.run_evidence_value_json(observation)),
      ("run_invocation", @publication.publication_contract_json(invocation)),
    ] {
    let writer = @encode.construction_measuring_writer(1000000, 100000, 64)
    @encode.emit_json(@json.parse(wire), writer)
    let geometry = @encode.finish_construction_measurement(writer)
    let before = @resources.preparation_body_borrow_reserved_extents(body).unwrap()
    reserve_installed_effect_keyed_encoding(
      original.run,
      original.plan,
      original.request,
      @publication.publication_contract_identity(original.definition),
      name,
      geometry,
      complete_body=true,
    ).unwrap()
    let after = @resources.preparation_body_borrow_reserved_extents(body).unwrap()
    assert_true(after.0 > before.0 && after.1 >= after.0)
    // A malformed extent still cannot construct or grow this same body.
    assert_true(
      reserve_installed_effect_keyed_encoding(
        original.run,
        original.plan,
        original.request,
        @publication.publication_contract_identity(original.definition),
        name,
        { ..geometry, nodes: 0, },
        complete_body=true,
      )
      is Err(InsufficientCapacity),
    )
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(body),
      Ok(after),
    )
  }
  // The other existing callbacks still supply preimages. Their default quote
  // must continue adding the registry-owned self field before construction.
  let preimage_json = @json.parse(
    @publication.publication_contract_json(invocation),
  )
  guard preimage_json is Object(fields) else {
    fail("original invocation object")
  }
  fields.remove("invocation_cid") |> ignore
  let writer = @encode.construction_measuring_writer(1000000, 100000, 64)
  @encode.emit_json(preimage_json, writer)
  let preimage = @encode.finish_construction_measurement(writer)
  let identity = @publication.publication_contract_identity(original.definition)
  let original_quote = effect_unit_publication_capacity(
    [("run_invocation", preimage)],
    identity,
  ).unwrap()
  let without_self = effect_unit_publication_capacity(
    [("run_invocation", preimage)],
    identity,
    complete_body=true,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(original_quote) >
    @execution.execution_capacity_retained_bytes(without_self),
  )
  close_effect_publication_values(original)
}
