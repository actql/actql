///|
/// Two ordinary byte reservations on the SAME adopted Effect Run. This
/// handle owns no Ledger, attempt allowance, mutation permission or new Root.
/// The fixed Host retains it before its first read/schema child and returns
/// it only after that original child cleanup, including failure, completes.
struct ClientInstalledEffectCaptureRecovery {
  mut parent : ClientInstalledManagedRun?
  mut prepared : @publication_host.PreparedClientEffectComputation?
  mut request : @publication_host.ClientRequestIdentity?
  mut definition : @publication.PublicationContract?
  mut ledger : @resources.Ledger?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut fixed : @resources.CapacityReservation?
  mut material : @resources.CapacityReservation?
  mut material_bytes : Int?
  mut transitioning : Bool
  mut closing : Bool
}

///|
pub fn prepare_installed_effect_capture_recovery(
  parent : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientInstalledEffectCaptureRecovery,
  ClientInstalledManagedRunIssue,
] {
  match check_installed_effect_managed_run(parent, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @publication.publication_contract_name(definition) == "run_definition" &&
    parent.ledger is Some(ledger) &&
    request_effect_capture_recovery_capacity(
      0,
      @publication.publication_contract_json(definition).length(),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(required) else {
    return Err(ForeignOriginal)
  }
  let fixed = match
    @resources.reserve_capacity(
      ledger,
      @execution.execution_capacity_retained_bytes(required),
      @execution.execution_capacity_execution_bytes(required),
    ) {
    Err(issue) => return Err(Ledger(issue))
    Ok(value) => value
  }
  Ok({
    parent: Some(parent),
    prepared: Some(prepared),
    request: Some(request),
    definition: Some(definition),
    ledger: Some(ledger),
    max_wire_bytes,
    max_nodes,
    max_depth,
    fixed: Some(fixed),
    material: None,
    material_bytes: None,
    transitioning: false,
    closing: false,
  })
}

///|
/// Exact selected encrypted extent, before the Store allocates ciphertext,
/// plaintext, String, JSON, typed values or schemas. Repeat of this SAME read
/// is idempotent; another extent cannot replace an in-flight original.
pub fn reserve_installed_effect_capture_recovery(
  owner : ClientInstalledEffectCaptureRecovery,
  encrypted_bytes : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if owner.transitioning || owner.closing || owner.fixed is None {
    return Err(Retired)
  }
  owner.transitioning = true
  preparation_module_call(
    () => {
      guard owner.parent is Some(parent) &&
        owner.prepared is Some(prepared) &&
        owner.request is Some(request) &&
        owner.definition is Some(definition) &&
        owner.ledger is Some(ledger) else {
        return Err(Retired)
      }
      match check_installed_effect_managed_run(parent, prepared, request) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      if owner.material_bytes is Some(bytes) {
        return if bytes == encrypted_bytes {
          Ok(())
        } else {
          Err(ForeignOriginal)
        }
      }
      guard request_effect_capture_recovery_capacity(
          encrypted_bytes,
          @publication.publication_contract_json(definition).length(),
          owner.max_wire_bytes,
          owner.max_nodes,
          owner.max_depth,
        )
        is Some(required) &&
        request_effect_capture_recovery_capacity(
          0,
          @publication.publication_contract_json(definition).length(),
          owner.max_wire_bytes,
          owner.max_nodes,
          owner.max_depth,
        )
        is Some(base) else {
        return Err(InsufficientCapacity)
      }
      let reserved = match
        @resources.reserve_capacity(
          ledger,
          @execution.execution_capacity_retained_bytes(required) -
          @execution.execution_capacity_retained_bytes(base),
          @execution.execution_capacity_execution_bytes(required) -
          @execution.execution_capacity_execution_bytes(base),
        ) {
        Err(issue) => return Err(Ledger(issue))
        Ok(value) => value
      }
      owner.material = Some(reserved)
      owner.material_bytes = Some(encrypted_bytes)
      Ok(())
    },
    () => owner.transitioning = false,
  )
}

///|
/// Called only by the same Host's original read/schema cleanup continuation.
/// A returned Bool from another child is not accepted as an ACK argument.
/// Parent cancellation/current failure permits disposal, never another read.
pub fn retire_installed_effect_capture_recovery(
  owner : ClientInstalledEffectCaptureRecovery,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if owner.transitioning {
    return Err(CleanupPending)
  }
  owner.closing = true
  // Physical children have stopped. Cut the original payload aliases BEFORE
  // any reservation return can report, reenter, consume or decline settlement.
  owner.parent = None
  owner.prepared = None
  owner.request = None
  owner.definition = None
  owner.transitioning = true
  preparation_module_call(
    () => {
      guard owner.ledger is Some(ledger) else { return Ok(()) }
      if owner.material is Some(original) {
        if @resources.capacity_reservation_open(original) {
          match @resources.settle_capacity(ledger, original) {
            Err(issue) => return Err(Ledger(issue))
            Ok(_) => ()
          }
        }
        owner.material = None
      }
      if owner.fixed is Some(original) {
        if @resources.capacity_reservation_open(original) {
          match @resources.settle_capacity(ledger, original) {
            Err(issue) => return Err(Ledger(issue))
            Ok(_) => ()
          }
        }
        owner.fixed = None
      }
      owner.ledger = None
      Ok(())
    },
    () => owner.transitioning = false,
  )
}
