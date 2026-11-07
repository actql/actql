///|
/// An original view of the existing platform VM reservation, not another Root,
/// allocator, physical-stop Owner or author-supplied capacity declaration.
struct PlatformVMCapacity {
  mut original : PlatformVMCapacity?
  ledger : Ledger
  capacity : SharedCapacity
  nonce : Int64
  observe : (Int64, Int) -> Int64
  mut closing : Bool
  mut failure : ImportedChildLedgerIssue?
}

///|
fn bind_platform_vm_capacity_original(
  nonce : Int64,
  ledger : Ledger,
  capacity : SharedCapacity,
  observe : (Int64, Int) -> Int64,
) -> Result[PlatformVMCapacity, ImportedChildLedgerIssue] {
  if nonce <= 0L ||
    ledger.imported_child is Some(_) ||
    !shared_capacity_matches_ledger(capacity, ledger) {
    return Err(ForeignOriginal)
  }
  match observe(nonce, 0) {
    0L => ()
    -41L => return Err(Unknown)
    _ => return Err(Unavailable)
  }
  let observed = observe(nonce, 1)
  if observed == -41L {
    return Err(Unknown)
  }
  if observed < 0L {
    return Err(Unavailable)
  }
  if observed == 0L ||
    observed != capacity.capacity ||
    !shared_capacity_matches_ledger(capacity, ledger) {
    return Err(InvalidOriginal)
  }
  let original : PlatformVMCapacity = {
    original: None,
    ledger,
    capacity,
    nonce,
    observe,
    closing: false,
    failure: None,
  }
  original.original = Some(original)
  Ok(original)
}

///|
/// Fixed trusted Host observation only. Neither equal Root limits nor the
/// observed byte amount supplies this association. No callback enters here.
pub fn bind_platform_vm_capacity(
  nonce : Int64,
  ledger : Ledger,
  capacity : SharedCapacity,
) -> Result[PlatformVMCapacity, ImportedChildLedgerIssue] {
  let observe = match platform_vm_port() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  bind_platform_vm_capacity_original(nonce, ledger, capacity, observe)
}

///|
/// Require the same live Instance capacity before a new suballocation. This
/// does not acknowledge cleanup, move bytes or turn VM bounds into permission.
pub fn require_platform_vm_capacity(
  original : PlatformVMCapacity,
  ledger : Ledger,
  capacity : SharedCapacity,
) -> Result[Unit, ImportedChildLedgerIssue] {
  guard original.original is Some(selected) &&
    physical_equal(original, selected) &&
    physical_equal(original.ledger, ledger) &&
    physical_equal(original.capacity, capacity) else {
    return Err(ForeignOriginal)
  }
  if original.failure is Some(issue) {
    return Err(issue)
  }
  if original.closing {
    return Err(Unavailable)
  }
  match (original.observe)(original.nonce, 0) {
    0L => ()
    1L => {
      original.closing = true
      return Err(Unavailable)
    }
    -41L => {
      original.failure = Some(Unknown)
      return Err(Unknown)
    }
    _ => {
      original.failure = Some(Unavailable)
      return Err(Unavailable)
    }
  }
  // A synchronous observation cannot restore a retired or replaced original.
  if original.failure is Some(issue) {
    return Err(issue)
  }
  if original.closing || !shared_capacity_matches_ledger(capacity, ledger) {
    return Err(Unavailable)
  }
  Ok(())
}
