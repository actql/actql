///|
// Actual original Source/parser/lowerer/check/compiler bodies. No physical
// allocation, Account, Run, provider read, durable state or ACK is supplied.
fn source_original_input_fixture(
  text : String,
  read_only? : Bool = false,
) -> (ClientSourceInput, @source_publication.PreparedPublishedQueryEnvironment) {
  let environment = admit_client_check_environment(
    local_update_source_environment,
    "sha256:aeb50e7260b47a2a152ee593bac2956835f53570c6c5fc68b5caf39c1da3959e",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let intent = prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"" +
    text +
    "\"},\"parameters\":null" +
    (if read_only { ",\"readOnly\":true}" } else { "}" }),
    65536,
    8192,
    64,
  ).unwrap()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"crm.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"installationOwnerCid\":\"sha256:" +
    "e".repeat(64) +
    "\"}]}"
  let selected = @source_publication.prepare_published_query_environment(
    environment, publication,
  ).unwrap()
  (
    prepare_client_source_input(intent, environment, publication).unwrap(),
    selected,
  )
}

///|
test "Source request original input handoff retains same Pure compiler and source identity without another preparation" {
  let (input, publication) = source_original_input_fixture("SELECT 7 AS n")
  let query = observe_client_source_input_query(input).unwrap().0.unwrap()
  let (lowered, catalog, _) = lower_client_source_input_query(
    input,
    publication,
    input.environment,
    query,
    public_primary=true,
  ).unwrap()
  let prepared = prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    input.environment,
    input.supplied,
    client_standard_program_preparation_limits(),
    source_catalog=Some(catalog),
  ).unwrap()
  let source = retain_compiled_client_source_input(input, Pure(prepared)).unwrap()
  assert_true(
    source.preparation is Pure(actual) && physical_equal(actual, prepared),
  )
  assert_true(physical_equal(source.intent, input.intent))
  assert_true(physical_equal(source.environment, input.environment))
  assert_eq(
    client_source_computation_source(source),
    ("SELECT 7 AS n", "sql", None),
  )
  assert_eq(prepared_client_result_name(prepared, 0), Some("main"))
  assert_eq(
    client_source_computation_material(source),
    (lowered.document, None),
  )
  let request = client_source_computation_request(
    source,
    "sha256:" + "a".repeat(64),
    "same-source-request",
  ).unwrap()
  assert_eq(
    client_request_input_cid(request),
    client_submitted_intent_cid(input.intent),
  )
  assert_true(
    physical_equal(
      source,
      retain_compiled_client_source_input(input, Pure(prepared)).unwrap(),
    ),
  )
  assert_true(observe_client_source_input_query(input) is Err(Input))
  assert_true(
    lower_client_source_input_query(
      input,
      publication,
      input.environment,
      query,
    )
    is Err(Input),
  )
}

///|
test "Source request original Effect constructor retains intent before same body handoff without copying compiler output" {
  let (input, publication) = source_original_input_fixture(
    "SELECT 1 AS id, 2 AS value |> RESULT out |> EFFECT UPDATE crm.Account ID id SET (Name = value)",
  )
  let query = observe_client_source_input_query(input).unwrap().0.unwrap()
  let (lowered, catalog, _) = lower_client_source_input_query(
    input,
    publication,
    input.environment,
    query,
  ).unwrap()
  let candidate = @checked.prepare_effect_computation_candidate(
    lowered.program.unwrap(),
    input.environment,
    input.supplied,
    [],
    client_standard_effect_computation_limits().program.checking,
    client_standard_effect_computation_limits().max_members,
    client_standard_effect_computation_limits().max_header_work,
    source_catalog=Some(catalog),
  ).unwrap()
  let prepared = observe_prepare_checked_client_source_effect_computation(
    input,
    candidate,
    client_standard_effect_computation_limits(),
    update_targets=lowered.update_targets,
    store_targets=lowered.store_targets,
    command_targets=lowered.command_targets,
  ).unwrap().0.unwrap()
  assert_true(
    prepared.source_intent is Some(original) &&
    physical_equal(original, input.intent),
  )
  assert_true(physical_equal(prepared.source, lowered.program.unwrap()))
  let source = retain_compiled_client_source_input(input, Effect(prepared)).unwrap()
  assert_true(
    source.preparation is Effect(actual) && physical_equal(actual, prepared),
  )
  let (program, parameters, _) = client_effect_original_input_wires(prepared).unwrap()
  assert_eq(client_source_computation_material(source), (program, parameters))
  let equal_intent = prepare_client_submitted_intent(
    client_submitted_intent_wire(input.intent),
    65536,
    8192,
    64,
  ).unwrap()
  assert_false(
    client_source_computation_matches(source, equal_intent, input.environment),
  )
  let unbound = prepare_checked_client_effect_computation(
    candidate,
    client_standard_effect_computation_limits(),
    update_targets=lowered.update_targets,
  ).unwrap()
  assert_true(unbound.source_intent is None)
  assert_true(
    retain_compiled_client_source_input(input, Effect(unbound)) is Err(Input),
  )
}

