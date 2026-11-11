///|
// Actual checked AQL and declaration-derived demand, not an operational Run,
// physical Source, allocation guarantee or permission positive.
priv struct SplitKeyedContentLimitsFixture {
  prepared : @publication_host.PreparedClientProgram
  direct : ClientInstalledCaptureCapacity
  keyed : @publication_host.ClientKeyedAcquisition
  capacity : @row_source_host.RowKeyedCapacity
  task : Int
  step : Int
}

///|
fn split_keyed_content_limits_fixture() -> (
  SplitKeyedContentLimitsFixture,
  String,
  @checked.CheckEnvironment,
  @row_source_host.RowDeclaration,
) raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let (declaration, wire) = original_keyed_declaration_environment()
  guard @json.parse(wire) is Object(body) &&
    body.get("evidence_bundle_cid") is Some(String(environment_cid)) else {
    abort("original keyed environment identity")
  }
  let environment = @publication_host.admit_client_check_environment(
    wire,
    environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let aliases = declaration.views.map(view => {
    let name = if view.resource == "files" {
      "docs.listing"
    } else {
      "docs.contents"
    }
    "{\"name\":\"" +
    name +
    "\",\"sourceRef\":\"" +
    view.source_ref +
    "\",\"sourceViewContractCid\":\"" +
    view.view_cid +
    "\",\"schemaContractCid\":\"" +
    view.carrier_schema_cid +
    "\"}"
  })
  let publication = "{\"environmentCid\":\"" +
    environment_cid +
    "\",\"aliases\":[" +
    aliases.join(",") +
    "]}"
  let context = @source_publication.bind_published_query_context(
    environment,
    publication,
    None,
  ).unwrap()
  let lowered = @frontend.lower(
    "FROM LIST_FILES(docs.listing) AS f " +
    "|> JOIN docs.contents AS c ON f.resource = c.resource AND f.version = c.version " +
    "|> SELECT f.name AS name, c.content AS document " +
    "|> ASSERT UNIQUE BY (name) " +
    "|> SERIALIZE FORMAT JSONL ORDER BY name OPTIONS (name = 'native-files.jsonl')",
    Text,
    Some(context),
  ).unwrap()
  let program = lowered.program.unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @syntax.emit_program_source(program, writer)
  let document = @encode.finish(writer)
  let prepared = @publication_host.prepare_parsed_effect_free_client_program(
    program,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let occurrences = @publication_host.prepared_client_serialization_occurrences(
    prepared,
  )
  assert_eq(occurrences.length(), 1)
  let (task, step) = occurrences[0]
  let keyed = @publication_host.select_client_single_keyed_acquisition(prepared)
    .unwrap()
    .unwrap()
  let (stage, input, _) = @publication_host.client_keyed_direct_acquisition_coordinates(
    keyed,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    stage,
    input,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let acquisition = @row_source_host.prepare_row_acquisition(
    declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
  ).unwrap()
  let direct = installed_row_capture_capacity(acquisition).unwrap()
  let capacity = @row_source_host.prepare_keyed_row_capacity(
    @publication_host.client_keyed_acquisition_owner(keyed),
    @publication_host.client_keyed_acquisition_facts(keyed),
    declaration,
    original_keyed_child_limits(),
  ).unwrap()
  // These are the same checked originals, not reconstructed DATA. Keep the
  // portable fixture shape separate from the extra originals its JS callers
  // retain; tuple projection supplies no physical retirement acknowledgement.
  (
    { prepared, direct, keyed, capacity, task, step, },
    document,
    environment,
    declaration,
  )
}

///|
test "split keyed Content keeps its original checked path instead of equal task ordinals" {
  let (value, _, _, _) = split_keyed_content_limits_fixture()
  let (_, keyed_task, _) = @publication_host.client_keyed_acquisition_coordinates(
    value.keyed,
  ).unwrap()
  assert_not_eq(keyed_task, value.task)
  assert_true(
    @publication_host.client_keyed_acquisition_reaches_serialization(
      value.prepared,
      value.keyed,
      value.task,
      value.step,
    ),
  )
  assert_false(
    @publication_host.client_keyed_acquisition_reaches_serialization(
      value.prepared,
      value.keyed,
      keyed_task,
      value.step,
    ),
  )
  assert_false(
    @publication_host.client_keyed_acquisition_reaches_serialization(
      value.prepared,
      value.keyed,
      value.task,
      value.step,
      max_work=0,
    ),
  )
  let (foreign, _, _, _) = split_keyed_content_limits_fixture()
  assert_false(
    @publication_host.client_keyed_acquisition_reaches_serialization(
      foreign.prepared,
      value.keyed,
      value.task,
      value.step,
    ),
  )
  assert_true(
    @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
      value.prepared,
      value.task,
      value.step,
      3,
      4096,
      1000000,
      @publication_host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Ok(_),
  )
}

///|
test "split keyed Content quote sums retained Sources and prefix without another Ledger" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let (value, _, _, _) = split_keyed_content_limits_fixture()
  // Independent DATA increments test demand addition, never a capacity issuer.
  let quote = (retained, executing) => {
    keyed_captured_local_installed_limits(
      value.prepared,
      value.direct,
      value.keyed,
      value.capacity,
      [8192L, 8192L],
      [4096L, 4096L],
      4096,
      1000000,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      serialization=Some((value.task, value.step, retained, executing)),
      captured_content=true,
    )
  }
  let baseline = quote(7L, 9L).unwrap()
  let larger = quote(10L, 14L).unwrap()
  assert_eq(larger.retained_bytes, baseline.retained_bytes + 3L)
  assert_eq(larger.execution_bytes, baseline.execution_bytes + 5L)
  let count = @strategy.graph_task_count(
    @publication_host.prepared_client_graph(value.prepared),
  )
  // Only the first child is quoted. A static key bound is neither the
  // cumulative Run allowance nor a demand to reserve every possible child.
  assert_eq(baseline.attempts, count + 3)
  assert_eq(baseline.holdings, count + 2)
  assert_true(quote(-1L, 9L) is None)
  assert_true(quote(7L, -1L) is None)
  assert_true(quote(9223372036854775807L, 9L) is None)
  assert_true(quote(7L, 9223372036854775807L) is None)
}

///|
test "split keyed Content prefix retains JOIN through sort but never replays acquisition" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let (value, _, _, _) = split_keyed_content_limits_fixture()
  let sequence = prepare_client_acquired_serialization_prefix(
    value.prepared,
    value.task,
    value.step,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let (_, _, join) = @publication_host.client_keyed_acquisition_coordinates(
    value.keyed,
  ).unwrap()
  assert_eq(
    @execution.generated_sequence_step_index_at(sequence, 0),
    Some(join),
  )
  assert_true(@execution.generated_sequence_step_count(sequence) > 1)
  let (_, execution, measurement) = client_local_execution_limits(max_rows=3)
  let capacity = client_acquired_serialization_prefix_capacity(
    value.prepared,
    value.task,
    value.step,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(capacity) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) >=
    @execution.execution_capacity_retained_bytes(capacity),
  )
}
