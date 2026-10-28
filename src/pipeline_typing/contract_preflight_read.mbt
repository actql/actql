///|
/// Private continuation of the original Contract preflight. The Budget and
/// admitted Contract/Source are borrowed; this is not another resource Owner.
priv enum ContractPreflightState {
  Pending
  Complete
  Rejected(Issue)
  Cleared
}

///|
priv enum ContractPreflightStep {
  Node
  Fields
  PushArray
  PushField
} derive(Eq)

///|
priv struct ContractPreflightRead {
  b : Budget
  source : @decode.Cursor
  work : Array[(@contract.Contract, Int)]
  mut state : ContractPreflightState
  mut step : ContractPreflightStep
  mut fields : @contract.Fields?
  mut child : @contract.Contract?
  mut depth : Int
  mut index : Int
  mut count : Int
}

///|
fn begin_contract_preflight_read(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  depth : Int,
) -> ContractPreflightRead {
  {
    b,
    source,
    work: [(root, depth)],
    state: Pending,
    step: Node,
    fields: None,
    child: None,
    depth: 0,
    index: 0,
    count: 0,
  }
}

///|
/// Return before each child tuple/pending-buffer write. The original semantic
/// spend and name charge precede that write exactly as in the original loop.
/// No recursive quote, duplicate type traversal or copied Budget is needed.
fn advance_contract_preflight_read(read : ContractPreflightRead) -> Unit {
  if !(read.state is Pending) {
    return
  }
  advance_contract_preflight_read_owned(read) catch {
    Stop(issue) => read.state = Rejected(issue)
  }
}

///|
fn advance_contract_preflight_read_owned(
  read : ContractPreflightRead,
) -> Unit raise Stop {
  let b = read.b
  let source = read.source
  let work = read.work
  match read.step {
    Node =>
      if work.pop() is Some((c, depth)) {
        spend(b, source, 1)
        if depth > b.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        match c.shape {
          @contract.Array(item, ..) => {
            read.child = Some(item)
            read.depth = depth
            read.step = PushArray
          }
          @contract.Object(fields) => {
            let count = @contract.field_count(fields)
            spend(b, source, count)
            if count > 0 {
              read.fields = Some(fields)
              read.depth = depth
              read.index = 0
              read.count = count
              read.step = Fields
            }
          }
          @contract.ResourceRef(resource_kind~) =>
            charge(b, source, resource_kind)
          @contract.ContentRef(media_type=Some(media)) =>
            charge(b, source, media)
          _ => ()
        }
      }
    Fields => {
      let field = @contract.field_at(read.fields.unwrap(), read.index).unwrap()
      charge(b, source, field.name)
      read.child = Some(field.contract)
      read.step = PushField
    }
    PushArray => {
      work.push((read.child.unwrap(), read.depth + 1))
      read.child = None
      read.step = Node
    }
    PushField => {
      work.push((read.child.unwrap(), read.depth + 1))
      read.child = None
      read.index += 1
      if read.index == read.count {
        read.fields = None
        read.step = Node
      } else {
        read.step = Fields
      }
    }
  }
  if read.step == Node && work.is_empty() {
    read.state = Complete
  }
}

///|
fn clear_contract_preflight_read(read : ContractPreflightRead) -> Unit {
  read.work.clear()
  read.fields = None
  read.child = None
  read.state = Cleared
}
