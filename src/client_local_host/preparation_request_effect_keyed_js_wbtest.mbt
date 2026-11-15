///|
// Actual Request check/compiler and declared-file Source profile. There is no
// Model node/provider or physical Source execution in this component fixture.
fn request_source_keyed_graph_fixture() -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientKeyedAcquisition,
  ClientInstalledSequenceContracts,
  @row_source_host.RowDeclaration,
) raise {
  let (unbound, wire) = original_keyed_declaration_environment(
    relation_versions=true,
  )
  let physical = @row_source_host.generate_row_declaration(
    "source-keyed-physical",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "file",
        fields: ["id", "name", "version", "mime", "text"].map(name => @row_source_host.RowField::{
          name,
          value_type: "string",
          nullable: false,
        }),
      },
    ],
    {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 32,
      max_views: 1,
      max_fields: 10,
    },
  ).unwrap()
  let content = unbound.views.filter(view => view.resource == "contents")[0]
  let declaration = @row_source_host.bind_declared_file_read_profile(
    unbound,
    content.source_ref,
    physical,
    "records",
    {
      identity: "id",
      name: "name",
      version: "version",
      media_type: "mime",
      content_utf8: "text",
      path: None,
      items_path: ["items"],
      key_path: ["id"],
    },
  ).unwrap()
  guard @json.parse(wire) is Object(fields) &&
    fields["host_policy_profile"] is Object(policy) else {
    fail("original keyed Source policy")
  }
  let (environment, _) = effect_model_plan_source(
    declaration=Some(declaration),
    lookup_policy=Some(policy["lookup_execution"]),
  )
  let document =
    #|{"version":"actql/0.1","id":"source-effect-request","stages":[{"id":"read","inputs":{"contents":{"connector":"content-fixture","resource":"contents"},"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"left"},{"from":"left","join":{"with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"joined"},{"derive":{"id":{"literal":1}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"read","result":"rows"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(environment),
    effect_limits=Some(
      @publication_host.client_standard_effect_computation_limits(),
    ),
  )
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_effect_program_check_preparation(child).unwrap()
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  assert_true(
    @publication_host.prepared_client_effect_infer_occurrences(prepared)
    is Some([]),
  )
  let borrowed = borrow_request_effect_plan_input(parent, input).unwrap()
  @resources.return_preparation_body_borrow(borrowed).unwrap() |> ignore
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let keyed = @publication_host.select_client_effect_single_keyed_acquisition(
      prepared,
    )
    .unwrap()
    .unwrap()
  (parent, input, prepared, keyed, contracts, declaration)
}

///|
test "Source-only Effect Request retains its actual measured keyed graph without a Model" {
  let (parent, input, prepared, keyed, contracts, declaration) = request_source_keyed_graph_fixture()
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  let graph = prepare_request_effect_keyed_plan(
    parent,
    input,
    keyed,
    contracts,
    [declaration],
  ).unwrap()
  assert_true(
    @publication_host.client_effect_keyed_plan_graph_matches(
      graph, prepared, keyed,
    ),
  )
  assert_true(parent.phase == EffectPlanReserved)
  guard parent.program_domain_compilation_inputs
    is Some(RequestEffectKeyedGraph(p, k, c, g)) else {
    fail("same Request must retain the actual issued graph")
  }
  assert_true(
    physical_equal(p, prepared) &&
    physical_equal(k, keyed) &&
    physical_equal(c, contracts) &&
    physical_equal(g, graph),
  )
  let after = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(
    prepare_request_effect_keyed_plan(parent, input, keyed, contracts, [
      declaration,
    ])
    is Err(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap() |> ignore
}

///|
test "Source-only Effect Request rejects a separately prepared keyed original before graph construction" {
  let (parent, input, _, _, contracts, declaration) = request_source_keyed_graph_fixture()
  let (other, _, _, keyed, _, _) = request_source_keyed_graph_fixture()
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(
    prepare_request_effect_keyed_plan(parent, input, keyed, contracts, [
      declaration,
    ])
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(
      parent.effect_capacity.unwrap(),
      input,
    ),
    Ok(before),
  )
  assert_true(parent.program_domain_compilation_inputs is None)
  abort_request_preparation_after_cleanup(parent).unwrap() |> ignore
  abort_request_preparation_after_cleanup(other).unwrap() |> ignore
}
