///|
pub(all) struct TransferLimits {
  max_work : Int
  max_name_bytes : Int
}

///|
pub struct Transfer {
  key : KeyedRelation?
  work : Int
  name_bytes : Int
}

///|
priv struct TransferBudget {
  mut work : Int
  mut text : Int
}

///|
fn spend(
  b : TransferBudget,
  source : @decode.Cursor,
  amount : Int,
) -> Unit raise Stop {
  if amount > b.work {
    fail(source, LimitExceeded)
  }
  b.work -= amount
}

///|
fn charge(
  b : TransferBudget,
  source : @decode.Cursor,
  field : @row.FieldName,
) -> Unit raise Stop {
  let size = match
    @scalar.admit_utf8_length(@row.reference_name(field), b.text) {
    Ok(n) => n
    Err(_) => fail(source, LimitExceeded)
  }
  b.text -= size
}

///|
/// Single-witness convenience entry to the shared collection transfer.
pub fn transfer_unary(
  previous : KeyedRelation,
  operation : @relation.CheckedOperation,
  limits : TransferLimits,
) -> Result[Transfer, Issue] {
  let set : KeySet = {
    records: previous.records,
    witnesses: [previous],
    work: 0,
    name_bytes: 0,
  }
  match transfer_keys(set, operation, limits) {
    Err(e) => Err(e)
    Ok(t) =>
      Ok({
        key: t.keys.witnesses.get(0),
        work: t.work,
        name_bytes: t.name_bytes,
      })
  }
}
