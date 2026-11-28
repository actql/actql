///|
// The complete-group count comes from the private retained Source set. This
// grows the existing control before Host DTO arrays, indexes or roots exist.
pub fn reserve_installed_effect_dependency_group(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  entries : Int,
  roots : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_inputs is Some(inputs) &&
    owner.source_free_captured is Some(captured) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    control.dependency_group is Some(_) ||
    control.dependency_inventory is Some(_) ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    !@strategy.captured_effect_inputs_match_captured_run(inputs, captured) ||
    entries < 0 ||
    roots < 0 ||
    entries > 2147483647 - roots {
    return Err(ForeignOriginal)
  }
  guard installed_effect_dependency_fixed_capacity(entries + roots, 0, 64)
    is Some(fixed) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, fixed,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  control.dependency_group = Some((entries, roots))
  Ok(())
}

///|
// Repeated member occurrences still pass their original custody checks. A
// nominal Artifact alias needs no second body quote or construction.
fn installed_effect_dependency_repeats_root(
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  index : Int,
  work : (Int) -> Bool,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  let artifact = artifacts[index]
  for previous in 0..<index {
    if !work(1) {
      return Err(InsufficientCapacity)
    }
    if physical_equal(artifacts[previous], artifact) {
      return Ok(true)
    }
  }
  Ok(false)
}

///|
// The same nominal Run and source generation receive every body/root. The
// cache only shares immutable DATA after exact-wire comparison; physical
// Source/Result owners and all imported edges remain separate obligations.
pub fn prepare_installed_effect_dependency_inventory(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  kinds : Array[String],
  identities : Array[String?],
  wires : Array[String],
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  original_artifacts? : Array[@publication_host.ClientEffectLocalResultArtifact] = [],
) -> Result[String, ClientInstalledManagedRunIssue] {
  prepare_installed_effect_dependency_inventory_retained(
    owner,
    prepared,
    request,
    expected_plan,
    kinds,
    identities,
    wires,
    artifacts,
    max_bytes,
    max_nodes,
    max_depth,
    original_artifacts~,
  ).map(@publication.captured_effect_dependency_inventory_json)
}

///|
/// The Native caller already holds the nominal Run. Return that same funded
/// inventory for the captured-run issuer without decoding another copy.
pub fn prepare_installed_effect_dependency_inventory_retained(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  kinds : Array[String],
  identities : Array[String?],
  wires : Array[String],
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  original_artifacts? : Array[@publication_host.ClientEffectLocalResultArtifact] = [],
) -> Result[
  @publication.CapturedEffectDependencyInventory,
  ClientInstalledManagedRunIssue,
] {
  let result = prepare_installed_effect_dependency_inventory_original(
    owner,
    prepared,
    request,
    expected_plan,
    kinds,
    identities,
    wires,
    artifacts,
    max_bytes,
    max_nodes,
    max_depth,
    original_artifacts~,
  )
  match result {
    Err(issue) => Err(issue)
    Ok(value) =>
      match
        complete_installed_effect_dependency_construction(
          owner, prepared, request, expected_plan,
        ) {
        Err(issue) => Err(issue)
        Ok(_) => Ok(value)
      }
  }
}

