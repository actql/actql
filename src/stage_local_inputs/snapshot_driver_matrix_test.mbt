///|
// Authored phase/linkage fixtures for the remaining funded driver. These use
// original codecs, not an independent wire-identity or public Host oracle.
fn snapshot_driver_source(inputs : Int) -> @stages.Source {
  let declarations : Array[String] = []
  for i in 0..<Int::max(1, inputs) {
    declarations.push("\"b" + i.to_string() + "\":\"relation\"")
  }
  let stages : Array[String] = []
  for stage in ["s", "t"] {
    stages.push(
      "{\"id\":\"" +
      stage +
      "\",\"inputs\":{" +
      declarations.join(",") +
      "},\"steps\":[],\"results\":{\"out\":{}}}",
    )
  }
  let text = "{\"version\":\"actql/0.1\",\"id\":\"snapshot-driver\",\"stages\":[" +
    stages.join(",") +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"t\",\"result\":\"out\"}}}}"
  let program = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 100000,
        max_total_string_bytes: 100000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
}

///|
fn snapshot_driver_body(stage : String, name : String) -> String {
  "{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/" +
  stage +
  "/" +
  name +
  "\",\"version\":\"actql-local-input-schema/0.1\"}"
}

///|
fn snapshot_driver_environment(
  bodies : Array[String],
) -> @environment.WireEnvironment {
  let sorted = bodies.copy()
  sorted.sort_by((a, b) => {
    @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
  })
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[" +
    sorted.join(",") +
    "],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  ).unwrap()
}

///|
fn snapshot_driver_read(
  source : @stages.Source,
  environment : @environment.WireEnvironment,
  limits? : Limits = caps(),
) -> LocalEnvironmentPreparation raise {
  let read = begin_local_environment_preparation(source, environment, limits).unwrap()
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentGroups)
  let _ = advance_local_environment_preparation(read)
  read
}

///|
// A finite bound on these authored fixtures' original remaining phases only.
// No product budget, new synchronous production implementation or Host claim.
fn snapshot_driver_finish(
  read : LocalEnvironmentPreparation,
) -> ProgramEnvironmentInputs raise {
  for _ in 0..<8 {
    let phase = advance_local_environment_preparation(read)
    if phase == LocalEnvironmentComplete {
      return take_local_environment_preparation_result(read).unwrap().unwrap()
    }
    assert_true(phase != LocalEnvironmentFailed)
  }
  fail("two original declarations/reconciliations and assembly must terminate")
}

///|
test "Snapshot driver zero members selects original declarations without a Reference phase" {
  let source = snapshot_driver_source(0)
  let environment = snapshot_driver_environment([])
  let read = snapshot_driver_read(source, environment)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentDeclaration,
  )
  assert_true(local_environment_snapshots_work_bound(read) is None)
  assert_true(observe_local_environment_snapshot_construction(read) is None)
  assert_true(
    observe_local_environment_snapshot_reference_construction(read) is None,
  )
  let result = snapshot_driver_finish(read)
  assert_true(physical_equal(environment_program(result), source))
  assert_true(physical_equal(program_environment(result), environment))
  for stage in 0..<2 {
    assert_eq(
      snapshot_count(
        environment_assertions(
          program_environment_stage(result, stage).unwrap(),
        ),
      ),
      0,
    )
  }
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentTransferred,
  )
}

