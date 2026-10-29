///|
/// States of the original literal admission, not another type or resource Owner.
pub(all) enum LiteralDomainsReadPhase {
  Pending
  Complete
  Failed
  Taken
  Cleared
} derive(Eq, Debug)

///|
priv struct LiteralDomainsReadBody {
  source : @decode.Cursor
  domains : LiteralDomains
  limits : TransferLimits
  budget : TransferBudget
  fields : Iter[(String, LiteralDomain)]
  mut domain : LiteralDomain?
  mut index : Int
}

///|
priv enum LiteralDomainsReadState {
  Reading(LiteralDomainsReadBody)
  Completed(LiteralTransfer)
  Rejected(LiteralDomainsReadBody, Issue)
  Taken
  Cleared
}

///|
struct LiteralDomainsRead {
  mut state : LiteralDomainsReadState
}

///|
pub fn begin_literal_domains_read(
  source : @decode.Cursor,
  domains : LiteralDomains,
  limits : TransferLimits,
) -> Result[LiteralDomainsRead, Issue] {
  if limits.max_work < 0 || limits.max_name_bytes < 0 {
    return fail(source, InvalidLimits) catch { Stop(issue) => Err(issue) }
  }
  Ok({
    state: Reading({
      source,
      domains,
      limits,
      budget: { work: limits.max_work, text: limits.max_name_bytes, },
      fields: domains.fields.iter(),
      domain: None,
      index: 0,
    }),
  })
}

///|
pub fn literal_domains_read_phase(
  read : LiteralDomainsRead,
) -> LiteralDomainsReadPhase {
  match read.state {
    Reading(_) => Pending
    Completed(_) => Complete
    Rejected(_, _) => Failed
    Taken => Taken
    Cleared => Cleared
  }
}

///|
/// Original partial work remains observable on rejection, not successful Usage.
pub fn literal_domains_read_consumed_work(read : LiteralDomainsRead) -> Int? {
  match read.state {
    Reading(body) | Rejected(body, _) =>
      Some(body.limits.max_work - body.budget.work)
    Completed(transfer) => Some(transfer.work)
    _ => None
  }
}

///|
/// Borrow the original refusal without taking its retained partial-work body.
pub fn literal_domains_read_issue(read : LiteralDomainsRead) -> Issue? {
  match read.state {
    Rejected(_, issue) => Some(issue)
    _ => None
  }
}

///|
pub fn advance_literal_domains_read(
  read : LiteralDomainsRead,
) -> LiteralDomainsReadPhase {
  guard read.state is Reading(body) else {
    return literal_domains_read_phase(read)
  }
  advance_literal_domains_read_owned(body) catch {
    Stop(issue) => {
      read.state = Rejected(body, issue)
      return Failed
    }
  }
  if body.domain is None && body.index == -1 {
    read.state = Completed({
      domains: body.domains,
      work: body.limits.max_work - body.budget.work,
      text_bytes: body.limits.max_name_bytes - body.budget.text,
    })
  }
  literal_domains_read_phase(read)
}

///|
fn advance_literal_domains_read_owned(
  body : LiteralDomainsReadBody,
) -> Unit raise Stop {
  let b = body.budget
  let source = body.source
  if body.domain is Some(domain) {
    if body.index < domain.values.length() {
      literal_charge(b, source, domain.values[body.index])
      body.index += 1
    } else {
      body.domain = None
    }
    return
  }
  match body.fields.next() {
    Some((name, domain)) => {
      spend(b, source, 1)
      let bytes = @scalar.admit_utf8_length(name, b.text).unwrap_or(-1)
      if bytes < 0 {
        fail(source, LimitExceeded)
      }
      b.text -= bytes
      body.domain = Some(domain)
      body.index = 0
    }
    None => body.index = -1
  }
}

///|
pub fn take_literal_domains_read(
  read : LiteralDomainsRead,
) -> Result[LiteralTransfer, Issue]? {
  let result = match read.state {
    Completed(transfer) => Ok(transfer)
    Rejected(_, issue) => Err(issue)
    _ => return None
  }
  read.state = Taken
  Some(result)
}

///|
/// Drops this read's roots only, never the borrowed original domain or Map.
pub fn clear_literal_domains_read(read : LiteralDomainsRead) -> Unit {
  read.state = Cleared
}
