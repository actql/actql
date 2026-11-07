///|
// Same Request driver, selected by the installing original, never a numeric
// profile or provider callback. Node's existing original stays Node-only.
priv enum ClientPreparationInitial[I] {
  NodeRequestInitial(@resources.NodePreparationAdmission[I])
  BackedRequestInitial(@resources.BackedPreparationAdmission[I])
}

///|
fn[I] preparation_initial_input(
  initial : ClientPreparationInitial[I],
  input : I,
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  match initial {
    NodeRequestInitial(value) =>
      @resources.check_node_preparation_input(value, input)
    BackedRequestInitial(value) =>
      @resources.check_backed_preparation_input(value, input)
  }
}

///|
fn[I] preparation_initial_start(
  initial : ClientPreparationInitial[I],
  input : I,
) -> Result[@resources.Ledger, @resources.ImportedChildLedgerIssue] {
  match initial {
    NodeRequestInitial(value) =>
      @resources.start_node_preparation_admission(value)
    BackedRequestInitial(value) =>
      @resources.start_backed_preparation_admission(value, input)
  }
}

///|
fn[I] preparation_initial_limits(
  initial : ClientPreparationInitial[I],
  input : I,
) -> Result[@resources.LedgerLimits, @resources.ImportedChildLedgerIssue] {
  match initial {
    NodeRequestInitial(value) =>
      @resources.node_local_preparation_limits(value, input)
    BackedRequestInitial(value) =>
      @resources.backed_preparation_limits(value, input)
  }
}

///|
fn[I] preparation_initial_cleanup(
  initial : ClientPreparationInitial[I],
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  match initial {
    NodeRequestInitial(value) =>
      @resources.cleanup_node_preparation_admission(value)
    BackedRequestInitial(value) =>
      @resources.cleanup_backed_preparation_admission(value)
  }
}

///|
fn[I, P] adopt_preparation_initial(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, P],
  prepared : P,
) -> Result[
  (
    @resources.PreparedRunAdmission[P],
    @resources.Ledger,
    @resources.PreparationRetirement,
    @resources.PreparationBodyBorrow[P],
  ),
  @resources.ImportedChildLedgerIssue,
] {
  match initial {
    NodeRequestInitial(value) =>
      @resources.adopt_node_preparation_admission(
        value, input, capacity, prepared,
      ).map(original => {
        (
          @resources.node_prepared_run_admission(original.0),
          original.1,
          original.2,
          original.3,
        )
      })
    BackedRequestInitial(value) =>
      @resources.adopt_backed_preparation_admission(
        value, input, capacity, prepared,
      ).map(original => {
        (
          @resources.backed_prepared_run_admission(original.0),
          original.1,
          original.2,
          original.3,
        )
      })
  }
}
