///|
priv enum DeltaTransferStep {
  Select
  DeriveNames
  DeriveFields
  Project
}

///|
/// Original immutable evidence and checked operation, not a resource grant.
priv struct DeltaTransferBody {
  b : Budget
  source : @decode.Cursor
  previous : DeltaEvidence
  op : @relation.CheckedOperation
  mut step : DeltaTransferStep
  mut index : Int
  mut count : Int
  mut overwritten : Map[String, Bool]?
  mut fields : Map[String, @graph_contract.CheckedContract]?
  mut iterator : Iter[(String, @graph_contract.CheckedContract)]?
  mut pending : (String, @graph_contract.CheckedContract)?
  mut projection : Array[@relation.ProjectionField]?
}

///|
priv enum DeltaTransferState {
  Pending(DeltaTransferBody)
  Completed(DeltaEvidence)
  Rejected(DeltaTransferBody, Issue)
  Taken
  Cleared
}

///|
priv struct DeltaTransferRead {
  mut state : DeltaTransferState
}

///|
fn begin_delta_transfer_read(
  b : Budget,
  source : @decode.Cursor,
  previous : DeltaEvidence,
  op : @relation.CheckedOperation,
) -> DeltaTransferRead {
  {
    state: Pending({
      b,
      source,
      previous,
      op,
      step: Select,
      index: 0,
      count: 0,
      overwritten: None,
      fields: None,
      iterator: None,
      pending: None,
      projection: None,
    }),
  }
}

///|
fn advance_delta_transfer_read(original : DeltaTransferRead) -> Unit {
  guard original.state is Pending(body) else { return }
  let result = advance_delta_transfer_owned(body) catch {
    Stop(issue) => Err(issue)
  }
  match result {
    Err(issue) => original.state = Rejected(body, issue)
    Ok(Some(value)) => original.state = Completed(value)
    Ok(None) => ()
  }
}

///|
fn take_delta_transfer_read(
  original : DeltaTransferRead,
) -> Result[DeltaEvidence, Issue]? {
  match original.state {
    Completed(value) => {
      original.state = Taken
      Some(Ok(value))
    }
    Rejected(_, issue) => {
      original.state = Taken
      Some(Err(issue))
    }
    _ => None
  }
}

///|
fn clear_delta_transfer_read(original : DeltaTransferRead) -> Unit {
  match original.state {
    Pending(body) | Rejected(body, _) => {
      body.overwritten = None
      body.fields = None
      body.iterator = None
      body.pending = None
      body.projection = None
    }
    _ => ()
  }
  if !(original.state is Taken) {
    original.state = Cleared
  }
}

///|
fn begin_delta_derive_fields(body : DeltaTransferBody) -> Unit {
  body.fields = Some(Map([]))
  body.iterator = Some(body.previous.fields.iter())
  body.count = body.previous.fields.length()
  body.index = 0
  // The empty previous Map was returned before Derive admission. The original
  // iterator pair is captured with this constructor, before any next quotation.
  body.pending = body.iterator.unwrap().next()
  body.step = DeriveFields
}

///|
fn advance_delta_transfer_owned(
  body : DeltaTransferBody,
) -> Result[DeltaEvidence?, Issue] raise Stop {
  let b = body.b
  let source = body.source
  let previous = body.previous
  let op = body.op
  match body.step {
    Select => {
      if previous.fields.is_empty() {
        return Ok(Some(previous))
      }
      match @relation.operation(op) {
        Filter
        | Sort
        | Take
        | AssertRows
        | DedupeRows
        | TopK
        | TopKBy
        | Lag
        | WatermarkRows => return Ok(Some(previous))
        Derive => {
          let bindings = @relation.binding_count(op)
          spend(b, source, bindings + previous.fields.length())
          body.overwritten = Some(Map([]))
          body.count = bindings
          body.index = 0
          if bindings == 0 {
            begin_delta_derive_fields(body)
          } else {
            body.step = DeriveNames
          }
        }
        Select | Rename | Drop | Distinct => {
          if @relation.row_operation(op) is Some(DistinctRows) {
            return Ok(Some(previous))
          }
          let projection = @relation.projection(op)
          spend(b, source, projection.length())
          let fields = Map([])
          body.fields = Some(fields)
          body.projection = Some(projection)
          body.count = projection.length()
          body.index = 0
          if projection.is_empty() {
            return Ok(Some({ fields, }))
          }
          body.step = Project
        }
        _ => return Ok(Some(empty_delta()))
      }
    }
    DeriveNames => {
      if @relation.binding_at(op, body.index).unwrap().name is Some(name) {
        body.overwritten.unwrap()[name] = true
      }
      body.index += 1
      if body.index == body.count {
        begin_delta_derive_fields(body)
      }
    }
    DeriveFields => {
      let (key, value) = body.pending.unwrap()
      let fields = body.fields.unwrap()
      if !body.overwritten.unwrap().contains(key) {
        fields[key] = value
      }
      body.index += 1
      if body.index == body.count {
        return Ok(Some({ fields, }))
      }
      body.pending = body.iterator.unwrap().next()
    }
    Project => {
      let p = body.projection.unwrap()[body.index]
      let fields = body.fields.unwrap()
      if previous.fields.get(@schema.reference_name(p.input)) is Some(c) {
        let name = @schema.reference_name(p.output)
        charge(b, source, name)
        fields[name] = c
      }
      body.index += 1
      if body.index == body.count {
        return Ok(Some({ fields, }))
      }
    }
  }
  Ok(None)
}
