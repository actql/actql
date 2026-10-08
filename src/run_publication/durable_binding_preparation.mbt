///|
priv struct DurableBindingInputs {
  run_definition : PublicationContract
  invocation : PublicationContract
  definitions : Array[PublicationContract]
  artifacts : Array[PublicationContract]
  orderings : Array[PublicationContract]
  retentions : Array[PublicationContract]
  bindings : Array[PublicationContract]
  index_entry : PublicationContract
}

///|
priv enum DurableBindingPhase {
  Begin
  Binding(Int)
  DuplicateIdentity(Int)
  DuplicateDefinition(String, Int)
  Definition(String, Int)
  Artifact(String, Int, Int, Int)
  Ordering(String, Int)
  Retention(String, Int)
  Fields(Int)
  Index
  IndexStrings(@json.FrozenArray[@json.CanonicalValue], Int)
  IndexMatches(@json.FrozenArray[@json.CanonicalValue], Int, Int, Int)
  Done
}

///|
/// Borrow the admitted inventories. No copied, filtered or sorted inventory
/// is needed: uniqueness and exact index membership are checked by cursors.
priv struct DurableBindingPreparation {
  mut inputs : DurableBindingInputs?
  max_workspace : Int?
  mut binding : Int
  mut artifact : Int
  mut phase : DurableBindingPhase
  mut live : Int
  peak : Int
  mut closed : Bool
}

///|
fn start_durable_binding_preparation(
  inputs : DurableBindingInputs,
  max_workspace : Int?,
) -> DurableBindingPreparation {
  {
    inputs: Some(inputs),
    max_workspace,
    binding: 0,
    artifact: -1,
    phase: Begin,
    live: 16,
    peak: 16,
    closed: false,
  }
}

