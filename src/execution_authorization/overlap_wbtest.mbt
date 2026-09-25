///|
test "overlap work beyond the budget is rejected, never approximated" {
  let raw : RawAccountConfiguration = {
    account_id: "acct",
    entries: [
      {
        entry_id: "allow",
        outcome: Allow,
        scope: {
          principal: All,
          connection: All,
          resource: All,
          operation: All,
        },
        exclusions: [
          {
            principal: AnyOf(["a"]),
            connection: AnyOf(["a"]),
            resource: All,
            operation: All,
          },
          {
            principal: All,
            connection: All,
            resource: AnyOf(["a"]),
            operation: AnyOf(["a"]),
          },
        ],
      },
      {
        entry_id: "deny",
        outcome: Deny,
        scope: {
          principal: All,
          connection: All,
          resource: AnyOf(["a"]),
          operation: AnyOf(["a"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }
  assert_eq(
    admit_with_overlap_budget(raw, 3).map(_ => ()),
    Err(OverlapCheckBudgetExceeded("allow", "deny")),
  )
  assert_true(
    admit_with_overlap_budget(raw, 0) is Err(OverlapCheckBudgetExceeded(_, _)),
  )
  assert_true(admit_with_overlap_budget(raw, 100) is Ok(_))
}

///|
test "dimension set algebra over the open universe" {
  let fin = (values : Array[String]) => DimSet::Finite(values)
  let cof = (values : Array[String]) => DimSet::Cofinite(values)
  assert_true(cof([]).minus(cof([])).is_empty())
  assert_true(cof(["a"]).minus(cof([])).is_empty())
  assert_true(!cof([]).minus(cof(["a"])).is_empty())
  assert_true(cof([]).minus(fin(["a"])).contains("zzz"))
  assert_true(!cof([]).minus(fin(["a"])).contains("a"))
  assert_true(fin(["a", "b"]).intersect(cof(["a"])).contains("b"))
  assert_true(!fin(["a", "b"]).intersect(cof(["a"])).contains("a"))
  assert_true(cof(["a"]).intersect(cof(["b"])).contains("c"))
  assert_true(!cof(["a"]).intersect(cof(["b"])).contains("b"))
  assert_true(fin(["a"]).minus(cof(["a"])).contains("a"))
  assert_true(fin(["a"]).intersect(fin(["b"])).is_empty())
}
