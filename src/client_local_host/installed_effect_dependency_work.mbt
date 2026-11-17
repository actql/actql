///|
// One construction continuation on the SAME adopted preparation. The original
// Ledger policy bounds coheld retained/execution representations; it supplies
// no body/entry credit. Actual numeric grows remain mandatory before arrays,
// copies and emitters. No dispatch100k counter or physical allowance changes.
fn begin_installed_effect_dependency_work(
  admission : @resources.PreparedRunAdmission[ClientInstalledEffectManagedPlan],
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
  control : ClientEffectOperationControls,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if control.dependency_work is Some(_) {
    return Err(AlreadyBound)
  }
  let policy = @resources.ledger_limits(ledger)
  // Closed codecs/heap sort/index algorithms have <=31 levels (Int-indexed
  // inventories) and <=32 fixed walks. Each variable key/code-unit occupies
  // >=2 representation bytes; each indexed node owns pointer/record storage.
  //128 work units per admitted representation byte majorizes those walks,
  // comparisons and scalar visits. It is a finite algorithmic maximum only:
  // successful prefix grows and actual Work spending are independently checked.
  guard @execution.checked_preparation_add_product(
      policy.retained_bytes,
      policy.execution_bytes,
      1L,
    )
    is Some(span) &&
    @execution.checked_preparation_add_product(256L, span, 128L)
    is Some(maximum) else {
    return Err(InsufficientCapacity)
  }
  match
    @resources.begin_prepared_run_publication_work(
      admission, plan, ledger, maximum,
    ) {
    Err(issue) => Err(Resource(issue))
    Ok(receipt) =>
      match @resources.return_preparation_phase_work_continuation64(receipt) {
        Err(_) => {
          @resources.finish_preparation_phase_work_continuation64(receipt)
          |> ignore
          Err(ForeignOriginal)
        }
        Ok(_) => {
          control.dependency_work = Some(receipt)
          Ok(())
        }
      }
  }
}

///|
// Receipt views never cross callbacks/awaits: resume only after the actual
// original current fence, return in defer after the closed task has unwound.
fn[R] with_installed_effect_dependency_work(
  control : ClientEffectOperationControls,
  admission : @resources.PreparedRunAdmission[ClientInstalledEffectManagedPlan],
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
  original : () -> Result[Unit, ClientInstalledManagedRunIssue],
  reservation : @resources.CapacityReservation,
  live : () -> Bool,
  task : ((Int) -> Result[Unit, @resources.LedgerIssue]) -> Result[
    R,
    @resources.NodeManagedRunOperationIssue[ClientInstalledManagedRunIssue],
  ],
) -> Result[
  R,
  @resources.NodeManagedRunOperationIssue[ClientInstalledManagedRunIssue],
] {
  guard control.dependency_work is Some(receipt) else {
    return Err(Control(ForeignOwner))
  }
  // The Resource view performs current once before invoking this trusted
  // synchronous task. Resuming itself invokes no external current callback.
  @resources.with_prepared_run_operation_control_publication_work(
    admission,
    plan,
    ledger,
    original,
    reservation,
    live,
    receipt,
    spend => {
      if @resources.resume_preparation_phase_work_continuation64(receipt)
        is Err(_) {
        return Err(Control(ForeignOwner))
      }
      defer @resources.return_preparation_phase_work_continuation64(receipt)
        |> ignore
      task(spend)
    },
  )
}