///|
test "Snapshot driver one two and many members retain one original Local traversal across Stages" {
  for count in [1, 2, 12] {
    let source = snapshot_driver_source(count)
    let bodies = Array::makei(count, i => {
      snapshot_driver_body(
        if i % 2 == 0 {
          "s"
        } else {
          "t"
        },
        "b" + i.to_string(),
      )
    })
    let environment = snapshot_driver_environment(bodies)
    let read = snapshot_driver_read(source, environment)
    assert_eq(
      local_environment_preparation_phase(read),
      LocalEnvironmentSnapshot,
    )
    let allowance = local_environment_snapshots_work_bound(read).unwrap()
    let mut spent = 0
    for i in 0..<count {
      // The prelude is one-shot for the first Member, not a phase per Member.
      if i == 0 {
        let _ = observe_local_environment_snapshot_construction(read).unwrap()
        let first = observe_local_environment_snapshot_reference_construction(
          read,
        ).unwrap()
        assert_true(first.0 is Some(_))
      } else {
        assert_true(
          local_environment_snapshot_reference_construction(read) is None,
        )
      }
      let (phase, debit) = observe_advance_local_environment_snapshot(read)
      assert_eq(debit, Some(13)) // 12 authored JSON nodes + one Stage-name unit.
      spent += debit.unwrap()
      assert_true(spent <= allowance)
      assert_eq(
        phase,
        if i + 1 == count {
          LocalEnvironmentDeclaration
        } else {
          LocalEnvironmentSnapshot
        },
      )
      assert_true(
        local_environment_snapshot_construction_geometry(read) is None,
      )
    }
    assert_eq(spent, 13 * count)
    let result = snapshot_driver_finish(read)
    assert_true(physical_equal(environment_program(result), source))
    assert_true(physical_equal(program_environment(result), environment))
    assert_eq(
      snapshot_count(
        environment_assertions(program_environment_stage(result, 0).unwrap()),
      ),
      (count + 1) / 2,
    )
    assert_eq(
      snapshot_count(
        environment_assertions(program_environment_stage(result, 1).unwrap()),
      ),
      count / 2,
    )
    clear_local_environment_preparation(read)
    assert_eq(
      local_environment_preparation_phase(read),
      LocalEnvironmentTransferred,
    )
  }
}

///|
test "Snapshot driver mixed Local and connector members preserves the original partition" {
  let source = snapshot_driver_source(1)
  let connector =
    #|{"carrier_schema_contract_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","data_classification":"internal","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","source_data_policy_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","source_ref":"connector://duckdb/local/orders#snapshot","source_view_contract_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}
  let environment = snapshot_driver_environment([
    snapshot_driver_body("s", "b0"),
    connector,
  ])
  let read = snapshot_driver_read(source, environment)
  let mut spent = 0
  for i in 0..<2 {
    let (phase, debit) = observe_advance_local_environment_snapshot(read)
    spent += debit.unwrap()
    assert_eq(
      phase,
      if i == 0 {
        LocalEnvironmentSnapshot
      } else {
        LocalEnvironmentDeclaration
      },
    )
  }
  assert_eq(spent, 22) // Local12+Stage1; connector's original nine nodes only.
  let result = snapshot_driver_finish(read)
  assert_eq(
    snapshot_count(
      environment_assertions(program_environment_stage(result, 0).unwrap()),
    ),
    1,
  )
  assert_eq(
    snapshot_count(
      environment_assertions(program_environment_stage(result, 1).unwrap()),
    ),
    0,
  )
  clear_local_environment_preparation(read)
}

///|
test "Snapshot driver second member refusal retains the first member and actual partial observation" {
  let source = snapshot_driver_source(2)
  let environment = snapshot_driver_environment([
    snapshot_driver_body("s", "b0"),
    snapshot_driver_body("t", "b1"),
  ])
  // Both authored bodies contain12 nodes; only the later member is one short.
  let read = snapshot_driver_read(source, environment, limits={
    ..caps(),
    max_nodes: 23,
  })
  assert_eq(
    observe_advance_local_environment_snapshot(read),
    (LocalEnvironmentSnapshot, Some(13)),
  )
  let (phase, debit) = observe_advance_local_environment_snapshot(read)
  assert_eq((phase, debit), (LocalEnvironmentFailed, Some(0)))
  let (index, emitted) = local_environment_preparation_snapshot_emission(read).unwrap()
  assert_eq(index, 1)
  let (_, nodes, _) = emitted.unwrap()
  assert_eq(nodes, 11)
  assert_eq(
    local_environment_preparation_failure_phase(read),
    Some(LocalEnvironmentSnapshot),
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(Snapshot(1, BudgetExceeded))),
  )
  assert_true(take_local_environment_preparation_result(read) is None)
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentTransferred,
  )
}
