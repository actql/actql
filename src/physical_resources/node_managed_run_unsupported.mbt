///|
// The Node issuer is absent on this target. No reference, callback or scalar
// can inhabit this handle; these signatures retain only the generic API.
enum NodeManagedRunAdmission[_] {}

///|
pub fn[P] cleanup_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] reserve_node_managed_run_read_bootstrap(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
  _ledger : Ledger,
  _retained_bytes : Int64,
  _execution_bytes : Int64,
) -> Result[CapacityReservation, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] start_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
) -> Result[Ledger, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] restore_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
  _saved : LedgerContinuationState,
) -> Result[Ledger, LedgerContinuationIssue] {
  match value {

  }
}

///|
pub fn[P] check_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
  _ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] check_node_managed_run_mutable_admission(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
  _ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] reserve_node_managed_run_attempt(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
  _ledger : Ledger,
  _transfer_bytes : Int64,
  _retained_bytes : Int64,
  _execution_bytes : Int64,
  quantities? : QuantityAmounts? = None,
) -> Result[Reservation, ImportedChildLedgerIssue] {
  ignore(quantities)
  match value {

  }
}

///|
// The original Node admission has no inhabitants on this target. Preserve
// the same closed boundary without inventing a resource port or refusal.
fn[P, E] check_node_managed_run_operation_original(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
  _ledger : Ledger,
  _original : () -> Result[Unit, E],
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  match value {

  }
}

///|
pub fn[P] check_node_managed_run_preparation(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] check_node_local_mock_model_run_preparation(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] check_node_source_compute_run_preparation(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] check_node_local_content_run_preparation(
  value : NodeManagedRunAdmission[P],
  _prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] report_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] stop_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
pub fn[P] release_node_preparation_holder(
  admission : NodeManagedRunAdmission[P],
) -> Result[Bool, ImportedChildLedgerIssue] {
  match admission {

  }
}

///|
pub fn[P] node_preparation_usage_isolated(
  admission : NodeManagedRunAdmission[P],
  _ledger : Ledger,
) -> Bool {
  match admission {

  }
}

///|
pub fn[P] check_node_preparation_cleanup_original(
  value : NodeManagedRunAdmission[P],
  _ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match value {

  }
}

///|
// The foreign references belong only to the fixed Node installer. Unsupported
// targets expose the same abstract names but have no way to obtain a value.
enum OriginalNodeManagedRunReference {}

///|
enum OriginalNodeSourceReference {}

///|
pub fn[P] prepare_node_managed_run_admission(
  original : OriginalNodeManagedRunReference,
  _prepared : P,
) -> Result[NodeManagedRunAdmission[P], ImportedChildLedgerIssue] {
  match original {

  }
}

///|
pub fn[P] prepare_node_local_mock_model_run_admission(
  original : OriginalNodeManagedRunReference,
  _prepared : P,
) -> Result[NodeManagedRunAdmission[P], ImportedChildLedgerIssue] {
  match original {

  }
}

///|
pub fn[P] prepare_node_local_content_run_admission(
  original : OriginalNodeManagedRunReference,
  _prepared : P,
) -> Result[NodeManagedRunAdmission[P], ImportedChildLedgerIssue] {
  match original {

  }
}

///|
pub fn[I] prepare_node_local_preparation_admission(
  original : OriginalNodeManagedRunReference,
  _input : I,
) -> Result[NodePreparationAdmission[I], ImportedChildLedgerIssue] {
  match original {

  }
}

///|
pub fn prepare_node_original_source_child(
  original : OriginalNodeSourceReference,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  match original {

  }
}