///|
fn prepare_installed_effect_dependency_inventory_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  kinds : Array[String],
  identities : Array[String?],
  wires : Array[String],
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  original_artifacts? : Array[@publication_host.ClientEffectLocalResultArtifact] = [],
) -> Result[
  @publication.CapturedEffectDependencyInventory,
  ClientInstalledManagedRunIssue,
] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_inputs is Some(inputs) &&
    owner.source_free_captured is Some(captured) &&
    owner.publication_definition is Some(definition) &&
    owner.publication_invocation is Some(_) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    !(match control.dependency_group {
      Some((entries, roots)) =>
        wires.length() <= entries &&
        artifacts.length() == roots &&
        original_artifacts.length() <= entries
      None => false
    }) ||
    control.dependency_inventory is Some(_) ||
    kinds.length() != wires.length() ||
    identities.length() != wires.length() ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    !@strategy.captured_effect_inputs_match_captured_run(inputs, captured) ||
    !@strategy.captured_effect_inputs_retained(inputs) ||
    max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_depth > 64 {
    return Err(ForeignOriginal)
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let segment = fn(
    task : ((Int) -> Bool) -> Result[
      ClientEffectDependencyGroupStep,
      ClientInstalledManagedRunIssue,
    ],
  ) -> Result[ClientEffectDependencyGroupStep, ClientInstalledManagedRunIssue] {
    match
      with_installed_effect_dependency_work(
        control,
        admission,
        plan,
        ledger,
        () => {
          check_installed_effect_operation_original(
            owner,
            ledger,
            preparation,
            Some(control),
          )
        },
        control.reservation,
        () => {
          owner.effect_operation_opening &&
          !owner.effect_operation_closing &&
          @strategy.captured_effect_inputs_match_captured_run(inputs, captured)
        },
        spend => {
          task(units => {
            match spend(units) {
              Ok(_) => true
              Err(issue) => {
                refused.val = Some(issue)
                false
              }
            }
          }).map_err(issue => {
            @resources.NodeManagedRunOperationIssue::Original(issue)
          })
        },
      ) {
      Ok(value) => Ok(value)
      Err(issue) =>
        Err(
          match refused.val {
            Some(issue) => Ledger(issue)
            None => installed_effect_operation_reservation_issue(issue)
          },
        )
    }
  }
  // Each grow is between synchronous Work segments. Only their quoted
  // survivors cross that boundary, including Catalog census and body owners.
  let grow = fn(
    required : @execution.ExecutionCapacity,
  ) -> Result[Unit, ClientInstalledManagedRunIssue] {
    retain_installed_effect_dependency_capacity(
      owner,
      preparation,
      admission,
      plan,
      ledger,
      control,
      required,
      previous_workspace_retired=true,
    )
  }
  // Artifact wire usage comes from its exact original final encoder. Root
  // parsing gets a separate measured extent before the existing classifier.
  let roots_capacity = match
    segment(work => {
      // Upstream exports are not final roots. Their nominal custody binds a
      // canonical Relation emission to this SAME captured Run before its wire can
      // use the original encoder's size instead of the untrusted spelling bound.
      for artifact in original_artifacts {
        if !work(1) {
          return Err(InsufficientCapacity)
        }
        if !@publication_host.client_effect_local_artifact_matches_inputs(
            artifact, inputs,
          ) ||
          !@publication_host.client_effect_local_artifact_matches_computation(
            artifact, prepared,
          ) ||
          @publication_host.client_effect_local_artifact_run_definition_cid(
            artifact,
          ) !=
          Some(@publication.publication_contract_identity(definition)) {
          return Err(ForeignOriginal)
        }
      }
      // The later catalog_original argument owns tuple1H2R + Some1H1R1W.
      // Include it in this existing pre-entry grow, even with no Artifact
      // roots; the Catalog helper's own fixed-control grow occurs too late.
      let mut roots_capacity = @execution.preparation_execution_capacity({
        retained: {
          record_headers: 2L,
          reference_slots: 3L,
          scalar_words: 1L,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        },
        workspace: {
          record_headers: 0L,
          reference_slots: 0L,
          scalar_words: 0L,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        },
        retained_nodes: 0L,
        workspace_nodes: 0L,
        retained_bytes: 0L,
        workspace_bytes: 0L,
      }).unwrap()
      for index, artifact in artifacts {
        if !work(1) {
          return Err(InsufficientCapacity)
        }
        if !@publication_host.client_effect_local_artifact_matches_inputs(
            artifact, inputs,
          ) ||
          !@publication_host.client_effect_local_artifact_matches_computation(
            artifact, prepared,
          ) ||
          @publication_host.client_effect_local_artifact_run_definition_cid(
            artifact,
          ) !=
          Some(@publication.publication_contract_identity(definition)) {
          return Err(ForeignOriginal)
        }
        match installed_effect_dependency_repeats_root(artifacts, index, work) {
          Ok(true) => continue
          Ok(false) => ()
          Err(issue) => return Err(issue)
        }
        let contract = @publication_host.client_effect_local_result_artifact_contract(
          artifact,
        )
        guard @publication.publication_contract_wire_usage(contract)
          is Some((bytes, nodes, depth)) &&
          bytes <= max_bytes &&
          nodes <= max_nodes &&
          depth <= max_depth else {
          return Err(Unsupported)
        }
        guard installed_effect_dependency_body_capacity({
            bytes,
            nodes,
            depth,
            arrays: 0,
            objects: nodes,
            fields: nodes - 1,
            largest_object: nodes - 1,
            strings: nodes,
            text_units: bytes,
          })
          is Some(capacity) &&
          standard_create_sum_capacities(
            [roots_capacity, capacity],
            sequential_workspace=true,
          )
          is Some(next) else {
          return Err(InsufficientCapacity)
        }
        roots_capacity = next
      }
      Ok(Capacity(roots_capacity))
    }) {
    Ok(Capacity(value)) => value
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  match grow(roots_capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let roots = match
    segment(work => {
      let roots : Array[@publication.CapturedEffectDependencyBody] = []
      for index, artifact in artifacts {
        match installed_effect_dependency_repeats_root(artifacts, index, work) {
          Ok(true) => continue
          Ok(false) => ()
          Err(issue) => return Err(issue)
        }
        let wire = @publication_host.client_effect_local_result_artifact_json(
          artifact,
        )
        for _ in 0..<6 {
          if !work(wire.length()) {
            return Err(InsufficientCapacity)
          }
        }
        match
          @publication_host.client_effect_local_artifact_dependency_root(
            artifact, max_bytes, max_nodes, max_depth,
          ) {
          Ok(root) => {
            // Distinct Artifact originals still need the exact wire check
            // when their roots name the same semantic body.
            let kind = @publication.captured_effect_dependency_body_kind(root)
            let cid = @publication.captured_effect_dependency_body_cid(root)
            let mut duplicate = false
            for previous in roots {
              let previous_kind = @publication.captured_effect_dependency_body_kind(
                previous,
              )
              let previous_cid = @publication.captured_effect_dependency_body_cid(
                previous,
              )
              // These admitted kind/CID spellings are bounded contract keys.
              // Borrow the already funded array; allocate no index or key.
              if !work(
                  1 +
                  kind.length() +
                  previous_kind.length() +
                  cid.length() +
                  previous_cid.length(),
                ) {
                return Err(InsufficientCapacity)
              }
              if kind == previous_kind && cid == previous_cid {
                let previous_wire = @publication.captured_effect_dependency_body_json(
                  previous,
                )
                if !work(wire.length()) || !work(previous_wire.length()) {
                  return Err(InsufficientCapacity)
                }
                if wire != previous_wire {
                  return Err(ForeignOriginal)
                }
                duplicate = true
                break
              }
            }
            if !duplicate {
              roots.push(root)
            }
          }
          Err(_) => return Err(Unsupported)
        }
      }
      Ok(Bodies(roots))
    }) {
    Ok(Bodies(roots)) => roots
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  let (inventory, geometry) = match
    prepare_funded_effect_dependency_inventory(
      kinds,
      identities,
      wires,
      roots,
      Some(control.dependency_static),
      max_bytes,
      max_nodes,
      max_depth,
      grow,
      segment,
      original_artifacts=Some(original_artifacts),
      catalog_original=Some(
        (
          @checked.effect_program_static_checked_computation(
            @publication_host.prepared_client_effect_computation_candidate(
              prepared,
            ),
          ),
          control,
        ),
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Retain the actual semantic owner for fresh CapturedRun preflight. A wire
  // or a callback's presence cannot manufacture this original association.
  control.dependency_inventory = Some(inventory)
  control.dependency_inventory_geometry = Some(geometry)
  Ok(inventory)
}
