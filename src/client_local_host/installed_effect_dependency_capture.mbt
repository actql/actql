///|
// The planned issuer receives already admitted snapshots and dependency DATA.
// Its canonical material borrows those subtrees, then measures/hashes/emits the
// complete capture. Only optional plan wires still construct a parsed value.
// Quantities are taken from this exact plan/Preview/inventory inside the same
// scoped Work segment; they select no policy and issue no authority.
fn installed_effect_capture_constructor_capacity(
  plan : @publication.CapturedRunConstructionPlan,
  dependencies : Int,
  sources : Int,
  local_sources : Int,
  advances : Int,
  members : Int,
  generations : Int,
  plan_wires : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> @execution.ExecutionCapacity? {
  if dependencies < 0 ||
    sources < 0 ||
    local_sources < 0 ||
    advances < 0 ||
    members < 0 ||
    generations < 0 {
    return None
  }
  guard @publication.capture_construction_layout_facts(plan)
    is Some(
      (bytes, all_nodes, depth, nodes, results, fields, max_fields, models)
    ) &&
    publication_capture_constructor_layout(
      bytes,
      nodes,
      depth,
      results,
      fields,
      max_fields,
      models,
      row_key_nodes=all_nodes - nodes,
      effect_members=members,
    )
    is Some(layout) &&
    @execution.preparation_execution_capacity({
      retained: layout.retained,
      workspace: layout.temporary,
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(base) else {
    return None
  }
  let d = dependencies.to_int64()
  let s = sources.to_int64()
  let l = local_sources.to_int64()
  let a = advances.to_int64()
  let m = members.to_int64()
  let g = generations.to_int64()
  let p = plan_wires.length().to_int64()
  guard @shape.collection_construction_extent({
      // DI entry: Object/Frozen + three field tuples + cid/kind variants;
      // its body is borrowed. Effect member: empty Object/Frozen + map pair.
      // Source maps: artifact pair + holding pair/String; local pair only.
      // Logical plan: pair/String; admitted plan map: one pair.
      // Content generation: Object/Frozen + five borrowed-child field pairs.
      records: 7L * d + 5L * m + 3L * s + l + 4L * p + 7L * g + 4L,
      record_references: 10L * d +
      5L * m +
      5L * s +
      2L * l +
      7L * p +
      12L * g +
      8L,
      record_words: 3L * d + 3L * m + s + p + g + 8L,
      // DI outer/entry fields, Effect map, logical CID/plan maps,
      // Source maps and sorted Source copies, advance/generation arrays.
      reference_arrays: d + g + 12L,
      reference_items: 4L * d + 2L * m + 3L * s + 2L * l + a + 2L * p + 6L * g,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(metadata) &&
    @shape.collection_construction_extent({
      // Actual preview-member and seen-plan maps used while admitting plans.
      records: 4L,
      record_references: 8L,
      record_words: 4L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: m + p,
    })
    is Some(index) &&
    closed_values_sort_scratch_layout(
      Int::max(
        1,
        Int::max(sources, Int::max(local_sources, plan_wires.length())),
      ),
    )
    is Some(sort) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: metadata.record_headers,
        reference_slots: metadata.reference_slots,
        scalar_words: metadata.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: index.record_headers + sort.record_headers,
        reference_slots: index.reference_slots + sort.reference_slots,
        scalar_words: index.scalar_words + sort.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(wrappers) else {
    return None
  }
  let mut body = base
  for wire in plan_wires {
    guard installed_effect_dependency_wire_geometry(
        wire, max_bytes, max_nodes, max_depth, work,
      )
      is Some(geometry) &&
      installed_effect_dependency_wire_capacity(
        geometry, max_bytes, max_nodes, max_depth,
      )
      is Some(parsed) &&
      standard_create_sum_capacities([body, parsed], sequential_workspace=true)
      is Some(next) else {
      return None
    }
    // Parsed plan values coexist in the context. Each parser and the later
    // context/hash/text constructor run sequentially; their workspace is MAX.
    body = next
  }
  // The maps/sort/control workspace is conservatively coheld with that peak.
  // Existing snapshot/body/wire holdings remain on the original prefix.
  standard_create_sum_capacities([body, wrappers], sequential_workspace=false)
}

///|
// Same original definition/invocation must select the capture before Host
// maps or copied nominal inventories are constructed. Slots price only actual
// reference holders; they are neither entry authority nor a byte/count grant.
pub fn reserve_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  slots : Int,
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
    owner.publication_definition is Some(original_definition) &&
    owner.publication_invocation is Some(original_invocation) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    !physical_equal(definition, original_definition) ||
    !physical_equal(invocation, original_invocation) ||
    control.dependency_inventory is None ||
    control.dependency_capture_slots is Some(_) ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    slots < 0 {
    return Err(ForeignOriginal)
  }
  guard installed_effect_dependency_fixed_capacity(slots, 0, 64) is Some(fixed) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, fixed,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      control.dependency_capture_slots = Some(slots)
      Ok(())
    }
  }
}

///|
// The complete prepared semantic inventory is reused. All other original
// occurrences retain their independent nominal checks in the existing issuer.
pub fn begin_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  sources : Array[@publication.CapturedEffectSourceArtifact],
  local_sources : Array[@publication.CapturedLocalEffectSourceEvidence],
  advances : Array[@publication.PendingSourceStateAdvance],
  authoring : @publication.RunEvidenceValue,
  models : Array[@publication.RunEvidenceValue],
  preview : @publication.EffectPreviewIdentity,
  plan_names : Array[String],
  plan_wires : Array[String],
  dependency_wire : String,
  content_generations : Array[@publication.BoundContentGeneration],
  max_body_bytes : Int,
  max_body_nodes : Int,
  max_body_depth : Int,
) -> Result[
  @publication.CapturedRunIssuancePreparation,
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
    control.dependency_inventory is Some(inventory) &&
    control.dependency_inventory_geometry is Some(geometry) &&
    control.dependency_capture_slots is Some(reserved_slots) &&
    control.dependency_capture is None &&
    owner.publication_definition is Some(original_definition) &&
    owner.publication_invocation is Some(original_invocation) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let slots = definitions.length().to_int64() +
    artifacts.length().to_int64() +
    snapshots.length().to_int64() +
    sources.length().to_int64() +
    local_sources.length().to_int64() +
    advances.length().to_int64() +
    models.length().to_int64() +
    content_generations.length().to_int64() +
    2L * plan_names.length().to_int64()
  if !physical_equal(plan, expected_plan) ||
    !physical_equal(definition, original_definition) ||
    !physical_equal(invocation, original_invocation) ||
    slots > reserved_slots.to_int64() ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) {
    return Err(ForeignOriginal)
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let (capture_plan, capacity) = match
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
      () => owner.effect_operation_opening && !owner.effect_operation_closing,
      spend => {
        let work = fn(units : Int) -> Bool {
          match spend(units) {
            Ok(_) => true
            Err(issue) => {
              refused.val = Some(issue)
              false
            }
          }
        }
        if !work(dependency_wire.length()) ||
          dependency_wire !=
          @publication.captured_effect_dependency_inventory_json(inventory) {
          return Err(
            @resources.NodeManagedRunOperationIssue::Original(ForeignOriginal),
          )
        }
        match
          @publication.prepare_original_effectful_capture_plan(
            definition, invocation, definitions, artifacts, manifest, receipt, snapshots,
            sources, local_sources, advances, authoring, models, preview, plan_names,
            plan_wires, inventory, geometry, content_generations, max_body_bytes,
            max_body_nodes, max_body_depth, work,
          ) {
          Some(value) => {
            guard installed_effect_capture_constructor_capacity(
                value,
                @publication.captured_effect_dependency_inventory_count(
                  inventory,
                ),
                sources.length(),
                local_sources.length(),
                advances.length(),
                @publication.effect_preview_member_count(preview),
                content_generations.length(),
                plan_wires,
                max_body_bytes,
                max_body_nodes,
                max_body_depth,
                work,
              )
              is Some(capacity) else {
              @publication.cancel_capture_construction_plan(value)
              return Err(
                @resources.NodeManagedRunOperationIssue::Original(
                  InsufficientCapacity,
                ),
              )
            }
            Ok((value, capacity))
          }
          None =>
            Err(@resources.NodeManagedRunOperationIssue::Original(Unsupported))
        }
      },
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match refused.val {
          Some(issue) => Ledger(issue)
          None => installed_effect_operation_reservation_issue(issue)
        },
      )
  }
  // The size plan owns only already funded reference copies. If numeric grow
  // fails, cut those aliases while retaining the original failed prefix.
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, capacity,
    ) {
    Err(issue) => {
      @publication.cancel_capture_construction_plan(capture_plan)
      return Err(issue)
    }
    Ok(_) => ()
  }
  guard @publication.start_planned_captured_run(capture_plan) is Some(issuer) else {
    return Err(ForeignOriginal)
  }
  control.dependency_capture = Some(issuer)
  Ok(issuer)
}