///|
fn DurableBindingPreparation::step(
  self : DurableBindingPreparation,
) -> Result[Unit, PublicationCommitIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Begin => {
      if self.max_workspace is Some(limit) && limit < self.live {
        return Err(CommitEncoding)
      }
      if inputs.bindings.length() != inputs.definitions.length() ||
        inputs.bindings.is_empty() {
        return Err(CommitInventoryMismatch)
      }
      self.phase = Binding(0)
    }
    Binding(index) =>
      if index == inputs.bindings.length() {
        self.phase = Index
      } else {
        self.binding = index
        if inputs.bindings[index].name != "durable_result_binding" {
          return Err(CommitWrongContract("durable_result_binding"))
        }
        self.phase = DuplicateIdentity(0)
      }
    DuplicateIdentity(prior) =>
      if prior < self.binding {
        if inputs.bindings[prior].identity ==
          inputs.bindings[self.binding].identity {
          return Err(CommitInventoryMismatch)
        }
        self.phase = DuplicateIdentity(prior + 1)
      } else {
        guard contract_string(
            inputs.bindings[self.binding],
            "result_definition_cid",
          )
          is Some(cid) else {
          return Err(CommitReferenceMismatch("binding.result_definition_cid"))
        }
        self.phase = DuplicateDefinition(cid, 0)
      }
    DuplicateDefinition(cid, prior) =>
      if prior < self.binding {
        if contract_string(inputs.bindings[prior], "result_definition_cid") ==
          Some(cid) {
          return Err(CommitInventoryMismatch)
        }
        self.phase = DuplicateDefinition(cid, prior + 1)
      } else {
        self.phase = Definition(cid, 0)
      }
    Definition(cid, index) => {
      if index == inputs.definitions.length() {
        return Err(CommitInventoryMismatch)
      }
      self.phase = if inputs.definitions[index].identity == cid {
        Artifact(cid, 0, -1, 0)
      } else {
        Definition(cid, index + 1)
      }
    }
    Artifact(cid, index, found, count) =>
      if index < inputs.artifacts.length() {
        let matches = contract_string(
            inputs.artifacts[index],
            "result_definition_cid",
          ) ==
          Some(cid)
        self.phase = Artifact(
          cid,
          index + 1,
          if matches {
            index
          } else {
            found
          },
          count + (if matches { 1 } else { 0 }),
        )
      } else {
        if count != 1 {
          return Err(CommitInventoryMismatch)
        }
        self.artifact = found
        guard contract_string(inputs.artifacts[found], "ordering_evidence_cid")
          is Some(cid) else {
          return Err(CommitReferenceMismatch("binding.ordering_evidence_cid"))
        }
        self.phase = Ordering(cid, 0)
      }
    Ordering(cid, index) => {
      if index == inputs.orderings.length() {
        return Err(CommitReferenceMismatch("binding.ordering_evidence_cid"))
      }
      if inputs.orderings[index].identity == cid {
        guard contract_string(
            inputs.artifacts[self.artifact],
            "effective_retention_policy_cid",
          )
          is Some(cid) else {
          return Err(
            CommitReferenceMismatch("binding.effective_retention_policy_cid"),
          )
        }
        self.phase = Retention(cid, 0)
      } else {
        self.phase = Ordering(cid, index + 1)
      }
    }
    Retention(cid, index) => {
      if index == inputs.retentions.length() {
        return Err(
          CommitReferenceMismatch("binding.effective_retention_policy_cid"),
        )
      }
      if inputs.retentions[index].identity == cid {
        let artifact = inputs.artifacts[self.artifact]
        if contract_string(artifact, "logical_result_cid") is None ||
          contract_string(artifact, "result_schema_cid") is None {
          return Err(CommitReferenceMismatch("artifact.identity"))
        }
        self.phase = Fields(0)
      } else {
        self.phase = Retention(cid, index + 1)
      }
    }
    Fields(index) => {
      let binding = inputs.bindings[self.binding]
      let artifact = inputs.artifacts[self.artifact]
      if index == 6 {
        if contract_count(binding, "row_count") !=
          contract_count(artifact, "actual_row_count") {
          return Err(CommitReferenceMismatch("binding.row_count"))
        }
        self.phase = Binding(self.binding + 1)
      } else {
        let (field, expected) = match index {
          0 => ("run_definition_cid", inputs.run_definition.identity)
          1 => ("invocation_cid", inputs.invocation.identity)
          2 =>
            (
              "logical_result_cid",
              contract_string(artifact, "logical_result_cid").unwrap(),
            )
          3 =>
            (
              "result_schema_cid",
              contract_string(artifact, "result_schema_cid").unwrap(),
            )
          4 =>
            (
              "ordering_evidence_cid",
              contract_string(artifact, "ordering_evidence_cid").unwrap(),
            )
          _ =>
            (
              "effective_retention_policy_cid",
              contract_string(artifact, "effective_retention_policy_cid").unwrap(),
            )
        }
        if contract_string(binding, field) != Some(expected) {
          return Err(CommitReferenceMismatch("binding." + field))
        }
        self.phase = Fields(index + 1)
      }
    }
    Index => {
      guard @json.object_field(
          inputs.index_entry.value,
          "durable_result_binding_cids",
        )
        is Some(@json.Array(values)) else {
        return Err(CommitReferenceMismatch("index.durable_result_binding_cids"))
      }
      self.phase = IndexStrings(values, 0)
    }
    IndexStrings(values, index) =>
      if index < @json.array_count(values) {
        if string_value(@json.array_at(values, index).unwrap()) is None {
          return Err(
            CommitReferenceMismatch("index.durable_result_binding_cids"),
          )
        }
        self.phase = IndexStrings(values, index + 1)
      } else {
        if @json.array_count(values) != inputs.bindings.length() {
          return Err(CommitInventoryMismatch)
        }
        self.phase = IndexMatches(values, 0, 0, 0)
      }
    IndexMatches(values, binding, index, count) =>
      if binding == inputs.bindings.length() {
        self.phase = Done
      } else if index < @json.array_count(values) {
        let matches = string_value(@json.array_at(values, index).unwrap()) ==
          Some(inputs.bindings[binding].identity)
        self.phase = IndexMatches(
          values,
          binding,
          index + 1,
          count + (if matches { 1 } else { 0 }),
        )
      } else {
        if count != 1 {
          return Err(CommitInventoryMismatch)
        }
        self.phase = IndexMatches(values, binding + 1, 0, 0)
      }
    Done => ()
  }
  Ok(())
}

///|
fn DurableBindingPreparation::advance(
  self : DurableBindingPreparation,
  quantum : Int,
) -> Result[(Bool, Int), PublicationCommitIssue] {
  if self.closed || quantum < 1 {
    return Err(CommitEncoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done) {
    match self.step() {
      Err(issue) => {
        self.cancel()
        return Err(issue)
      }
      Ok(_) => used += 1
    }
  }
  Ok((self.phase is Done, used))
}

///|
fn DurableBindingPreparation::cancel(self : DurableBindingPreparation) -> Unit {
  self.inputs = None
  self.phase = Done
  self.live = 0
  self.closed = true
}
