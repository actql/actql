///|
test "required Catalog replay admits exact four-axis limits and debits once" {
  let usage : SourceCatalogUsage = { work: 11, bytes: 13, nodes: 17, }
  let budget : IdentityBudget = { work: 11, bytes: 13, nodes: 17, depth: 19, }
  assert_true(source_catalog_replay_accounting(usage, 19, budget, true))
  assert_eq(
    (budget.work, budget.bytes, budget.nodes, budget.depth),
    (0, 0, 0, 19),
  )
  let accepted = source_catalog_replay_accounting(usage, 19, budget, true) catch {
    BudgetExceeded => false
    _ => true
  }
  assert_false(accepted)
}

///|
test "required Catalog replay rejects each short axis without a partial debit" {
  let usage : SourceCatalogUsage = { work: 11, bytes: 13, nodes: 17, }
  for
    (work, bytes, nodes, depth) in [
      (10, 13, 17, 19),
      (11, 12, 17, 19),
      (11, 13, 16, 19),
      (11, 13, 17, 18),
    ] {
    let budget : IdentityBudget = { work, bytes, nodes, depth, }
    let rejected = try {
      ignore(source_catalog_replay_accounting(usage, 19, budget, true))
      false
    } catch {
      BudgetExceeded => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(
      (budget.work, budget.bytes, budget.nodes, budget.depth),
      (work, bytes, nodes, depth),
    )
  }
}

///|
test "legacy Catalog replay retains fresh-reader selection for short limits" {
  let usage : SourceCatalogUsage = { work: 11, bytes: 13, nodes: 17, }
  for
    (work, bytes, nodes, depth) in [
      (10, 13, 17, 19),
      (11, 12, 17, 19),
      (11, 13, 16, 19),
      (11, 13, 17, 18),
    ] {
    let budget : IdentityBudget = { work, bytes, nodes, depth, }
    assert_false(source_catalog_replay_accounting(usage, 19, budget, false))
    assert_eq(
      (budget.work, budget.bytes, budget.nodes, budget.depth),
      (work, bytes, nodes, depth),
    )
  }
}

///|
test "required Catalog replay preserves nominal original and never invokes reader" {
  let environment = reuse_catalog_environment()
  let original = prepare_source_catalog(environment, reuse_catalog_limits()).unwrap()
  let required = require_source_catalog_reuse(original)
  assert_false(source_catalog_requires_reuse(original))
  assert_true(source_catalog_requires_reuse(required))
  assert_true(source_catalog_same_original(original, required))
  assert_true(physical_equal(required, require_source_catalog_reuse(required)))
  let limits = source_catalog_replay_limits(required)
  let usage = source_catalog_usage(original)
  assert_eq(
    (limits.max_work, limits.max_bytes, limits.max_nodes, limits.max_depth),
    (usage.work, usage.bytes, usage.nodes, 100),
  )
  let calls = Ref(0)
  let read = (wire, budget) => {
    calls.val += 1
    prepare_environment(wire, budget)
  }
  for
    (work, bytes, nodes, depth) in [
      (usage.work - 1, usage.bytes, usage.nodes, 100),
      (usage.work, usage.bytes - 1, usage.nodes, 100),
      (usage.work, usage.bytes, usage.nodes - 1, 100),
      (usage.work, usage.bytes, usage.nodes, 99),
    ] {
    let budget : IdentityBudget = { work, bytes, nodes, depth, }
    try
      reuse_source_catalog_with_reader(required, environment.wire, budget, read)
    catch {
      BudgetExceeded => ()
      other => raise other
    } noraise {
      _ => fail("required reuse accepted short limits")
    }
  }
  let budget : IdentityBudget = {
    work: usage.work,
    bytes: usage.bytes,
    nodes: usage.nodes,
    depth: 100,
  }
  let (catalog, references) = reuse_source_catalog_with_reader(
    required,
    environment.wire,
    budget,
    read,
  )
  assert_true(physical_equal(catalog, original.catalog))
  assert_true(physical_equal(references, original.references))
  let foreign = prepare_source_catalog(
    reuse_catalog_environment(),
    reuse_catalog_limits(),
  ).unwrap()
  assert_false(source_catalog_same_original(required, foreign))
  try
    reuse_source_catalog_with_reader(
      required,
      foreign.environment.wire,
      budget,
      read,
    )
  catch {
    ForeignPreparedCatalog => ()
    other => raise other
  } noraise {
    _ => fail("required reuse accepted same-CID foreign wire")
  }
  assert_eq(calls.val, 0)
}

///|
test "required Catalog replay projection retains installed original and refuses foreign environment" {
  let environment = reuse_catalog_environment()
  let wire = "{\"environmentCid\":\"" +
    checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let installed = @installed_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap()
  let original = @installed_publication.prepared_published_query_catalog(
    installed, environment,
  ).unwrap()
  let required = @installed_publication.prepared_published_required_catalog(
    installed, environment,
  ).unwrap()
  assert_true(source_catalog_same_original(original, required))
  assert_false(source_catalog_requires_reuse(original))
  assert_true(source_catalog_requires_reuse(required))
  assert_eq(source_catalog_usage(original), source_catalog_usage(required))
  let foreign = reuse_catalog_environment()
  assert_eq(
    checking_environment_cid(environment),
    checking_environment_cid(foreign),
  )
  assert_true(
    @installed_publication.prepared_published_required_catalog(
      installed, foreign,
    )
    is Err(ForeignEnvironment),
  )
}

///|
test "required Catalog closed Values dependencies refuse nonempty keyed source facts" {
  let environment = reuse_catalog_environment()
  let original = prepare_source_catalog(environment, reuse_catalog_limits()).unwrap()
  assert_true(
    source_catalog_closed_values_dependencies(original, 1000000) is None,
  )
  assert_true(
    source_catalog_closed_values_dependencies(
      require_source_catalog_reuse(original),
      1000000,
    )
    is None,
  )
}

///|
// Exact generated client_local_product_assets.environment; no authored substitute.
test "default product Catalog admits closed Values original dependency guard" {
  let bytes = @utf8.encode(
    "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"},\"text_time_evaluation\":{\"max_input_codepoints\":4096,\"max_input_utf8_bytes\":16384,\"max_output_bytes\":1048576,\"max_pattern_bytes\":4096,\"max_replacements\":4096,\"version\":\"actql-text-time-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
  )
  let wire = @environment.read(
    bytes,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    },
  ).unwrap()
  let environment = checking_environment(
    wire,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let catalog = prepare_source_catalog(environment, reuse_catalog_limits()).unwrap()
  let dependencies = source_catalog_closed_values_dependencies(catalog, 0).unwrap()
  assert_eq(dependencies.scanned_work, 0)
  assert_eq(dependencies.registry_entries, 0)
  assert_eq(dependencies.reference_entries, 0)
}

