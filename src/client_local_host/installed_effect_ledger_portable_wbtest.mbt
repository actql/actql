///|
// Keep the original typed Ledger contract control portable. The separate JS
// Host test still checks its actual reservation and decoder cleanup scope.
// This pure contract test grants no send or physical cleanup authority.
test "saved Ledger contract preserves original typed binding and fixed wire identity" {
  let cid = fn(mark : String) { "sha256:" + mark.repeat(64) }
  let scope = @effect.prepare_logical_request_scope(cid("a"), "request-1", 32).unwrap()
  let key = @effect.prepare_effect_dispatch_key(
    scope,
    cid("b"),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = @effect.prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "{\"row\":\"record-1\"}", 64, 128,
    8, 3,
  ).unwrap()
  let basis = @effect.prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    cid("c"),
    cid("d"),
    cid("e"),
    cid("f"),
    cid("0"),
    "unavailable",
    cid("1"),
    cid("2"),
  ).unwrap()
  let issued = @effect.issue_prepared_effect_ledger_entry(basis, 1000000, 64, 4).unwrap()
  let wire = @effect.effect_ledger_entry_wire(issued)
  assert_eq(
    @effect.effect_ledger_entry_cid(issued),
    "sha256:09517d06658bcea4c679a029de58d0cb4dbd512eb4d06473b2502acecd009dca",
  )
  let restored = @effect.admit_effect_ledger_entry(wire, 1000000, 64, 4).unwrap()
  assert_true(@effect.effect_ledger_entry_matches_basis(restored, basis))
  assert_eq(@effect.effect_ledger_entry_wire(restored), wire)
  assert_eq(
    @effect.effect_ledger_entry_cid(restored),
    @effect.effect_ledger_entry_cid(issued),
  )
}
