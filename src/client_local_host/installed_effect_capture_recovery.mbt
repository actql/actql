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
          // A previous successful Store return may have disposed scratch.
          // Re-enter only after this SAME token funds the same original peak.
          resize_installed_effect_capture_recovery_material(owner, false)
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
/// The trusted Store consumer has returned after its original FD close and
/// transient plaintext/cursor aliases and full parsed container were cut.
/// Keep every returned typed/schema/wire output on this SAME token.
pub fn complete_installed_effect_capture_recovery(
  owner : ClientInstalledEffectCaptureRecovery,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if owner.transitioning || owner.closing || owner.fixed is None {
    return Err(Retired)
  }
  owner.transitioning = true
  preparation_module_call(
    () => resize_installed_effect_capture_recovery_material(owner, true),
    () => owner.transitioning = false,
  )
}

///|
// Both entrances reuse the original adopted Plan and byte-only backing. The
// private Bool selects completion versus a later SAME-extent read, not an ACK
// or externally supplied capacity. No new reservation/attempt/history exists.
fn resize_installed_effect_capture_recovery_material(
  owner : ClientInstalledEffectCaptureRecovery,
  completed : Bool,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard !owner.closing &&
    owner.transitioning &&
    owner.parent is Some(parent) &&
    owner.prepared is Some(prepared) &&
    owner.request is Some(request) &&
    owner.definition is Some(definition) &&
    owner.ledger is Some(ledger) &&
    owner.fixed is Some(fixed) &&
    parent.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(parent, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.material is Some(material) && owner.material_bytes is Some(bytes) else {
    return check_installed_effect_managed_run(parent, prepared, request)
  }
  let original : () -> Result[Unit, ClientInstalledManagedRunIssue] = () => {
    guard !owner.closing &&
      owner.transitioning &&
      owner.parent is Some(p) &&
      physical_equal(p, parent) &&
      owner.prepared is Some(p) &&
      physical_equal(p, prepared) &&
      owner.request is Some(r) &&
      physical_equal(r, request) &&
      owner.definition is Some(d) &&
      physical_equal(d, definition) &&
      owner.ledger is Some(l) &&
      physical_equal(l, ledger) &&
      owner.fixed is Some(f) &&
      physical_equal(f, fixed) &&
      owner.material is Some(m) &&
      physical_equal(m, material) &&
      owner.material_bytes == Some(bytes) else {
      return Err(Retired)
    }
    check_installed_managed_run_original(parent, ledger, preparation).map(_ => {
      ()
    })
  }
  let backing = @resources.NodeManagedRunOperationBacking::Construction(
    material,
  )
  guard request_effect_capture_recovery_capacity(
      bytes,
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
  let retained = @execution.execution_capacity_retained_bytes(required) -
    @execution.execution_capacity_retained_bytes(base)
  let execution = @execution.execution_capacity_execution_bytes(required) -
    @execution.execution_capacity_execution_bytes(base)
  if completed {
    // The full parsed capture container no longer exists after the trusted
    // Store return. Preserve the other two tree inventories, every original
    // decoded string/wire bound and all returned schema/member owners. This
    // is one completed constructor role, not a measured byte/cleanup claim.
    guard @execution.execution_capacity_inventory_bytes([
        { unit: ValueNodeSlots, count: bytes.to_int64(), copies: 1, },
      ])
      is Some(container) else {
      return Err(InsufficientCapacity)
    }
    return @resources.complete_prepared_run_operation_construction_output(
      admission, plan, ledger, original, backing, retained - container,
    ).map_err(installed_effect_operation_reservation_issue)
  }
  if @resources.capacity_reservation_covers(
      ledger, material, retained, execution,
    ) {
    return original()
  }
  @resources.grow_prepared_run_operation_capacity(
    admission, plan, ledger, original, backing, retained, execution,
  ).map_err(installed_effect_operation_reservation_issue)
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
