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
  mut material_nodes : Int?
  mut material_wire : String?
  mut material_ready : Bool
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
    material_nodes: None,
    material_wire: None,
    material_ready: false,
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
          nodes=Some(0),
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
/// Observe only allocation geometry of the SAME authenticated plaintext before
/// native JSON.parse or typed reconstruction. This is not JSON admission: all
/// original validators still consume the complete wire. Include punctuation
/// and escapes INSIDE strings to cover the embedded contract trees as well.
fn effect_capture_wire_nodes(wire : String) -> Int? {
  let mut nodes = 1L
  for index = 0; index < wire.length(); index = index + 1 {
    let code = wire[index].to_int()
    nodes += if code == 123 || code == 91 || code == 92 {
      2L
    } else if code == 58 || code == 44 {
      1L
    } else {
      0L
    }
    if nodes > 2147483647L {
      return None
    }
  }
  Some(nodes.to_int())
}

///|
/// Grow the original read reservation after AEAD and BEFORE constructing any
/// decoded tree. Bytes fund buffers/text; actual wire punctuation bounds nodes.
/// No cached authorization, replacement Ledger or caller-supplied count exists.
pub fn reserve_installed_effect_capture_decoded(
  owner : ClientInstalledEffectCaptureRecovery,
  wire : String,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if owner.transitioning || owner.closing || owner.fixed is None {
    return Err(Retired)
  }
  guard owner.material_bytes is Some(bytes) &&
    wire.length() <= bytes &&
    effect_capture_wire_nodes(wire) is Some(nodes) else {
    return Err(ForeignOriginal)
  }
  if owner.material_wire is Some(original) && original != wire {
    return Err(ForeignOriginal)
  }
  owner.material_nodes = Some(nodes)
  owner.material_wire = Some(wire)
  owner.material_ready = false
  owner.transitioning = true
  preparation_module_call(
    () => {
      match resize_installed_effect_capture_recovery_material(owner, false) {
        Err(issue) => Err(issue)
        Ok(_) => {
          owner.material_ready = true
          Ok(())
        }
      }
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
  if owner.material is Some(_) && !owner.material_ready {
    return Err(ForeignOriginal)
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
  let nodes = owner.material_nodes.unwrap_or(0)
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
      owner.material_bytes == Some(bytes) &&
      owner.material_nodes.unwrap_or(0) == nodes else {
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
      nodes=Some(nodes),
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
    // Store return. That return also cuts the envelope/ciphertext/plaintext
    // buffers and completed schema-writer bytes; failures never enter here.
    // Preserve the two returned tree inventories, all three decoded String
    // bounds (including the retained record wire), and schema/member owners.
    // No returned original borrows those four binary constructor buffers.
    guard @execution.execution_capacity_inventory_bytes([
        {
          unit: ValueNodeSlots,
          count: Int64::max(bytes.to_int64(), nodes.to_int64() * 3L) -
          nodes.to_int64() * 2L,
          copies: 1,
        },
        { unit: CanonicalWireBytes, count: bytes.to_int64(), copies: 4, },
      ])
      is Some(completed_material) else {
      return Err(InsufficientCapacity)
    }
    return @resources.complete_prepared_run_operation_construction_output(
      admission,
      plan,
      ledger,
      original,
      backing,
      retained - completed_material,
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
  owner.material_wire = None
  owner.material_nodes = None
  owner.material_ready = false
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
