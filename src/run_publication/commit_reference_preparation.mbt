///|
priv enum PublicationInventoryPhase {
  Begin
  Entry(Int)
  Seek(Int, NamedCid, Int, Int)
  Name(Int, NamedCid, Int, Int, String, Int)
  Done(Bool)
}

///|
priv struct PublicationInventoryPreparation {
  mut inputs : (PublicationContract, Array[PublicationContract])?
  mut inventory : @json.FrozenArray[@json.CanonicalValue]?
  max_workspace : Int?
  mut phase : PublicationInventoryPhase
  mut live : Int
  peak : Int
  mut closed : Bool
}

///|
fn start_publication_inventory_preparation(
  request : PublicationContract,
  definitions : Array[PublicationContract],
  max_workspace : Int?,
) -> PublicationInventoryPreparation {
  {
    inputs: Some((request, definitions)),
    inventory: None,
    max_workspace,
    phase: Begin,
    live: 8,
    peak: 8,
    closed: false,
  }
}

///|
fn PublicationInventoryPreparation::step(
  self : PublicationInventoryPreparation,
) -> Result[Unit, PublicationCommitIssue] {
  let (request, definitions) = self.inputs.unwrap()
  match self.phase {
    Begin => {
      if self.max_workspace is Some(limit) && limit < self.live {
        return Err(CommitEncoding)
      }
      match @json.object_field(request.value, "inventory") {
        Some(@json.Array(values)) if @json.array_count(values) ==
          definitions.length() => {
          self.inventory = Some(values)
          self.phase = Entry(0)
        }
        _ => self.phase = Done(false)
      }
    }
    Entry(index) => {
      let inventory = self.inventory.unwrap()
      if index == @json.array_count(inventory) {
        self.phase = Done(true)
      } else {
        self.phase = match
          validate_named_cid_object(
            @json.array_at(inventory, index).unwrap(),
            "result_name",
            "result_definition_cid",
          ) {
          Some(item) => Seek(index, item, 0, 0)
          None => Done(false)
        }
      }
    }
    Seek(entry, item, index, count) =>
      if index == definitions.length() {
        self.phase = if count == 1 { Entry(entry + 1) } else { Done(false) }
      } else if definitions[index].identity == item.cid {
        self.phase = match contract_string(definitions[index], "result_name") {
          Some(name) => Name(entry, item, index, count, name, 0)
          None => Seek(entry, item, index + 1, count)
        }
      } else {
        self.phase = Seek(entry, item, index + 1, count)
      }
    Name(entry, item, index, count, name, offset) => {
      let (comparison, next, _) = @canonical.compare_utf16_fragment(
        name,
        item.name,
        offset,
        64,
      )
      self.phase = match comparison {
        None => Name(entry, item, index, count, name, next)
        Some(comparison) =>
          Seek(
            entry,
            item,
            index + 1,
            count + (if comparison == 0 { 1 } else { 0 }),
          )
      }
    }
    Done(_) => ()
  }
  Ok(())
}

