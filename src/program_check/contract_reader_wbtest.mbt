///|
test "Unit consumer reads the exact sorted local contract selection" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (identity, _, _, inventory, units) = local_construction_fixture(
    budget,
    second_stage=true,
  )
  for stage in 0..<2 {
    let unit = units[stage]
    assert_true(physical_equal(unit.contract_inventory, inventory))
    assert_true(
      physical_equal(
        @context.core_contract_identity(unit.contract_inventory),
        identity,
      ),
    )
    assert_eq(
      unit.contracts.length(),
      @context.core_contract_stage_body_count(inventory, stage).unwrap(),
    )
    let cids = []
    let mut transfer = false
    let mut relation_count = false
    for i in 0..<unit.contracts.length() {
      let (cid, body) = unit.contracts[i]
      assert_eq(cid, @context.core_contract_cid(body))
      if i > 0 {
        assert_true(@canonical.compare_utf16(unit.contracts[i - 1].0, cid) < 0)
      }
      transfer = transfer || body == @context.BoundTransferRules
      relation_count = relation_count || body == @context.RelationCountRules
      cids.push(cid)
    }
    // Only first authors a derive. The empty consumer references the producer
    // through its Result interfaces, not by copying these operation laws.
    assert_eq(transfer, stage == 0)
    assert_eq(relation_count, stage == 0)
    let writer = @encode.hashing_writer(100000, 1000, 10)
    emit_contract_set(cids, writer)
    assert_eq("sha256:" + @encode.finish_hash(writer), unit.contracts_cid)
  }
}
