///|
/// The recovery child uses its SAME parent's retained PublicationProof receipt.
/// The encrypted entrance prepares that phase for cold parents too; the legacy
/// generic entrance keeps its original full-envelope quote.
pub fn reserve_installed_effect_capture_envelope(
  owner : ClientInstalledEffectCaptureRecovery,
  wire : String,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if owner.transitioning || owner.closing || owner.fixed is None {
    return Err(Retired)
  }
  if !owner.material_staged_envelope {
    return Ok(())
  }
  guard owner.material_bytes is Some(bytes) &&
    wire.length() <= bytes &&
    owner.material is Some(material) &&
    owner.parent is Some(parent) &&
    owner.prepared is Some(prepared) &&
    owner.request is Some(request) &&
    owner.ledger is Some(ledger) &&
    parent.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    parent.effect_operation_controls is Some(control) &&
    control.dependency_work is Some(_) else {
    return Err(ForeignOriginal)
  }
  if owner.material_envelope_wire is Some(original) && original != wire {
    return Err(ForeignOriginal)
  }
  owner.transitioning = true
  preparation_module_call(
    () => {
      if owner.material_envelope_nodes is None {
        owner.material_envelope_wire = Some(wire)
        let geometry = match
          with_installed_effect_dependency_work(
            control,
            admission,
            plan,
            ledger,
            () => {
              match
                check_installed_effect_managed_run_binding(
                  parent, prepared, request,
                ) {
                Err(issue) => return Err(issue)
                Ok(_) => ()
              }
              check_installed_managed_run_original(parent, ledger, preparation).map(_ => {
                  ()
                },
              )
            },
            material,
            () => {
              owner.transitioning &&
              !owner.closing &&
              owner.parent is Some(same) &&
              physical_equal(same, parent) &&
              owner.material is Some(same) &&
              physical_equal(same, material)
            },
            spend => {
              let refused : Ref[@resources.LedgerIssue?] = Ref(None)
              let geometry = installed_effect_dependency_wire_geometry(
                wire,
                bytes,
                owner.max_nodes,
                owner.max_depth,
                units => {
                  match spend(units) {
                    Ok(_) => true
                    Err(issue) => {
                      refused.val = Some(issue)
                      false
                    }
                  }
                },
              )
              match geometry {
                Some(value) => Ok(value)
                None =>
                  Err(
                    @resources.NodeManagedRunOperationIssue::Original(
                      match refused.val {
                        Some(issue) => Ledger(issue)
                        None => Unsupported
                      },
                    ),
                  )
              }
            },
          ) {
          Err(issue) =>
            return Err(installed_effect_operation_reservation_issue(issue))
          Ok(value) => value
        }
        owner.material_envelope_wire = Some(wire)
        owner.material_envelope_nodes = Some(geometry.node_upper)
      }
      resize_installed_effect_capture_recovery_material(owner, false)
    },
    () => owner.transitioning = false,
  )
}

///|
fn observe_installed_effect_capture_plaintext_nodes(
  owner : ClientInstalledEffectCaptureRecovery,
  wire : String,
) -> Result[Int, ClientInstalledManagedRunIssue] {
  guard owner.transitioning &&
    !owner.closing &&
    owner.material is Some(material) &&
    owner.material_bytes is Some(bytes) &&
    owner.parent is Some(parent) &&
    owner.prepared is Some(prepared) &&
    owner.request is Some(request) &&
    owner.ledger is Some(ledger) &&
    parent.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    parent.effect_operation_controls is Some(control) else {
    return Err(ForeignOriginal)
  }
  with_installed_effect_dependency_work(
    control,
    admission,
    plan,
    ledger,
    () => {
      match
        check_installed_effect_managed_run_binding(parent, prepared, request) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      check_installed_managed_run_original(parent, ledger, preparation).map(_ => {
        ()
      })
    },
    material,
    () => {
      owner.transitioning &&
      !owner.closing &&
      owner.material is Some(same) &&
      physical_equal(same, material)
    },
    spend => {
      match spend(wire.length()) {
        Err(issue) =>
          return Err(@resources.NodeManagedRunOperationIssue::Control(issue))
        Ok(_) => ()
      }
      // Common performs its SAME actual UTF8 selection once per read call.
      // Charge that scan on every invocation, while the immutable owner
      // geometry below is observed only once for this exact wire.
      if owner.material_wire == Some(wire) &&
        owner.material_nodes is Some(nodes) &&
        owner.material_plaintext_bytes is Some(_) {
        return Ok(nodes)
      }
      // The remaining scans observe exact UTF8 and nested-node geometry.
      match spend(wire.length()) {
        Err(issue) =>
          return Err(@resources.NodeManagedRunOperationIssue::Control(issue))
        Ok(_) => ()
      }
      match spend(wire.length()) {
        Err(issue) =>
          return Err(@resources.NodeManagedRunOperationIssue::Control(issue))
        Ok(_) => ()
      }
      let plaintext_bytes = match @scalar.admit_utf8_length(wire, bytes) {
        Err(_) =>
          return Err(
            @resources.NodeManagedRunOperationIssue::Original(Unsupported),
          )
        Ok(value) => value
      }
      owner.material_plaintext_bytes = Some(plaintext_bytes)
      match effect_capture_wire_nodes(wire) {
        Some(nodes) => Ok(nodes)
        None =>
          Err(@resources.NodeManagedRunOperationIssue::Original(Unsupported))
      }
    },
  ).map_err(installed_effect_operation_reservation_issue)
}

