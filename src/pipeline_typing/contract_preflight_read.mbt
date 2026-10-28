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
priv struct ContractPreflightRead {
  b : Budget
  source : @decode.Cursor
  work : Array[(@contract.Contract, Int)]
  mut state : ContractPreflightState
}

///|
fn begin_contract_preflight_read(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  depth : Int,
) -> ContractPreflightRead {
  { b, source, work: [(root, depth)], state: Pending, }
}

///|
/// Advance exactly the next original popped Contract. Its own field count is
/// available before pushing children; no recursive quote or second type walk.
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
  if work.pop() is Some((c, depth)) {
    spend(b, source, 1)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, source, count)
        for i in 0..<count {
          let f = @contract.field_at(fields, i).unwrap()
          charge(b, source, f.name)
          work.push((f.contract, depth + 1))
        }
      }
      @contract.ResourceRef(resource_kind~) => charge(b, source, resource_kind)
      @contract.ContentRef(media_type=Some(media)) => charge(b, source, media)
      _ => ()
    }
  }
  if work.is_empty() {
    read.state = Complete
  }
}

///|
fn clear_contract_preflight_read(read : ContractPreflightRead) -> Unit {
  read.work.clear()
  read.state = Cleared
}
