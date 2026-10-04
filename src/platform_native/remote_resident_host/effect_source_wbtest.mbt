///|
fn resident_effect_source_prepared() -> @host.PreparedClientEffectComputation {
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @host.prepare_client_effect_computation(
    resident_effect_source_document,
    Json,
    environment,
    None,
    [],
    {
      program: @host.client_standard_program_preparation_limits(),
      max_members: 1,
      max_header_work: 1000,
      mapping: {
        max_bytes: 20000,
        max_nodes: 2000,
        max_depth: 100,
        max_members: 100,
      },
      max_mapping_work: 1000,
      effects: {
        max_members: 1,
        max_work: 1000,
        max_admission_nodes: 100,
        max_admission_depth: 10,
        max_admission_text_bytes: 1000,
      },
    },
  ).unwrap()
}

///|
fn resident_effect_source_requirement(
  source_ref? : String = "connector://crm/main/r#v",
  contract? : String = "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
  task? : Int = 0,
  source_index? : Int = 0,
  registry? : String = resident_effect_source_registry,
) -> Result[@planning.QueryRequirement, ResidentSourceIssue] {
  prepare_resident_effect_source_requirement(
    resident_effect_source_prepared(),
    task,
    source_index,
    registry,
    resident_effect_source_values,
    Some(resident_effect_source_fragment),
    source_ref,
    contract,
  )
}

///|
test "Effect Source preparation retains the existing two-task checked owner" {
  let prepared = resident_effect_source_prepared()
  let effects = @host.prepared_client_effect_computation_graph(prepared)
  assert_eq(
    @strategy.graph_task_count(
      @strategy.checked_effect_computation_graph(effects),
    ),
    2,
  )
  assert_eq(@strategy.checked_effect_source_count(effects), 1)
  let requirement = resident_effect_source_requirement().unwrap()
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let values = @planning.query_source_evidence_fact_values(facts)
  assert_eq(values[0], "connector://crm/main/r#v")
  assert_eq(
    values[1],
    "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
  )
}

///|
test "Effect Source refuses a different logical Site Source before physical selection" {
  assert_true(
    resident_effect_source_requirement(source_ref="connector://crm/other/r#v")
    is Err(ForeignInput),
  )
}

///|
test "Effect Source refuses a different trusted contract before physical selection" {
  assert_true(
    resident_effect_source_requirement(contract="sha256:" + "0".repeat(64))
    is Err(ForeignInput),
  )
}

///|
test "Effect Source refuses a dependency task as an acquisition root" {
  assert_true(resident_effect_source_requirement(task=1) is Err(Query(_)))
}

///|
test "Effect Source refuses a nonexistent source occurrence" {
  assert_true(
    resident_effect_source_requirement(source_index=1) is Err(Query(_)),
  )
}

///|
test "Effect Source rejects an invalid execution registry without a physical fallback" {
  assert_true(
    resident_effect_source_requirement(registry="{}") is Err(Query(_)),
  )
}