///|
test "default product Catalog declines oversized or nested policy before serialization" {
  for
    (wire_text, cid) in [
      (
        "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:86f2e8fde2de1a27cef1cc292ce37a1608a3cc531a0b59fa3b10aa0f28abdf43\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"},\"text_time_evaluation\":{\"max_input_codepoints\":4096,\"max_input_utf8_bytes\":16384,\"max_output_bytes\":1048576,\"max_pattern_bytes\":4096,\"max_replacements\":4096,\"version\":\"actql-text-time-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
        "sha256:86f2e8fde2de1a27cef1cc292ce37a1608a3cc531a0b59fa3b10aa0f28abdf43",
      ),
      (
        "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:f7ac98081769ba0a5bd2b285a09290fad85d5cac0ee86684634ee22d5ed5570b\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":{\"nested\":1},\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"},\"text_time_evaluation\":{\"max_input_codepoints\":4096,\"max_input_utf8_bytes\":16384,\"max_output_bytes\":1048576,\"max_pattern_bytes\":4096,\"max_replacements\":4096,\"version\":\"actql-text-time-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
        "sha256:f7ac98081769ba0a5bd2b285a09290fad85d5cac0ee86684634ee22d5ed5570b",
      ),
      (
        "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:ffc99e7be0db5898b104754114620f2ed598d4e6c8216417721e47398d82ac9c\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\",\"日本語\":1},\"text_time_evaluation\":{\"max_input_codepoints\":4096,\"max_input_utf8_bytes\":16384,\"max_output_bytes\":1048576,\"max_pattern_bytes\":4096,\"max_replacements\":4096,\"version\":\"actql-text-time-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
        "sha256:ffc99e7be0db5898b104754114620f2ed598d4e6c8216417721e47398d82ac9c",
      ),
      (
        "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:4df28d0215b0a53a194f777f8485a4fbcfe0cff819ba9c52b15fba319dcd0c21\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"},\"extra\":{\"data\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"},\"text_time_evaluation\":{\"max_input_codepoints\":4096,\"max_input_utf8_bytes\":16384,\"max_output_bytes\":1048576,\"max_pattern_bytes\":4096,\"max_replacements\":4096,\"version\":\"actql-text-time-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
        "sha256:4df28d0215b0a53a194f777f8485a4fbcfe0cff819ba9c52b15fba319dcd0c21",
      ),
    ] {
    let wire = @environment.read(@utf8.encode(wire_text), cid, {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    }).unwrap()
    assert_false(@environment.closed_values_policy_shape(wire))
  }
}