///|
fn PublicationInventoryPreparation::advance(
  self : PublicationInventoryPreparation,
  quantum : Int,
) -> Result[(Bool, Int), PublicationCommitIssue] {
  if self.closed || quantum < 1 {
    return Err(CommitEncoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done(_)) {
    match self.step() {
      Err(issue) => {
        self.cancel()
        return Err(issue)
      }
      Ok(_) => used += 1
    }
  }
  Ok((self.phase is Done(_), used))
}

///|
fn PublicationInventoryPreparation::finish(
  self : PublicationInventoryPreparation,
) -> Result[Bool, PublicationCommitIssue] {
  guard !self.closed && self.phase is Done(valid) else {
    return Err(CommitEncoding)
  }
  self.cancel()
  Ok(valid)
}

///|
fn PublicationInventoryPreparation::cancel(
  self : PublicationInventoryPreparation,
) -> Unit {
  self.inputs = None
  self.inventory = None
  self.phase = Done(false)
  self.live = 0
  self.closed = true
}

///|
priv struct PublicationReferenceInputs {
  run_definition : PublicationContract
  invocation : PublicationContract
  definitions : Array[PublicationContract]
  manifest : PublicationContract
  receipt : PublicationContract
  captured_run : PublicationContract
  request : PublicationContract
  attempt : PublicationContract
  index_entry : PublicationContract
}

///|
priv enum PublicationReferencePhase {
  Begin
  Inventory(PublicationInventoryPreparation)
  Attempt
  Namespace(Int)
  Fields(Int)
  Done
}

///|
priv struct PublicationReferencePreparation {
  mut inputs : PublicationReferenceInputs?
  max_workspace : Int?
  mut phase : PublicationReferencePhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_publication_reference_preparation(
  inputs : PublicationReferenceInputs,
  max_workspace : Int?,
) -> PublicationReferencePreparation {
  {
    inputs: Some(inputs),
    max_workspace,
    phase: Begin,
    live: 16,
    peak: 16,
    closed: false,
  }
}

///|
fn PublicationReferencePreparation::step(
  self : PublicationReferencePreparation,
) -> Result[Unit, PublicationCommitIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Begin => {
      if self.max_workspace is Some(limit) && limit < self.live {
        return Err(CommitEncoding)
      }
      if inputs.request.name != "publication_request" {
        return Err(CommitWrongContract("publication_request"))
      }
      if inputs.attempt.name != "publication_attempt" {
        return Err(CommitWrongContract("publication_attempt"))
      }
      if inputs.index_entry.name != "public_index_entry" {
        return Err(CommitWrongContract("public_index_entry"))
      }
      if contract_string(inputs.request, "run_definition_cid") !=
        Some(inputs.run_definition.identity) {
        return Err(CommitReferenceMismatch("request.run_definition_cid"))
      }
      if self.max_workspace is Some(limit) && 8 > limit - self.live {
        return Err(CommitEncoding)
      }
      self.phase = Inventory(
        start_publication_inventory_preparation(
          inputs.request,
          inputs.definitions,
          match self.max_workspace {
            Some(limit) => Some(limit - self.live)
            None => None
          },
        ),
      )
    }
    Inventory(child) =>
      match child.advance(1) {
        Err(issue) => return Err(issue)
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            match child.finish() {
              Err(issue) => return Err(issue)
              Ok(false) => return Err(CommitInventoryMismatch)
              Ok(true) => self.phase = Attempt
            }
          }
        }
      }
    Attempt => {
      if contract_string(inputs.attempt, "publication_request_cid") !=
        Some(inputs.request.identity) ||
        contract_string(inputs.attempt, "run_definition_cid") !=
        Some(inputs.run_definition.identity) {
        return Err(CommitReferenceMismatch("publication_attempt"))
      }
      self.phase = Namespace(0)
    }
    Namespace(offset) => {
      guard contract_string(inputs.request, "namespace_id") is Some(expected) &&
        contract_string(inputs.index_entry, "namespace_id") is Some(actual) else {
        return Err(CommitReferenceMismatch("index.namespace_id"))
      }
      let (comparison, next, _) = @canonical.compare_utf16_fragment(
        expected, actual, offset, 64,
      )
      match comparison {
        None => self.phase = Namespace(next)
        Some(0) => self.phase = Fields(0)
        Some(_) => return Err(CommitReferenceMismatch("index.namespace_id"))
      }
    }
    Fields(index) =>
      if index == 8 {
        self.phase = Done
      } else {
        let (field, expected) = match index {
          0 =>
            (
              "authority_scope_cid",
              contract_string(inputs.request, "authority_scope_cid"),
            )
          1 => ("run_definition_cid", Some(inputs.run_definition.identity))
          2 => ("invocation_cid", Some(inputs.invocation.identity))
          3 => ("result_manifest_cid", Some(inputs.manifest.identity))
          4 => ("run_receipt_cid", Some(inputs.receipt.identity))
          5 => ("captured_run_cid", Some(inputs.captured_run.identity))
          6 => ("publication_request_cid", Some(inputs.request.identity))
          _ => ("publication_attempt_cid", Some(inputs.attempt.identity))
        }
        if expected is None ||
          contract_string(inputs.index_entry, field) != expected {
          return Err(CommitReferenceMismatch("index." + field))
        }
        self.phase = Fields(index + 1)
      }
    Done => ()
  }
  Ok(())
}

///|
fn PublicationReferencePreparation::advance(
  self : PublicationReferencePreparation,
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
fn PublicationReferencePreparation::cancel(
  self : PublicationReferencePreparation,
) -> Unit {
  if self.phase is Inventory(child) {
    child.cancel()
  }
  self.inputs = None
  self.phase = Done
  self.live = 0
  self.closed = true
}
