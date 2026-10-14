///|
// Type erasure stays inside Resource. Only the original admission and its
// actual opaque installation are captured; ModelProvider DATA is not an issuer.
// These records/closures are additional funded holdings, not byte-free tickets.
pub struct ModelIoAccess {
  priv mut leases : Array[ModelIoLease]?
  priv mut claim : ((ModelIoAccess, Ledger, Reservation, Int, Int) -> Result[
    ModelIoLease,
    ModelIoAdmissionIssue,
  ])?
  priv mut close : (() -> Result[Bool, ModelIoAdmissionIssue])?
}

///|
pub struct ModelIoLease {
  priv mut access : ModelIoAccess?
  priv mut settle_io : ((Ledger, Reservation, Int, Int) -> Result[
    Unit,
    ModelIoAdmissionIssue,
  ])?
  priv mut settle_holding : ((Ledger, Reservation, Int, Int) -> Result[
    Unit,
    ModelIoAdmissionIssue,
  ])?
}

///|
// The trusted Host installer shares this exact instance across its Runs.
// No origin getter, Node bare factory, wire reader or reconstructed grant exists.
pub fn[T] issue_model_io_access(
  original : ModelIoAdmission[T],
  installation : T,
) -> Result[ModelIoAccess, ModelIoAdmissionIssue] {
  if !model_io_installation_matches(original, installation) {
    return Err(ForeignInstallation)
  }
  if original.closing {
    return Err(AdmissionClosing)
  }
  if original.access_issued {
    return Err(DuplicateAccess)
  }
  original.access_issued = true
  Ok({
    leases: Some([]),
    claim: Some((access, ledger, reservation, slot, attempt) => {
      claim_model_io_for_owned_ledger(
        original, installation, ledger, reservation, slot, attempt,
      ).map(ticket => {
        access: Some(access),
        settle_io: Some((ledger, claimed, slot, attempt) => {
          if ticket.reservation is Some(bound) && physical_equal(bound, claimed) {
            settle_model_io_for_owned_ledger_after_owner_ack(
              original, installation, ledger, ticket, slot, attempt,
            )
          } else {
            Err(ForeignTicket)
          }
        }),
        settle_holding: Some((ledger, claimed, slot, attempt) => {
          if ticket.reservation is Some(bound) && physical_equal(bound, claimed) {
            settle_model_holding_for_owned_ledger_after_owner_ack(
              original, installation, ledger, ticket, slot, attempt,
            )
          } else {
            Err(ForeignTicket)
          }
        }),
      })
    }),
    close: Some(() => close_model_io_admission(original, installation)),
  })
}

///|
pub fn claim_model_io_access(
  access : ModelIoAccess,
  ledger : Ledger,
  reservation : Reservation,
  slot : Int,
  attempt : Int,
) -> Result[ModelIoLease, ModelIoAdmissionIssue] {
  guard access.claim is Some(claim) else { return Err(AdmissionClosing) }
  guard access.leases is Some(leases) else { return Err(AdmissionClosing) }
  claim(access, ledger, reservation, slot, attempt).map(lease => {
    leases.push(lease)
    lease
  })
}

///|
pub fn settle_model_io_lease_after_owner_ack(
  access : ModelIoAccess,
  lease : ModelIoLease,
  ledger : Ledger,
  reservation : Reservation,
  slot : Int,
  attempt : Int,
) -> Result[Unit, ModelIoAdmissionIssue] {
  guard lease.access is Some(original) else { return Err(TicketRetired) }
  if !physical_equal(access, original) {
    return Err(ForeignTicket)
  }
  guard access.leases is Some(leases) &&
    leases.any(original => physical_equal(original, lease)) else {
    return Err(ForeignTicket)
  }
  guard lease.settle_io is Some(settle) else { return Err(TicketRetired) }
  settle(ledger, reservation, slot, attempt)
}

///|
pub fn settle_model_io_lease_holding_after_owner_ack(
  access : ModelIoAccess,
  lease : ModelIoLease,
  ledger : Ledger,
  reservation : Reservation,
  slot : Int,
  attempt : Int,
) -> Result[Unit, ModelIoAdmissionIssue] {
  guard lease.access is Some(original) else { return Err(TicketRetired) }
  if !physical_equal(access, original) {
    return Err(ForeignTicket)
  }
  guard access.leases is Some(leases) &&
    leases.any(original => physical_equal(original, lease)) else {
    return Err(ForeignTicket)
  }
  guard lease.settle_holding is Some(settle) else { return Err(TicketRetired) }
  match settle(ledger, reservation, slot, attempt) {
    Err(issue) => Err(issue)
    Ok(_) => {
      let mut index = 0
      while !physical_equal(leases[index], lease) {
        index += 1
      }
      let last = leases.pop().unwrap()
      if index < leases.length() {
        leases[index] = last
      }
      // Only full holding retirement severs the escaped lease's closures.
      lease.settle_io = None
      lease.settle_holding = None
      lease.access = None
      Ok(())
    }
  }
}

///|
pub fn close_model_io_access(
  access : ModelIoAccess,
) -> Result[Bool, ModelIoAdmissionIssue] {
  guard access.close is Some(close) else { return Ok(true) }
  match close() {
    Ok(true) => {
      access.claim = None
      access.close = None
      access.leases = None
      Ok(true)
    }
    result => result
  }
}
