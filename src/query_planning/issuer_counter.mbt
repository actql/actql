///|
// Serial allocation only, never authority or a shared issuer namespace. Each
// backend retains its own issuer counter; every issuer owns a fresh attempt
// counter. A reservation is consumed even if later preparation fails.
priv struct IssuerCounter {
  mut next : Int
}

///|
fn reserve_issuer_number(counter : IssuerCounter) -> Int? {
  if counter.next == 2147483647 {
    return None
  }
  let number = counter.next
  counter.next += 1
  Some(number)
}
