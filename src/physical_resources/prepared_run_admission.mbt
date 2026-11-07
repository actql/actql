///|
/// A closed view of existing original admissions. Neither variant creates a
/// resource, purpose or Ledger. The Node token stays uninhabited off Node.
enum PreparedRunAdmission[P] {
  NodePreparedRun(NodeManagedRunAdmission[P])
  BackedPreparedRun(BackedPreparedRunAdmission[P])
}

///|
pub fn[P] node_prepared_run_admission(
  value : NodeManagedRunAdmission[P],
) -> PreparedRunAdmission[P] {
  NodePreparedRun(value)
}

///|
pub fn[P] backed_prepared_run_admission(
  value : BackedPreparedRunAdmission[P],
) -> PreparedRunAdmission[P] {
  BackedPreparedRun(value)
}

///|
pub fn[P] check_prepared_run_admission(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {
    NodePreparedRun(original) =>
      check_node_managed_run_mutable_admission(original, prepared, ledger)
    BackedPreparedRun(original) =>
      check_backed_prepared_run_admission(original, prepared, ledger)
  }
}

///|
pub fn[P] check_prepared_run_cleanup_original(
  value : PreparedRunAdmission[P],
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {
    NodePreparedRun(original) =>
      check_node_preparation_cleanup_original(original, ledger)
    BackedPreparedRun(original) =>
      check_backed_preparation_cleanup_original(original, ledger)
  }
}

///|
pub fn[P] prepared_run_usage_isolated(
  value : PreparedRunAdmission[P],
  ledger : Ledger,
) -> Bool {
  match value {
    NodePreparedRun(original) =>
      node_preparation_usage_isolated(original, ledger)
    BackedPreparedRun(original) =>
      backed_preparation_usage_isolated(original, ledger)
  }
}

///|
pub fn[P] release_prepared_run_holder(
  value : PreparedRunAdmission[P],
) -> Result[Bool, ImportedChildLedgerIssue] {
  match value {
    NodePreparedRun(original) => release_node_preparation_holder(original)
    BackedPreparedRun(original) => release_backed_preparation_holder(original)
  }
}

///|
pub fn[P] cleanup_prepared_run_admission(
  value : PreparedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {
    NodePreparedRun(original) => cleanup_node_managed_run_admission(original)
    BackedPreparedRun(original) =>
      cleanup_backed_prepared_run_admission(original)
  }
}

///|
// Only the closed Resource operations below consume this immediate result.
// The original consumer can neither retain it nor acquire a current proof.
fn[P, E] check_prepared_run_operation_original(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  match value {
    NodePreparedRun(value) =>
      check_node_managed_run_operation_original(
        value, prepared, ledger, original,
      )
    BackedPreparedRun(value) => {
      match check_backed_prepared_run_admission(value, prepared, ledger) {
        Err(issue) => return Err(Admission(issue))
        Ok(_) => ()
      }
      match original() {
        Err(issue) => return Err(Original(issue))
        Ok(_) => ()
      }
      match check_backed_prepared_run_binding(value, prepared, ledger) {
        Err(issue) => return Err(Admission(issue))
        Ok(_) => ()
      }
      match check_imported_original_child_ledger_current(value.child, ledger) {
        Err(issue) => return Err(Admission(issue))
        Ok(_) => ()
      }
      check_original_resources_mutable_current(ledger).map_err(issue => {
        Admission(Resource(issue))
      })
    }
  }
}

///|
// The existing attempt constructor, shared after original admission.
pub fn[P] reserve_prepared_run_attempt(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  quantities? : QuantityAmounts? = None,
) -> Result[Reservation, ImportedChildLedgerIssue] {
  if transfer_bytes < 0L || retained_bytes < 0L || execution_bytes < 0L {
    return Err(Resource(InvalidCharge))
  }
  match check_prepared_run_admission(value, prepared, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_imported_child_admission_current(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  reserve_attempt_current(
    ledger, transfer_bytes, retained_bytes, execution_bytes, quantities,
  ).map_err(issue => Resource(issue))
}
