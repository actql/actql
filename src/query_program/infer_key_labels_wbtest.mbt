///|
fn infer_key_labels_test_construction(
  work : Int,
  infer_labels? : Bool = true,
) -> (Construction, @origin.Origin) {
  let document = @origin.document("id😀", 6).unwrap()
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let construction : Construction = {
    builder,
    generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
    model_tasks: None,
    parameter_names: None,
    infer_labels,
    infer_budget: { remaining_work: work, },
  }
  (construction, @origin.range(document, 2, 6, kind=Generated).unwrap())
}

///|
fn infer_key_labels_test_pass(
  construction : Construction,
) -> Array[(String, String)] raise Abort {
  let columns = infer_key_column_names(
    construction,
    [("id", "slot_0"), ("text", "slot_1"), ("hidden", "slot_2")],
    ["hidden"],
    [],
  )
  let seeded = seed_infer_key_labels(construction, [], columns)
  let renamed = retain_infer_key_labels(
    construction,
    seeded,
    columns,
    [("ticket", "slot_0"), ("text", "slot_1")],
    ["slot_0", "slot_1"],
    reset=false,
  )
  remap_infer_key_labels(
    construction,
    renamed,
    Map([("slot_0", "joined_0"), ("slot_1", "joined_1")]),
  )
}

///|
test "INFER key label passes conserve exact and one-short work across Construction spreads" {
  let expected = [("joined_0", "ticket"), ("joined_1", "text")]
  let (measured, _) = infer_key_labels_test_construction(10000)
  assert_eq(infer_key_labels_test_pass(measured), expected)
  let used = 10000 - measured.infer_budget.remaining_work
  assert_true(used > 0 && used < 5000)
  @builder.discard(measured.builder)
  // Every seed, chronology and remap pass spends the same retained owner.
  // Changing the diagnostic origin through a spread must not renew it.
  let (exact, later) = infer_key_labels_test_construction(used * 2)
  let shifted : Construction = { ..exact, generated: later, }
  assert_true(physical_equal(exact.infer_budget, shifted.infer_budget))
  assert_eq(infer_key_labels_test_pass(exact), expected)
  assert_eq(exact.infer_budget.remaining_work, used)
  assert_eq(shifted.infer_budget.remaining_work, used)
  assert_eq(infer_key_labels_test_pass(shifted), expected)
  assert_eq(exact.infer_budget.remaining_work, 0)
  assert_eq(shifted.infer_budget.remaining_work, 0)
  @builder.discard(exact.builder)
  let (short, later) = infer_key_labels_test_construction(used * 2 - 1)
  let shifted : Construction = { ..short, generated: later, }
  assert_eq(infer_key_labels_test_pass(short), expected)
  assert_eq(shifted.infer_budget.remaining_work, used - 1)
  let rejected = try {
    ignore(infer_key_labels_test_pass(shifted))
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(rejected)
  assert_true(short.infer_budget.remaining_work >= 0)
  assert_true(short.infer_budget.remaining_work < used - 1)
  assert_eq(
    short.infer_budget.remaining_work,
    shifted.infer_budget.remaining_work,
  )
  @builder.discard(short.builder)
}

///|
test "INFER label chronology does not revive dropped aliases and resets reused generations" {
  let (construction, _) = infer_key_labels_test_construction(10000)
  let original = [("id", "slot")]
  let aliases = [("id", "slot"), ("ticket", "slot")]
  let seeded = seed_infer_key_labels(construction, [], original)
  assert_eq(seeded, [("slot", "id")])
  let introduced = retain_infer_key_labels(
    construction,
    seeded,
    original,
    aliases,
    ["slot"],
    reset=false,
  )
  assert_eq(introduced, [("slot", "ticket")])
  let dropped = retain_infer_key_labels(
    construction,
    introduced,
    aliases,
    original,
    ["slot"],
    reset=false,
  )
  assert_eq(dropped, [("slot", "ticket")])
  // Visiting an old range after the newer alias disappears is not a rename.
  assert_eq(seed_infer_key_labels(construction, dropped, original), [
    ("slot", "ticket"),
  ])
  // A materialized projection can reuse the physical spelling for a new
  // generation. A true reset admits only its new labels, not old chronology.
  assert_eq(
    retain_infer_key_labels(
      construction,
      dropped,
      original,
      original,
      ["slot"],
      reset=true,
    ),
    [("slot", "id")],
  )
  assert_eq(
    retain_infer_key_labels(
      construction,
      dropped,
      original,
      [],
      [],
      reset=false,
    ),
    [],
  )
  @builder.discard(construction.builder)
}

///|
test "explicit-only INFER disables all label work even with zero remaining allowance" {
  let query = @query.parse_query(
    "SELECT DISTINCT 'a' AS id |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = 'urgent') AS assessment",
    mapping_syntax_limits(),
  ).unwrap()
  assert_false(query_has_omitted_infer(query))
  let (construction, later) = infer_key_labels_test_construction(
    0,
    infer_labels=query_has_omitted_infer(query),
  )
  let shifted : Construction = { ..construction, generated: later, }
  let columns = [("id", "slot")]
  let labels = [("slot", "id")]
  assert_eq(
    infer_key_column_names(shifted, columns, ["id"], [("id", "ticket")]),
    [],
  )
  assert_eq(seed_infer_key_labels(shifted, labels, columns), [])
  assert_eq(
    remap_infer_key_labels(shifted, labels, Map([("slot", "joined")])),
    [],
  )
  for reset in [false, true] {
    assert_eq(
      retain_infer_key_labels(
        shifted,
        labels,
        columns,
        [("ticket", "slot")],
        ["slot"],
        reset~,
      ),
      [],
    )
  }
  assert_eq(construction.infer_budget.remaining_work, 0)
  assert_eq(shifted.infer_budget.remaining_work, 0)
  @builder.discard(construction.builder)
}
