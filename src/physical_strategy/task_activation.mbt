///|
/// Opaque proof that one task activation is inside the Run's admitted
/// authorization envelope. It is created only from an evaluated
/// `AuthorizedForDispatch` runtime action or from the Host's explicit
/// statement that the activation has no protected scope (pure compute over
/// already captured inputs on an unprotected in-process Site). It carries no
/// data and costs no evaluation to check.
struct TaskActivationGrant {
  basis : TaskActivationBasis
}

///|
priv enum TaskActivationBasis {
  Authorized(@authorization.DispatchBasis)
  Covered
}

///|
/// Only `AuthorizedForDispatch` yields a grant. Deny, Checkpoint and
/// DecisionFailure never authorize an activation.
pub fn task_activation_authorized(
  action : @authorization.RuntimeAction,
) -> TaskActivationGrant? {
  match action {
    AuthorizedForDispatch(basis) => Some({ basis: Authorized(basis), })
    _ => None
  }
}

///|
/// Explicit coverage for an activation with no protected scope. The Host
/// states this after its own local coverage check; it is never derived from
/// Program input and grants no connection, resource or transfer.
pub fn task_activation_covered() -> TaskActivationGrant {
  { basis: Covered, }
}

///|
/// The evaluated dispatch basis, or `None` for explicit no-protected-scope
/// coverage.
pub fn task_activation_grant_basis(
  grant : TaskActivationGrant,
) -> @authorization.DispatchBasis? {
  match grant.basis {
    Authorized(basis) => Some(basis)
    Covered => None
  }
}

///|
/// Seal the per-task activation requirement on this Run. It is one-way: once
/// required, every task start (Local, DuckDB, managed, synchronous or native
/// realization) consumes an exact grant for that task, and nothing clears the
/// requirement.
pub fn require_captured_task_activation(run : CapturedDAG) -> Unit {
  run.activation_required = true
}

///|
pub fn captured_task_activation_required(run : CapturedDAG) -> Bool {
  run.activation_required
}

///|
/// Install the grant for exactly the next ready task at the current strategy
/// revision. A grant is single-use; a retry, replan or later task needs a new
/// one. Resident provisioning between the grant and the start does not
/// invalidate it: it changes physical progress, not the task or its revision.
pub fn authorize_captured_task_activation(
  run : CapturedDAG,
  task : Int,
  grant : TaskActivationGrant,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  ignore(task_activation_grant_basis(grant))
  run.activation_grant = Some((task, run.revisions))
  Ok(())
}

///|
/// Pending grant for `task` at the current strategy revision, without
/// consuming it.
pub fn captured_task_activation_granted(run : CapturedDAG, task : Int) -> Bool {
  run.activation_grant is Some((granted, revision)) &&
  granted == task &&
  revision == run.revisions
}

///|
/// Checked by every task start before any reservation or external work. The
/// grant is consumed whether or not the start later succeeds.
fn consume_task_activation(run : CapturedDAG, task : Int) -> Bool {
  if !run.activation_required {
    return true
  }
  let granted = captured_task_activation_granted(run, task)
  run.activation_grant = None
  granted
}
