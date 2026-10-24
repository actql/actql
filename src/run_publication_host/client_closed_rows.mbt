///|
/// Original checked owner inventory, before generated task views are expanded.
/// This changes only the sequence row envelope; cells, expression work, bytes,
/// admission and Run resource capacities retain their independent enforcement.
fn client_closed_owner_rows(owners : Array[@lower.BoundPrepared],max_work : Int) -> Int? {
  if owners.is_empty() || owners.length()>max_work {return None}
  let mut remaining=max_work-owners.length()
  let mut maximum=0
  for owner in owners {
    guard @lower.prepared_closed_row_bound(@lower.bound_preparation(owner),remaining) is Some((rows,used)) else {return None}
    remaining-=used
    maximum=Int::max(maximum,rows)
  }
  Some(Int::max(1,maximum))
}
