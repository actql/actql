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
pub fn[I, P] adopt_node_preparation_admission(
  owner : NodePreparationAdmission[I],
  _input : I,
  _capacity : PreparationCapacity[I, P],
  _prepared : P,
) -> Result[
  (NodeManagedRunAdmission[P], Ledger, PreparationRetirement),
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
