///|
// Pure checked Model/sequence DATA, without Request resource admission, Model
// IO or Account permission. The actual Request/Host integration is JS-only;
// this shared control checks the same binary-prefix eligibility on every target.
test "bounded binary obligations use only the same original Model prefix" {
  let (environment, _) = effect_model_plan_source()
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    model_tasks=@checked.checking_environment_model_tasks(environment),
  ).unwrap()
  let query = "FROM (SELECT 7 AS id, 0 AS position UNION ALL SELECT 8 AS id, 1 AS position) " +
    "|> ASSERT UNIQUE BY (id) |> WHERE position = 0 |> SELECT id " +
    "|> EXTEND 'urgent' AS text " +
    "|> INFER `model-task:risk-score.v1` INPUT (text = text) AS assessment"
  let lowered = @frontend.lower(query, @frontend.Text, Some(context)).unwrap()
  let prepare = fn() {
    @publication_host.prepare_parsed_effect_free_client_program(
      lowered.program.unwrap(),
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
  }
  let prepared = prepare()
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let prefix_for = fn(original, selected) {
    prepare_client_composed_infer_prefix(
      original,
      selected,
      contracts,
      assets.values,
      fragment_body=Some(assets.fragment),
      ordered_body=assets.ordered,
    ).unwrap()
  }
  let prefix = prefix_for(prepared, occurrence)
  let sequences = prepare_client_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(sequences.length(), 1)
  let limits = @infer_host.standard_limits()
  let starts = Ref(0)
  let provider = @infer_host.composed_local_provider(
    occurrence,
    limits,
    _ => {
      starts.val += 1
      Err(@infer_host.InvalidAdvance)
    },
    _ => @connector.ComputeUnsupported,
    input_prefix=Some(prefix),
  )
  let bundle : @connector.CapabilityBundle[Unit, Unit, Unit] = {
    name: "local",
    acquisition: None,
    fixed_compute: Some((_, _) => ()),
    effect: None,
  }
  let bundles = @connector.install_bundles([bundle], 1, 100).unwrap()
  let registry = @connector.installed_bundle_registry(bundles)
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let module_for = fn(selected) {
    @local.prepare_local_compute_module(
      registry,
      registration,
      sequences,
      limits.input,
      limits.measurement,
      1000,
      1,
      managed_providers=[selected],
    ).unwrap()
  }
  let original = module_for(provider)
  // Source-defined operations: Values at 0/3, UNION ALL at 6, unique guard at 7.
  assert_eq(@execution.generated_sequence_step_count(prefix), 12)
  assert_true(@local.local_module_bounded_values_obligation(original, 0, 0))
  assert_true(@local.local_module_bounded_values_obligation(original, 0, 3))
  assert_true(@local.local_module_bounded_append_obligation(original, 0, 6))
  assert_true(
    @local.local_module_bounded_relation_obligation(
      original,
      0,
      7,
      @local.Assertion,
    ),
  )
  assert_false(@local.local_module_bounded_set_obligation(original, 0, 6))
  assert_false(
    @local.local_module_bounded_cross_join_obligation(original, 0, 6),
  )
  assert_false(@local.local_module_bounded_append_obligation(original, 0, 7))
  let unproven = @local.managed_provider_with_inputs(
    actual => @local.managed_provider_accepts(provider, actual),
    actual => @local.managed_provider_capacity(provider, actual),
    (actual, inputs, rows, bytes, execution) => {
      @local.start_managed_provider_with_inputs_and_execution(
        provider, actual, inputs, rows, bytes, execution,
      )
    },
  )
  assert_false(
    @local.local_module_bounded_append_obligation(module_for(unproven), 0, 6),
  )
  let foreign_prepared = prepare()
  let foreign_occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    foreign_prepared,
  ).unwrap()
  let foreign_prefix = prefix_for(foreign_prepared, foreign_occurrence)
  assert_eq(@execution.generated_sequence_step_count(foreign_prefix), 12)
  assert_false(
    physical_equal(
      @execution.generated_sequence_owner(prefix),
      @execution.generated_sequence_owner(foreign_prefix),
    ),
  )
  for
    selected in [
      @local.managed_provider_with_infer_relation_prefix(
        unproven,
        foreign_prefix,
        12,
        limits.input,
        limits.measurement,
      ),
      @local.managed_provider_with_infer_relation_prefix(
        unproven,
        prefix,
        13,
        limits.input,
        limits.measurement,
      ),
      @local.managed_provider_with_infer_relation_prefix(
        unproven,
        @execution.select_generated_sequence_step(prefix, 0).unwrap(),
        12,
        limits.input,
        limits.measurement,
      ),
    ] {
    assert_false(
      @local.local_module_bounded_append_obligation(module_for(selected), 0, 6),
    )
  }
  assert_eq(
    starts.val,
    0,
    msg="eligibility must never open or fabricate a Model execution",
  )
}
