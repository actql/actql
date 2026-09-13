///|
// Unchecked input material for the known fixture topology. Never derives its
// coordinates or expected acceptance from an already checked Program.
fn local_join_capacity_fixture(
  environment : @environment.WireEnvironment,
  maximum : Int,
  step : Int,
) -> @host.HostSources raise @encode.EncodeFailure {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let host = @host.create(
    @policy.ceiling(policy, "max_relation_output_rows").unwrap(),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, },
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 30)
  @host.emit(host, writer)
  let host_text = @encode.finish(writer)
  let witness = @wire.admit(@utf8.encode(host_text), @host.cid(host), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
    host_text +
    "],\"effective_max\":" +
    maximum.to_string() +
    ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"join:checked-step:" +
    step.to_string() +
    ":output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let text = body.replace(
    old="\"subject_ref\":",
    new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
  )
  let mixed = @wire.check_mixed_claims([witness], [(@utf8.encode(text), cid)], {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 10,
    max_references: 20,
  }).unwrap()
  @host.bind_claim_sources(claims, [policy], {
    max_entries: 10,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
}

///|
test "formal join rejects missing capacity and missing full-join identity atomically" {
  for full in [false, true] {
    let checked : Array[CheckedProgram] = []
    let kind = if full { "full" } else { "inner" }
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        second_steps="[" +
          (if full {
            "{\"drop\":[\"id\"]},{\"derive\":{\"id\":\"value + 1\"}},"
          } else {
            ""
          }) +
          "{\"join\":{\"with\":\"again\",\"kind\":\"" +
          kind +
          "\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}},\"as\":\"selected\"}]",
        // Keep publication independently ordered so this probes the unused
        // full join's identity requirement, not a later order failure.
        second_result_from=if full { "rows" } else { "selected" },
        extra_step_budget=2,
        second_join_capacity=full,
        second_join_step=if full { 2 } else { 0 },
      )
    catch {
      LocalConstructionFailure::Source(
        SourceFailure::SourceView(
          Context(
            Stages(
              Capacity(stage, visit, JoinCollection(MissingApplication(step)))
            )
          )
        )
      ) => {
        assert_false(full)
        assert_eq(stage, 1)
        assert_eq(visit, 0)
        assert_eq(step, 0)
      }
      LocalConstructionFailure::Closure(Joins(MissingEvidence(_))) =>
        assert_true(full)
      error => raise error
    } noraise {
      _ => fail("incomplete join escaped the formal entry")
    }
    assert_eq(checked.length(), 0)
  }
}