///|
test "Source request original trace refuses copied input foreign query Environment and equal foreign compiled body" {
  let (input, publication) = source_original_input_fixture("SELECT 7 AS n")
  assert_true(client_source_input_parts({ ..input, }) is Err(Input))
  let query = observe_client_source_input_query(input).unwrap().0.unwrap()
  let equal_query = @source_frontend.parse_query("SELECT 7 AS n", Sql).unwrap()
  assert_true(
    lower_client_source_input_query(
      input,
      publication,
      input.environment,
      equal_query,
    )
    is Err(Input),
  )
  assert_false(input.lowering_started)
  let (foreign, _) = source_original_input_fixture("SELECT 7 AS n")
  assert_true(
    lower_client_source_input_query(
      input,
      publication,
      foreign.environment,
      query,
    )
    is Err(Input),
  )
  assert_false(input.lowering_started)
  let (lowered, catalog, _) = lower_client_source_input_query(
    input,
    publication,
    input.environment,
    query,
  ).unwrap()
  let fresh_parsed = @syntax.parse(
    lowered.document,
    client_standard_program_preparation_limits().checking.input,
    format=@syntax.Json,
  ).unwrap()
  let copied = prepare_parsed_effect_free_client_program(
    fresh_parsed,
    input.environment,
    None,
    client_standard_program_preparation_limits(),
    source_catalog=Some(catalog),
  ).unwrap()
  assert_true(
    retain_compiled_client_source_input(input, Pure(copied)) is Err(Input),
  )
  assert_true(input.prepared is None)
}

///|
test "Source request original trace keeps readOnly refusal and does not retry a failed lowering" {
  let (input, publication) = source_original_input_fixture(
    "SELECT 1 AS id, 2 AS value |> RESULT out |> EFFECT UPDATE crm.Account ID id SET (Name = value)",
    read_only=true,
  )
  let query = observe_client_source_input_query(input).unwrap().0.unwrap()
  assert_true(
    lower_client_source_input_query(
      input,
      publication,
      input.environment,
      query,
    )
    is Err(ReadOnly),
  )
  assert_true(input.lowering_started)
  assert_true(input.lowered is None)
  assert_true(input.prepared is None)
  assert_true(
    lower_client_source_input_query(
      input,
      publication,
      input.environment,
      query,
    )
    is Err(Input),
  )
}

///|
test "Source request original nonnull Parameter cursor reaches SAME Effect compiler and rejects equal foreign cursor" {
  let (seed, publication) = source_original_input_fixture("SELECT 7 AS n")
  let intent = prepare_client_submitted_intent(
    (
      #|{"kind":"aql","input":{"format":"sql","text":"SELECT 1 AS id, @n AS value |> RESULT out |> EFFECT UPDATE crm.Account ID id SET (Name = value)","parameterDeclarations":{"n":{"type":"number"}}},"parameters":{"n":2}}
    ),
    65536,
    8192,
    64,
  ).unwrap()
  let input = prepare_client_source_input(
    intent,
    seed.environment,
    seed.publication,
  ).unwrap()
  let query = observe_client_source_input_query(input).unwrap().0.unwrap()
  let (lowered, catalog, _) = lower_client_source_input_query(
    input,
    publication,
    input.environment,
    query,
  ).unwrap()
  let limits = client_standard_effect_computation_limits()
  let candidate = @checked.prepare_effect_computation_candidate(
    lowered.program.unwrap(),
    input.environment,
    input.supplied,
    [],
    limits.program.checking,
    limits.max_members,
    limits.max_header_work,
    source_catalog=Some(catalog),
  ).unwrap()
  let supplied = input.supplied.unwrap()
  assert_true(
    @checked.effect_computation_supplied(candidate) is Some(original) &&
    physical_equal(original, supplied),
  )
  let prepared = observe_prepare_checked_client_source_effect_computation(
    input,
    candidate,
    limits,
    update_targets=lowered.update_targets,
  ).unwrap().0.unwrap()
  assert_true(
    prepared.supplied is Some(original) && physical_equal(original, supplied),
  )
  let source = retain_compiled_client_source_input(input, Effect(prepared)).unwrap()
  assert_true(
    source.preparation is Effect(original) && physical_equal(original, prepared),
  )
  assert_eq(client_source_computation_material(source).1, Some("{\"n\":2}"))
  assert_eq(
    client_source_computation_source(source).2,
    Some("{\"n\":{\"type\":\"number\"}}"),
  )
  let foreign = scalar_profile_cursor("{\"n\":2}")
  let changed = @checked.prepare_effect_computation_candidate(
    lowered.program.unwrap(),
    input.environment,
    Some(foreign),
    [],
    limits.program.checking,
    limits.max_members,
    limits.max_header_work,
    source_catalog=Some(catalog),
  ).unwrap()
  assert_true(
    observe_prepare_checked_client_source_effect_computation(
      input,
      changed,
      limits,
      update_targets=lowered.update_targets,
    )
    is Err(Input),
  )
}
