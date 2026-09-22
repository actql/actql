///|
/// Run one kernel attempt behind the same workspace scope used by product
/// execution. The returned counters remain observable after rollback.
fn[T] kernel_budget_attempt(
  work : Int,
  slots : Int,
  run : (ControlBudget, RowWorkspace) -> Result[T, RowIssue],
) -> (Result[T, RowIssue], Int, Int, Int) {
  let control = { remaining: work, max_frames: 100, }
  let workspace = row_workspace(slots)
  let result = with_scoped_slots(workspace, fn() { run(control, workspace) })
  (result, work - control.remaining, workspace.peak, workspace.live)
}

///|
fn row_issue_label(issue : RowIssue) -> String {
  match issue {
    OwnerMismatch => "OwnerMismatch"
    InputMismatch => "InputMismatch"
    InvalidRows => "InvalidRows"
    RowLimit => "RowLimit"
    InvalidRowLimits => "InvalidRowLimits"
    MissingOrderedResourceContext => "MissingOrderedResourceContext"
    LogicalRows(_) => "LogicalRows"
    Evaluation(_, _, _) => "Evaluation"
    Comparison(_) => "Comparison"
    Aggregation(_) => "Aggregation"
    DedupeTopTie(_, _) => "DedupeTopTie"
    DedupeIdentityCollision => "DedupeIdentityCollision"
    AssertionPredicate(_) => "AssertionPredicate"
    AssertionNullKey(_, _) => "AssertionNullKey"
    AssertionDuplicate(_, _) => "AssertionDuplicate"
    JoinNullKey(_, _, _) => "JoinNullKey"
    JoinDuplicateKey(_, _, _) => "JoinDuplicateKey"
    AsOfTopTie(_, _, _) => "AsOfTopTie"
    WindowTime(_) => "WindowTime"
    WindowArithmetic(_) => "WindowArithmetic"
    AnalyticEnvelope(_) => "AnalyticEnvelope"
    NestItemLimitRequired => "NestItemLimitRequired"
    NestItemLimit(_) => "NestItemLimit"
    NestEnvelope(_) => "NestEnvelope"
  }
}

///|
/// Measure one successful kernel and exhaustively sweep both independent
/// resource axes around its exact requirements. Every rejected attempt must
/// remain a resource error and must return the workspace to zero live slots.
fn[T] assert_kernel_budget_sweep(
  name : String,
  run : (ControlBudget, RowWorkspace) -> Result[T, RowIssue],
) -> Unit raise {
  let maximum = 1000000
  let (sample, used, peak, _) = kernel_budget_attempt(maximum, maximum, run)
  if sample is Err(issue) {
    fail(name + " baseline failed: " + row_issue_label(issue))
  }
  assert_true(used > 0)
  assert_true(peak > 0)
  for slots = 0; slots <= peak + 1; slots = slots + 1 {
    let (result, _, _, live) = kernel_budget_attempt(used, slots, run)
    if slots < peak {
      match result {
        Err(RowLimit) => ()
        Err(issue) =>
          fail(
            name +
            " non-resource slot failure at " +
            slots.to_string() +
            ": " +
            row_issue_label(issue),
          )
        _ => fail(name + " unexpected slot success")
      }
      assert_eq(live, 0)
    } else if result is Err(_) {
      fail(name + " rejected admitted slots")
    }
  }
  for work = 0; work <= used + 1; work = work + 1 {
    let (result, _, _, live) = kernel_budget_attempt(work, peak, run)
    if work < used {
      match result {
        Err(RowLimit) => ()
        Err(issue) =>
          fail(
            name +
            " non-resource work failure at " +
            work.to_string() +
            ": " +
            row_issue_label(issue),
          )
        _ => fail(name + " unexpected work success")
      }
      assert_eq(live, 0)
    } else if result is Err(_) {
      fail(name + " rejected admitted work")
    }
  }
}
