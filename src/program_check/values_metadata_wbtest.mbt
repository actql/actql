///|
test "formal construction charges unused values metadata exactly once across Stages" {
  for count in [1, 8] {
    let mut suffix = ""
    for i in 0..<count {
      suffix += ",{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"unused" +
        i.to_string() +
        "\"}"
    }
    let checked : Array[CheckedProgram] = []
    let generous : IdentityBudget = {
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    }
    let identity = local_construction_fixture(
        generous,
        through_check=true,
        checked_results=checked,
        second_stage=true,
        producer_suffix=suffix,
        extra_step_budget=count + 1,
      ).0
    assert_eq(checked.length(), 1)
    let budget : IdentityBudget = {
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    }
    let (requirements, gates, contracts) = prepare_owned_closure(
      identity, budget,
    )
    let index = @context.incoming_links_resolutions(
      @context.stage_requirement_owner(requirements),
    )
    let (payload_bytes, payload_nodes) = @context.operation_resolution_values_usage(
      index,
    )
    let (metadata_bytes, metadata_nodes) = @context.operation_resolution_values_metadata_usage(
      index,
    )
    assert_eq(payload_bytes, count * 3 * 2)
    assert_true(metadata_bytes > payload_bytes)
    assert_true(metadata_nodes > payload_nodes)
    let (_, gate_bytes, gate_nodes) = @context.program_incoming_gates_usage(
      gates,
    )
    let (contract_bytes, contract_nodes) = @context.core_contract_hash_usage(
      contracts,
    )
    assert_eq(
      10000000 - budget.bytes,
      payload_bytes + metadata_bytes + gate_bytes + contract_bytes,
    )
    assert_eq(
      1000000 - budget.nodes,
      payload_nodes + metadata_nodes + gate_nodes + contract_nodes,
    )
    let short : IdentityBudget = {
      work: 100000000,
      bytes: metadata_bytes + payload_bytes - 1,
      nodes: 1000000,
      depth: 100,
    }
    let before = (short.work, short.bytes, short.nodes)
    try prepare_owned_closure(identity, short) catch {
      ConstructionFailure::Values(_) => ()
      _ => fail("the aggregate shortage must fail inside values preparation")
    } noraise {
      _ => fail("no partial closure may escape")
    }
    assert_eq((short.work, short.bytes, short.nodes), before)
    let rejected : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        {
          work: 100000000,
          bytes: metadata_bytes + payload_bytes - 1,
          nodes: 1000000,
          depth: 100,
        },
        through_check=true,
        checked_results=rejected,
        second_stage=true,
        producer_suffix=suffix,
        extra_step_budget=count + 1,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("insufficient aggregate budget cannot return CheckedProgram")
    }
    assert_eq(rejected.length(), 0)
  }
}