///|
pub fn installed_effect_capture_prepared_available(
  owner : ClientInstalledEffectCaptureRecovery,
) -> Bool {
  owner.material_staged_envelope &&
  owner.material_plaintext_bytes is Some(_) &&
  owner.material_ready &&
  !owner.closing &&
  !owner.transitioning &&
  owner.parent is Some(parent) &&
  parent.effect_operation_controls is Some(control) &&
  control.dependency_work is Some(_)
}

///|
/// SAME live Read and SAME original complete inventory. Exact saved wire and
/// Definition correspondence precede semantic reuse; mutable current remains
/// a fresh Resource fence. The returned DATA grants no physical permission.
pub fn admit_installed_effect_captured_run(
  owner : ClientInstalledEffectCaptureRecovery,
  captured_wire : String,
) -> Result[
  @publication.PreparedCapturedEffectRun,
  ClientInstalledManagedRunIssue,
] {
  guard installed_effect_capture_prepared_available(owner) &&
    owner.material is Some(material) &&
    owner.material_wire is Some(wire) &&
    owner.material_nodes is Some(nodes) &&
    owner.material_bytes is Some(encrypted_bytes) &&
    owner.parent is Some(parent) &&
    owner.definition is Some(definition) &&
    owner.prepared is Some(prepared) &&
    owner.request is Some(request) &&
    owner.ledger is Some(ledger) &&
    parent.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    parent.effect_operation_controls is Some(control) else {
    return Err(ForeignOriginal)
  }
  let bytes = owner.material_plaintext_bytes.unwrap_or(encrypted_bytes)
  owner.transitioning = true
  preparation_module_call(
    () => {
      match resize_installed_effect_capture_recovery_material(owner, false) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      if owner.material_captured is Some(original) {
        return if @publication.publication_contract_json(
            @publication.prepared_captured_effect_run_contract(original),
          ) ==
          captured_wire {
          Ok(original)
        } else {
          Err(ForeignOriginal)
        }
      }
      let value = match
        with_installed_effect_dependency_work(
          control,
          admission,
          plan,
          ledger,
          () => {
            match
              check_installed_effect_managed_run_binding(
                parent, prepared, request,
              ) {
              Err(issue) => return Err(issue)
              Ok(_) => ()
            }
            check_installed_managed_run_original(parent, ledger, preparation).map(_ => {
                ()
              },
            )
          },
          material,
          () => {
            owner.transitioning &&
            !owner.closing &&
            owner.material is Some(same) &&
            physical_equal(same, material)
          },
          spend => {
            for _ in 0..<6 {
              match spend(wire.length()) {
                Err(issue) =>
                  return Err(
                    @resources.NodeManagedRunOperationIssue::Control(issue),
                  )
                Ok(_) => ()
              }
            }
            let node = match
              @source.parse_json(wire, {
                max_input_bytes: bytes,
                max_nodes: nodes,
                max_depth: owner.max_depth,
              }) {
              Err(_) =>
                return Err(
                  @resources.NodeManagedRunOperationIssue::Original(Unsupported),
                )
              Ok(value) => value
            }
            let record = @identity.from_source(
              node,
              nodes,
              owner.max_depth,
              bytes,
              data_keys=true,
            ) catch {
              _ =>
                return Err(
                  @resources.NodeManagedRunOperationIssue::Original(Unsupported),
                )
            }
            guard @identity.object_field(record, "run_definition")
              is Some(@identity.String(run_wire)) &&
              run_wire == @publication.publication_contract_json(definition) &&
              @identity.object_field(record, "captured_run")
              is Some(@identity.String(original_wire)) &&
              original_wire == captured_wire else {
              return Err(
                @resources.NodeManagedRunOperationIssue::Original(
                  ForeignOriginal,
                ),
              )
            }
            let captured = match
              @publication.admit_publication_contract(
                "captured_run",
                original_wire,
                bytes,
                nodes,
                owner.max_depth,
              ) {
              Err(_) =>
                return Err(
                  @resources.NodeManagedRunOperationIssue::Original(Unsupported),
                )
              Ok(value) => value
            }
            match control.dependency_inventory {
              Some(inventory) =>
                @publication.bind_prepared_captured_effect_run(
                  captured, inventory,
                ).map_err(_ => {
                  @resources.NodeManagedRunOperationIssue::Original(Unsupported)
                })
              None => {
                // A different process owns no prior typed inventory. Admit the
                // complete closure under THIS authenticated Read's real extent,
                // never a metadata/row codec limit or a supplied inventory.
                let refused : Ref[@resources.LedgerIssue?] = Ref(None)
                let recovered = @publication.prepare_recovered_captured_effect_run(
                  captured,
                  bytes,
                  nodes,
                  owner.max_depth,
                  units => {
                    match spend(units) {
                      Ok(_) => true
                      Err(issue) => {
                        refused.val = Some(issue)
                        false
                      }
                    }
                  },
                )
                match recovered {
                  Ok(value) => Ok(value)
                  Err(_) =>
                    Err(
                      match refused.val {
                        Some(issue) =>
                          @resources.NodeManagedRunOperationIssue::Control(
                            issue,
                          )
                        None =>
                          @resources.NodeManagedRunOperationIssue::Original(
                            Unsupported,
                          )
                      },
                    )
                }
              }
            }
          },
        ) {
        Err(issue) =>
          return Err(installed_effect_operation_reservation_issue(issue))
        Ok(value) => value
      }
      owner.material_captured = Some(value)
      Ok(value)
    },
    () => owner.transitioning = false,
  )
}