///|
pub fn advance_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  issuer : @publication.CapturedRunIssuancePreparation,
  quantum : Int,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
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
    control.dependency_capture is Some(original_issuer) &&
    physical_equal(original_issuer, issuer) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) || quantum < 1 || quantum > 256 {
    return Err(ForeignOriginal)
  }
  if issuer.next_step_requires_reference_callback() {
    // Debit the actual scalar step while scoped, then close/return that view
    // BEFORE the existing reference-authorize callback can run or reenter.
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
        () => owner.effect_operation_opening && !owner.effect_operation_closing,
        spend => {
          spend(1).map_err(issue => {
            @resources.NodeManagedRunOperationIssue::Control(issue)
          })
        },
      ) {
      Err(issue) =>
        return Err(installed_effect_operation_reservation_issue(issue))
      Ok(_) => ()
    }
    let advanced = issuer.advance(1)
    // No Work cursor is live here. Recheck the SAME original after the actual
    // mutable callback; equality/metadata is not a cached authority decision.
    match require_installed_effect_operation_plan(owner, prepared, request) {
      Ok((current_plan, current_ledger)) if physical_equal(current_plan, plan) &&
        physical_equal(current_ledger, ledger) => ()
      Ok(_) => return Err(ForeignOriginal)
      Err(issue) => return Err(issue)
    }
    match
      check_installed_effect_operation_original(
        owner,
        ledger,
        preparation,
        Some(control),
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    return match advanced {
      Ok((done, _)) => Ok(done)
      Err(_) => Err(Unsupported)
    }
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let result = with_installed_effect_dependency_work(
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
    () => owner.effect_operation_opening && !owner.effect_operation_closing,
    spend => {
      match
        issuer.advance_with_work(quantum, units => {
          match spend(units) {
            Ok(_) => true
            Err(issue) => {
              refused.val = Some(issue)
              false
            }
          }
        }) {
        Ok((done, _)) => Ok(done)
        Err(_) =>
          Err(@resources.NodeManagedRunOperationIssue::Original(Unsupported))
      }
    },
  ).map_err(installed_effect_operation_reservation_issue)
  match result {
    Err(issue) =>
      Err(
        match refused.val {
          Some(issue) => Ledger(issue)
          None => issue
        },
      )
    Ok(value) => Ok(value)
  }
}

///|
pub fn finish_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  issuer : @publication.CapturedRunIssuancePreparation,
) -> Result[
  @publication.PreparedCapturedEffectRun,
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
    control.dependency_inventory is Some(inventory) &&
    control.dependency_capture is Some(original_issuer) &&
    physical_equal(original_issuer, issuer) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) {
    return Err(ForeignOriginal)
  }
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
    () => owner.effect_operation_opening && !owner.effect_operation_closing,
    spend => {
      match spend(1) {
        Err(issue) => return Err(Control(issue))
        Ok(_) => ()
      }
      let captured = match issuer.finish() {
        Ok(value) => value
        Err(_) => return Err(Original(Unsupported))
      }
      // Existing binder compares canonical inventory/root text once. Debit
      // the exact completed borrowed wire span before those synchronous walks.
      let wire = @publication.publication_contract_json(captured)
      for _ in 0..<8 {
        match spend(wire.length()) {
          Err(issue) => return Err(Control(issue))
          Ok(_) => ()
        }
      }
      match
        @publication.bind_prepared_captured_effect_run(captured, inventory) {
        Ok(value) => Ok(value)
        Err(_) => Err(Original(ForeignOriginal))
      }
    },
  ).map_err(installed_effect_operation_reservation_issue)
}
