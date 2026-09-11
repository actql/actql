///|
test "registered capacity laws require exact spellings" {
  let names = [
    "actql.bound.append", "actql.bound.array-aggregate-input", "actql.bound.asof-left",
    "actql.bound.canonical-artifact-bytes", "actql.bound.components-input-nodes",
    "actql.bound.components-nodes", "actql.bound.components-output", "actql.bound.effect-scope",
    "actql.bound.global-group", "actql.bound.graph-degree", "actql.bound.graph-edge-rows",
    "actql.bound.graph-edges", "actql.bound.graph-endpoints", "actql.bound.graph-input-edges",
    "actql.bound.graph-input-nodes", "actql.bound.graph-node-rows", "actql.bound.graph-nodes",
    "actql.bound.infer-distinct-keys", "actql.bound.infer-output", "actql.bound.join-output",
    "actql.bound.join-projection", "actql.bound.join-resolved-output", "actql.bound.lookup.complete-response",
    "actql.bound.match-edges", "actql.bound.match-node-ids", "actql.bound.match-nodes",
    "actql.bound.merge-rankings", "actql.bound.nearest", "actql.bound.nest-empty-array",
    "actql.bound.reach-nodes", "actql.bound.row-window", "actql.bound.sequence-output",
    "actql.bound.serialize-artifact-row", "actql.bound.shortest-path", "actql.bound.take",
    "actql.bound.top-k", "actql.bound.traverse-nodes", "actql.bound.traverse-output",
    "actql.bound.unnest-array-items", "actql.bound.unpivot", "actql.bound.vector-rows",
    "actql.bound.window-events", "actql.contract.command-items", "actql.contract.model-task-items",
    "actql.guard.array-aggregate", "actql.guard.artifact-bytes", "actql.guard.artifact-rows",
    "actql.guard.components-output", "actql.guard.effect-items", "actql.guard.infer-items",
    "actql.guard.join-output", "actql.guard.sequence-matches", "actql.guard.sequence-output",
    "actql.guard.traverse-output", "actql.host.aggregate-array-items", "actql.host.artifact-bytes",
    "actql.host.artifact-rows", "actql.host.effect-items", "actql.host.graph-input-edges",
    "actql.host.graph-input-nodes", "actql.host.graph-output", "actql.host.graph-paths",
    "actql.host.infer-items", "actql.host.model-request-bytes", "actql.host.nested-value-bytes",
    "actql.host.relation-output", "actql.host.temporal-matches", "actql.host.temporal-output",
  ]
  for id in names {
    assert_eq(name(admit(id).unwrap()), id)
    assert_true(admit(id + " ") is None)
    assert_true(admit(" " + id) is None)
  }
  for
    id in [
      "actql.guard.nested-array-items", "actql.guard.string-aggregate", "actql.guard.shortest-output",
    ] {
    assert_eq(name(admit(id).unwrap()), id)
  }
  assert_true(admit("actql.expression-fragment.capacity") is None)
  for
    id in [
      "", "actql.bound.unknown", "ACTQL.bound.append", "actql.host.relation-output.v1",
    ] {
    assert_true(admit(id) is None)
  }
}
