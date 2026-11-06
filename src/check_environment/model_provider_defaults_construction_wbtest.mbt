///|
fn resolution_inventory_extent(
  inventory : ModelProviderDefaultsResolutionConstructionInventory,
) -> @shape.CollectionConstructionExtent {
  // Independent source-site expansion, using the shared Array recipe. This
  // remains logical DATA, never a byte price or a Native funding certificate.
  @shape.collection_construction_extent({
    records: inventory.resolved_records +
    inventory.generation_copies +
    inventory.work_cells +
    inventory.issue_tags +
    inventory.error_results +
    inventory.success_results,
    record_references: 4L * inventory.resolved_records +
    inventory.generation_copies +
    inventory.error_results +
    inventory.success_results,
    record_words: inventory.resolved_records +
    3L * inventory.generation_copies +
    inventory.work_cells +
    inventory.issue_tags +
    inventory.error_results +
    inventory.success_results,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: inventory.comparison_arrays,
    scalar_items: inventory.comparison_items,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
}

///|
fn resolution_inventory_one_model() -> ModelProviderDefaults {
  default_profile_read(
    (
      #|{"model_defaults":{"default_model":"m","models":[{"model":"m","generation_config":{"temperature":0,"top_p":1,"max_output_tokens":10,"seed_requested":-7}}]}}
    ),
  )
}

///|
test "default resolution constructor inventory preserves source kinds and visit multiplicity" {
  let original = default_profile_read(default_profile_configuration())
  let inventory = model_provider_defaults_resolution_construction_inventory(
    original,
    Some(200L),
  )
  // Independent source census: one resolution, one copied generation, one
  // three-Int scratch Array per visit, one work cell, six issue/Err sites, Ok.
  assert_eq(inventory, {
    resolved_records: 1L,
    generation_copies: 1L,
    comparison_arrays: 1L,
    comparison_items: 3L,
    comparison_array_constructions: 2L,
    work_cells: 1L,
    issue_tags: 6L,
    error_results: 6L,
    success_results: 1L,
  })
  assert_eq(resolution_inventory_extent(inventory), {
    record_headers: 19L,
    reference_slots: 13L,
    scalar_words: 41L,
  })
  let borrowed = model_provider_defaults_resolution_construction_inventory(
    original,
    None,
  )
  assert_eq(borrowed, { ..inventory, generation_copies: 0L, })
  assert_eq(resolution_inventory_extent(borrowed), {
    record_headers: 18L,
    reference_slots: 12L,
    scalar_words: 38L,
  })
  assert_eq(
    model_provider_defaults_resolution_retained_extent(original, Some(200L)),
    { record_headers: 2L, reference_slots: 5L, scalar_words: 4L, },
  )
  assert_eq(
    model_provider_defaults_resolution_retained_extent(original, None),
    { record_headers: 1L, reference_slots: 4L, scalar_words: 1L, },
  )
  // Equal/invalid override values do not shrink a constructor based on a
  // semantic assumption. The actual resolver alone decides token validity.
  for task_tokens in [0L, 100L, 9007199254740992L] {
    assert_eq(
      model_provider_defaults_resolution_construction_inventory(
        original,
        Some(task_tokens),
      ),
      inventory,
    )
  }
  let one = model_provider_defaults_resolution_construction_inventory(
    resolution_inventory_one_model(),
    Some(200L),
  )
  assert_eq(one, { ..inventory, comparison_array_constructions: 1L, })
}

///|
test "default resolution constructor inventory keeps empty profile refusals without invented storage" {
  let empty = default_profile_read("{\"model_defaults\":{\"models\":[]}}")
  let inventory = model_provider_defaults_resolution_construction_inventory(
    empty,
    Some(1L),
  )
  assert_eq(inventory, {
    resolved_records: 0L,
    generation_copies: 0L,
    comparison_arrays: 0L,
    comparison_items: 0L,
    comparison_array_constructions: 0L,
    work_cells: 1L,
    issue_tags: 6L,
    error_results: 6L,
    success_results: 1L,
  })
  assert_eq(resolution_inventory_extent(inventory), {
    record_headers: 14L,
    reference_slots: 7L,
    scalar_words: 14L,
  })
  for task_tokens in [None, Some(1L)] {
    assert_eq(
      model_provider_defaults_resolution_retained_extent(empty, task_tokens),
      { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, },
    )
    assert_true(
      resolve_model_provider_defaults(empty, None, task_tokens, 0)
      is Err(DefaultUnavailable),
    )
    assert_true(
      resolve_model_provider_defaults(empty, Some("m"), task_tokens, 0)
      is Err(UnknownModel),
    )
  }
}

///|
test "default resolution retained census distinguishes copies from borrowed original aliases" {
  let original = resolution_inventory_one_model()
  let prior = original.models[0].1
  let borrowed = resolve_model_provider_defaults(original, None, None, 4).unwrap()
  assert_true(physical_equal(borrowed.original, original))
  assert_true(physical_equal(borrowed.generation, prior))
  assert_true(physical_equal(borrowed.handling, original.models[0].2))
  for tokens in [1L, 10L, 9007199254740991L] {
    let selected = resolve_model_provider_defaults(
      original,
      Some("m"),
      Some(tokens),
      4,
    ).unwrap()
    assert_true(physical_equal(selected.original, original))
    assert_false(physical_equal(selected.generation, prior))
    assert_true(
      physical_equal(selected.generation.seed_requested, prior.seed_requested),
    )
    assert_eq(selected.generation.temperature, prior.temperature)
    assert_eq(selected.generation.top_p, prior.top_p)
    assert_eq(selected.generation.max_output_tokens, tokens)
    assert_eq(prior.max_output_tokens, 10L)
  }
  let equal_original = resolution_inventory_one_model()
  assert_true(
    resolved_model_provider_defaults_generation(borrowed, equal_original)
    is None,
  )
}

///|
test "default resolution inventory covers every original refusal and exact work boundary" {
  let original = resolution_inventory_one_model()
  assert_true(
    resolve_model_provider_defaults(original, None, None, -1)
    is Err(InvalidLimits),
  )
  for tokens in [0L, -1L, 9007199254740992L] {
    assert_true(
      resolve_model_provider_defaults(original, None, Some(tokens), 4)
      is Err(InvalidTaskOutputTokens),
    )
  }
  // These exercise the comparison-loop refusal and the later success charge
  // separately. No construction quantity changes the original work ceiling.
  for work in [0, 1, 2, 3] {
    assert_true(
      resolve_model_provider_defaults(original, None, None, work)
      is Err(WorkLimit),
    )
  }
  assert_eq(
    resolve_model_provider_defaults(original, None, None, 4).unwrap().work,
    4,
  )
  assert_true(
    resolve_model_provider_defaults(original, Some("x"), None, 3)
    is Err(UnknownModel),
  )
  let multiple = default_profile_read(default_profile_configuration())
  // Both ten-unit names cost21 per visit; selecting the second costs43.
  assert_true(
    resolve_model_provider_defaults(multiple, Some("operator-b"), None, 42)
    is Err(WorkLimit),
  )
  assert_eq(
    resolve_model_provider_defaults(multiple, Some("operator-b"), None, 43).unwrap().work,
    43,
  )
  let unicode = default_profile_read(
    "{\"model_defaults\":{\"default_model\":\"e\u{0301}\",\"models\":[{\"model\":\"e\u{0301}\",\"generation_config\":{\"temperature\":0,\"top_p\":1,\"max_output_tokens\":10}}]}}",
  )
  assert_true(
    resolve_model_provider_defaults(unicode, None, None, 5) is Err(WorkLimit),
  )
  assert_eq(
    resolve_model_provider_defaults(unicode, None, None, 6).unwrap().model,
    "e\u{0301}",
  )
  assert_true(
    resolve_model_provider_defaults(unicode, Some("é"), None, 4)
    is Err(UnknownModel),
  )
}

///|
test "default resolution logical composition rejects overflow and cannot erase required retained units" {
  let original = resolution_inventory_one_model()
  let retained = model_provider_defaults_resolution_retained_extent(
    original,
    Some(10L),
  )
  // Each coordinate is independently required by the two actual records.
  // This is an underquote comparison, not a new production admission policy.
  let underquotes : Array[@shape.CollectionConstructionExtent] = [
    { record_headers: 1L, reference_slots: 5L, scalar_words: 4L, },
    { record_headers: 2L, reference_slots: 4L, scalar_words: 4L, },
    { record_headers: 2L, reference_slots: 5L, scalar_words: 3L, },
  ]
  for underquote in underquotes {
    assert_true(
      underquote.record_headers < retained.record_headers ||
      underquote.reference_slots < retained.reference_slots ||
      underquote.scalar_words < retained.scalar_words,
    )
  }
  let max = 9223372036854775807L
  let exact = max / 5L
  assert_eq(
    @shape.scale_collection_construction_extent(retained, exact),
    Some({
      record_headers: 2L * exact,
      reference_slots: 5L * exact,
      scalar_words: 4L * exact,
    }),
  )
  assert_true(
    @shape.scale_collection_construction_extent(retained, exact + 1L) is None,
  )
  assert_true(
    @shape.scale_collection_construction_extent(retained, -1L) is None,
  )
  let remaining : @shape.CollectionConstructionExtent = {
    record_headers: max - 2L,
    reference_slots: max - 5L,
    scalar_words: max - 4L,
  }
  assert_eq(
    @shape.add_collection_construction_extents(remaining, retained),
    Some({ record_headers: max, reference_slots: max, scalar_words: max, }),
  )
  for
    over in [
      { ..remaining, record_headers: max - 1L, },
      { ..remaining, reference_slots: max - 4L, },
      { ..remaining, scalar_words: max - 3L, },
    ] {
    assert_true(
      @shape.add_collection_construction_extents(over, retained) is None,
    )
  }
}
