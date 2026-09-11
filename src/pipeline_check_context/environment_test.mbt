///|
fn snapshot_wire(
  profile? : String = "{}",
) -> (@environment.WireEnvironment, @snapshot.EnvironmentSnapshot) {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/first/a\",\"version\":\"actql-local-input-schema/0.1\"}],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  // Linkage fixture, not an independent identity oracle.
  let suffix = suffix.replace(
    old="\"host_policy_profile\":{}",
    new="\"host_policy_profile\":" + profile,
  )
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let entry = @snapshot.read_member(
    @environment.member_at(environment, @environment.SchemaSnapshots, 0).unwrap(),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  (environment, entry)
}

///|
fn snapshot_context(
  locals : Array[@local_inputs.Attached],
  reprepare : Bool,
) -> @local_inputs.ProgramEnvironmentInputs {
  let source = @local_inputs.source(@local_inputs.attached_inputs(locals[0]))
  let (environment, entry) = snapshot_wire()
  let index = @refs.prepare(source, {
    max_work: 100000,
    max_text_bytes: 100000,
  }).unwrap()
  let limits : @local_inputs.Limits = {
    max_work: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }
  let checked = []
  for i in 0..<locals.length() {
    let prepared = if reprepare {
      @local_inputs.prepare(source, i, limits).unwrap()
    } else {
      @local_inputs.attached_inputs(locals[i])
    }
    checked.push(
      @local_inputs.reconcile_environment(
        prepared,
        index,
        environment,
        if i == 0 {
          [entry]
        } else {
          []
        },
        limits,
      ).unwrap(),
    )
  }
  @local_inputs.assemble_environment(source, environment, checked, limits).unwrap()
}

///|
test "Program context retains snapshot coverage and discounts only exact source preparation" {
  let (stages, wiring, _, locals) = wired_fixture()
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let inputs = attach_local_inputs(
    wired,
    locals,
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  let snapshots = snapshot_context(locals, false)
  let result = attach_environment(
    inputs,
    snapshots,
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  assert_true(physical_equal(environment_inputs(result), inputs))
  assert_true(physical_equal(environment_snapshots(result), snapshots))
  let used = environment_usage(result)
  let before = input_usage(inputs)
  let evidence = @local_inputs.program_environment_usage(snapshots)
  let mut shared_work = 0
  let mut shared_nodes = 0
  let mut shared_text = 0
  for attached in locals {
    let prior = @local_inputs.usage(@local_inputs.attached_inputs(attached))
    shared_work += prior.work
    shared_nodes += prior.nodes
    shared_text += prior.text_bytes
  }
  assert_eq(used, {
    work: before.work + locals.length() + evidence.work - shared_work,
    local_input_nodes: before.local_input_nodes + evidence.nodes - shared_nodes,
    text_bytes: before.text_bytes + evidence.text_bytes - shared_text,
  })
  assert_true(
    attach_environment(
      inputs,
      snapshots,
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Ok(_),
  )
  for
    (w, t, n) in [
      (used.work - 1, used.text_bytes, used.local_input_nodes),
      (used.work, used.text_bytes - 1, used.local_input_nodes),
      (used.work, used.text_bytes, used.local_input_nodes - 1),
    ] {
    assert_true(
      attach_environment(
        inputs,
        snapshots,
        max_work=w,
        max_text_bytes=t,
        max_local_input_nodes=n,
      )
      is Err(EnvironmentIssue::BudgetExceeded),
    )
  }
  assert_true(
    attach_environment(
      inputs,
      snapshots,
      max_work=-1,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(InvalidLimits),
  )
  let reread = snapshot_context(locals, true)
  assert_true(
    attach_environment(
      inputs,
      reread,
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignInputs(0)),
  )
  let (_, _, _, other) = wired_fixture()
  assert_true(
    attach_environment(
      inputs,
      snapshot_context(other, false),
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignProgram),
  )
}
