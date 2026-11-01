///|
// Only the Node installer can issue this handle. Other targets have no
// inhabitants, rather than a scalar token, fallback issuer or dummy owner.
// The phantom parameter preserves the same abstract input-indexed API.
enum NodePreparationAdmission[_] {}

///|
pub fn[I] start_node_preparation_admission(
  owner : NodePreparationAdmission[I],
) -> Result[Ledger, ImportedChildLedgerIssue] {
  match owner {

  }
}

///|
pub fn[I] node_local_preparation_limits(
  owner : NodePreparationAdmission[I],
  _input : I,
) -> Result[LedgerLimits, ImportedChildLedgerIssue] {
  match owner {

  }
}

///|
// Other backends cannot construct the Node-only original; preserve the same
// abstract declaration without a fallback Ledger or inventory issuer.
pub fn[I] begin_node_preparation_inventory(
  owner : NodePreparationAdmission[I],
  _input : I,
  _retained_bytes : Int64,
  _execution_bytes : Int64,
  _max_reservations : Int,
  _max_holdings : Int,
  _max_delegations : Int,
) -> Result[OriginalLedgerIdentity, ImportedChildLedgerIssue] {
  match owner {

  }
}

///|
pub fn[I, P] adopt_node_preparation_admission(
  owner : NodePreparationAdmission[I],
  _input : I,
  _capacity : PreparationCapacity[I, P],
  _prepared : P,
) -> Result[
  (
    NodeManagedRunAdmission[P],
    Ledger,
    PreparationRetirement,
    PreparationBodyBorrow[P],
  ),
  ImportedChildLedgerIssue,
] {
  match owner {

  }
}

///|
pub fn[I] cleanup_node_preparation_admission(
  owner : NodePreparationAdmission[I],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match owner {

  }
}

///|
pub fn[I] check_node_preparation_input(
  owner : NodePreparationAdmission[I],
  _input : I,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match owner {

  }
}
