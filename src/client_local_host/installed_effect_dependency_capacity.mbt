///|
// Result/member coordinates and grouping holders used by the existing Node
// exporter. Counts come from the original captured inventory, never bytes or
// a Host-selected limit. Source/Result physical holdings remain independent.
fn installed_effect_dependency_index_capacity(
  results : Int,
  members : Int,
  names? : Int64 = 0L,
  tables? : Int = 0,
) -> @execution.ExecutionCapacity? {
  if results < 0 || members < 0 || names < 0L || tables < 0 {
    return None
  }
  let n = results.to_int64()
  let m = members.to_int64()
  let t = tables.to_int64()
  guard @shape.collection_construction_extent({
      // Per Result: manifest coordinate, selected entry, dependency wrapper,
      // two ordered-unit/group pairs and the retained payload association.
      // Original pin materialization: local ports/occurrences, request
      // tuples, source/entry variants, original borrow wrappers and private
      // Table entries. Each physical holding remains an independent slot.
      // The warm Source handle's optional context field is one additional
      // borrowed-reference slot; its checked-context association is cold-only.
      records: 8L + 6L * n + 6L + 8L * n + 7L * m + 7L * t,
      record_references: 20L + 23L * n + 12L + 17L * n + 17L * m + 15L * t,
      record_words: 6L + 9L * n + 4L + 8L * n + 6L * m + 6L * t,
      reference_arrays: 19L + 4L * n,
      reference_items: 14L * n + 10L * m + 3L * t,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 4L,
      map_entries: 5L * n + 2L * m,
    })
    is Some(held) else {
    return None
  }
  let scratch = closed_values_program_arrays(4L, 4L * n + 2L * m, false)
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: held.record_headers,
      reference_slots: held.reference_slots,
      scalar_words: held.scalar_words,
      // Decimal checked Unit index (<=10 units) + slash and retained
      // borrowed name. Co-count concatenation/hash-key old/new text.
      owned_utf16_units: 3L * (names + 11L * (n + m)),
      owned_wire_bytes: 0L,
    },
    workspace: scratch,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// Called by the existing retainInputs entrance BEFORE the Host constructs
// Result/group/member vectors. Preserve this original prefix on every later
// row/control/codec resize, including a failed child or stopped export.
fn retain_installed_effect_dependency_index(
  owner : ClientInstalledManagedRun,
  preparation : ClientInstalledManagedRunOriginal,
  admission : @resources.PreparedRunAdmission[ClientInstalledEffectManagedPlan],
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
  control : ClientEffectOperationControls,
  inputs : @strategy.CapturedEffectInputs,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if control.dependency_inputs is Some(original) {
    if !physical_equal(original, inputs) {
      return Err(ForeignOriginal)
    }
    return check_installed_effect_operation_original(
      owner,
      ledger,
      preparation,
      Some(control),
    )
  }
  let count = @strategy.captured_effect_local_result_count(inputs)
  match @resources.charge_planning(ledger, count) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  if !@strategy.captured_effect_inputs_retained(inputs) {
    return Err(ForeignOriginal)
  }
  for index in 0..<count {
    if @strategy.captured_effect_local_result_at(inputs, index) is None {
      return Err(ForeignOriginal)
    }
  }
  guard installed_effect_dependency_index_capacity(
      count,
      plan.operations.length(),
    )
    is Some(dependency) &&
    installed_effect_control_capacity(
      Some(control),
      plan,
      dependency_capacity=Some(dependency),
    )
    is Some((capacity, idle)) else {
    return Err(InsufficientCapacity)
  }
  match
    @resources.resize_prepared_run_operation_control_construction(
      admission,
      plan,
      ledger,
      () => {
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
        if !@strategy.captured_effect_inputs_retained(inputs) ||
          @strategy.captured_effect_local_result_count(inputs) != count {
          return Err(ForeignOriginal)
        }
        Ok(())
      },
      control.reservation,
      @execution.execution_capacity_retained_bytes(capacity),
      installed_effect_control_execution(Some(control), capacity, idle),
    ).map_err(installed_effect_operation_reservation_issue) {
    Err(issue) => Err(issue)
    Ok(_) => {
      control.dependency_inputs = Some(inputs)
      control.dependency_capacity = Some(dependency)
      Ok(())
    }
  }
}

///|
// Initial numeric quote BEFORE the Work view, depth vectors or body selection
// arrays exist. Actual entries/Units and existing JSON depth are quantities,
// never permissions, row credit or max_nodes-per-body precharges.
fn installed_effect_dependency_fixed_capacity(
  entries : Int,
  units : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  if entries < 0 || units < 0 || depth < 0 {
    return None
  }
  // This numeric inventory also funds Definition recovery under its existing
  // selected parser depth. Dependency readers retain their own depth policy;
  // no independent depth policy belongs to a quote before construction.
  // Int inputs widen before products; the collection and byte recipes below
  // check all aggregate extents before the SAME parent reserves any vectors.
  let n = entries.to_int64()
  let d = depth.to_int64() + 1L
  let preflight = @source.json_source_preflight_control_extent()
  let phase = @resources.preparation_phase_work_continuation64_construction_inventory()
  guard @shape.collection_construction_extent({
      // Censuses own a9-word geometry, source/role tuple and output pair.
      records: 5L * n,
      record_references: 11L * n,
      record_words: 12L * n,
      // Source payload original vector plus its Core token projection are
      // built after group reserve, before shape/admission construction.
      reference_arrays: 5L,
      reference_items: 5L * n,
      scalar_arrays: 1L,
      scalar_items: units.to_int64(),
      // Frozen Host body aliases are indexed before DTO flattening. A Map
      // quote dominates this Set, including actual candidate-count growth.
      maps: 1L,
      map_entries: n,
    })
    is Some(held) &&
    @encode.measuring_writer_construction_extent(0, depth) is Some(writer) &&
    @shape.collection_construction_extent({
      // Resource view:3Refs, spend/defer contexts and the old/new immutable
      // LedgerUsage overlap9H17R17W. Closed caller: error Ref + two work/live
      // contexts4H14R2W. Work sink+geometry state2H1R7W and finish geometry1H9W.
      // Six exact emitter alternatives own only depth-sized continuations.
      // Contract emission adds <=6 fixed vocabulary member pairs per depth;
      // its borrowed Fields vector never grows with output field width.
      // Three Host DATA-property descriptors coexist during alias checking.
      // Price the shared phase receipt explicitly, alongside the existing
      // Resource/caller/codec frames, so a prepaid receipt is reused exactly.
      records: phase.record_headers + 19L + 24L * d,
      record_references: phase.reference_slots + 5L + 37L + 64L * d,
      record_words: phase.scalar_words + 5L + 44L + 32L * d,
      reference_arrays: 6L,
      reference_items: 12L * d,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  @execution.preparation_execution_capacity({
    // Keep one bounded Work/census-depth control slot on this original
    // prefix. The owned second pass can then add its measured text/sort
    // workspace without borrowing these still-coheld control cells.
    retained: {
      record_headers: held.record_headers +
      writer.record_headers +
      controls.record_headers +
      preflight.record_headers,
      reference_slots: held.reference_slots +
      writer.reference_slots +
      controls.reference_slots +
      preflight.reference_slots,
      scalar_words: held.scalar_words +
      writer.scalar_words +
      controls.scalar_words +
      preflight.scalar_words,
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
  })
}

///|
// Add a measured DATA extent to the SAME control, retaining every prior
// failed/successful prefix through later operation/codec resizes and cleanup.
fn retain_installed_effect_dependency_capacity(
  owner : ClientInstalledManagedRun,
  preparation : ClientInstalledManagedRunOriginal,
  admission : @resources.PreparedRunAdmission[ClientInstalledEffectManagedPlan],
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
  control : ClientEffectOperationControls,
  added : @execution.ExecutionCapacity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let next = match control.dependency_capacity {
    None => added
    Some(previous) => {
      let before = @execution.execution_capacity_retained_bytes(previous)
      let after = @execution.execution_capacity_retained_bytes(added)
      guard @execution.checked_preparation_add_product(before, after, 1L)
        is Some(retained) &&
        @execution.checked_preparation_add_product(
          retained,
          Int64::max(
            @execution.execution_capacity_execution_bytes(previous) - before,
            @execution.execution_capacity_execution_bytes(added) - after,
          ),
          1L,
        )
        is Some(execution) &&
        @execution.execution_capacity(retained, execution) is Some(next) else {
        return Err(InsufficientCapacity)
      }
      next
    }
  }
  guard installed_effect_control_capacity(
      Some(control),
      plan,
      dependency_capacity=Some(next),
    )
    is Some((capacity, idle)) else {
    return Err(InsufficientCapacity)
  }
  let execution = if control.construction_deferred &&
    !control.construction_active {
    // Only this dependency constructor is running. Its own measured scratch
    // coexists with retained DATA; the unrelated generic Effect frame is idle.
    match
      @execution.checked_preparation_add_product(
        idle,
        @execution.execution_capacity_execution_bytes(next) -
        @execution.execution_capacity_retained_bytes(next),
        1L,
      ) {
      Some(value) => value
      None => return Err(InsufficientCapacity)
    }
  } else {
    @execution.execution_capacity_execution_bytes(capacity)
  }
  match
    @resources.resize_prepared_run_operation_control_construction(
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
      @execution.execution_capacity_retained_bytes(capacity),
      execution,
    ).map_err(installed_effect_operation_reservation_issue) {
    Err(issue) => Err(issue)
    Ok(_) => {
      control.dependency_capacity = Some(next)
      Ok(())
    }
  }
}

///|
// The closed public wrapper calls this only after its synchronous constructor
// stack has returned. All emitted wire, typed bodies, pins and cache/control
// records remain in the original retained prefix. Only completed dependency
// scratch is returned; a failed constructor never reaches this cut.
fn complete_installed_effect_dependency_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    physical_equal(plan, expected_plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_capacity is Some(previous) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening ||
    owner.effect_operation_closing ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    control.dependency_capture is Some(_) {
    return Err(AlreadyBound)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let retained = @execution.execution_capacity_retained_bytes(previous)
  let completed = @execution.execution_capacity(retained, retained).unwrap()
  guard installed_effect_control_capacity(
      Some(control),
      plan,
      dependency_capacity=Some(completed),
    )
    is Some((capacity, idle)) else {
    return Err(InsufficientCapacity)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  match
    @resources.resize_prepared_run_operation_control_construction(
      admission,
      plan,
      ledger,
      () => {
        if !owner.effect_operation_opening || owner.effect_operation_closing {
          return Err(ClientInstalledManagedRunIssue::Retired)
        }
        check_installed_effect_operation_original(
          owner,
          ledger,
          preparation,
          Some(control),
        )
      },
      control.reservation,
      @execution.execution_capacity_retained_bytes(capacity),
      installed_effect_control_execution(Some(control), capacity, idle),
    ).map_err(installed_effect_operation_reservation_issue) {
    Err(issue) => Err(issue)
    Ok(_) => {
      control.dependency_capacity = Some(completed)
      Ok(())
    }
  }
}

///|
// Actual emitted geometry includes lowered/generated fields, checked
// contracts/catalog/parameters and final writer bytes, not source JSON size.
fn installed_effect_dependency_body_capacity(
  geometry : @encode.EncodingConstructionGeometry,
) -> @execution.ExecutionCapacity? {
  guard program_artifact_parse_layout(
      @encode.construction_geometry_usage(geometry),
      structure=Some(geometry),
    )
    is Some(parse) &&
    @encode.text_writer_construction_inventory(
      geometry.bytes,
      geometry.nodes,
      geometry.depth,
    )
    is Some(writer) &&
    @shape.collection_construction_extent({
      // The four Cursor emitters allocate only emitted field pairs and
      // arrays on the owned second pass. In-place heap sort owns no scratch.
      records: 2L * geometry.fields.to_int64(),
      record_references: 4L * geometry.fields.to_int64(),
      record_words: 0L,
      reference_arrays: geometry.objects.to_int64(),
      reference_items: geometry.fields.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(sort) &&
    @execution.compose_preparation_representation([
      parse.value,
      {
        record_headers: 4L + geometry.nodes.to_int64(),
        reference_slots: 10L + 2L * geometry.nodes.to_int64(),
        scalar_words: 6L,
        owned_utf16_units: geometry.bytes.to_int64(),
        owned_wire_bytes: geometry.bytes.to_int64(),
      },
      closed_values_program_arrays(2L, geometry.nodes.to_int64(), false),
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      parse.temporary,
      {
        record_headers: writer.record_headers + sort.record_headers + 1L,
        reference_slots: writer.reference_slots + sort.reference_slots + 1L,
        scalar_words: writer.scalar_words + sort.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: geometry.bytes.to_int64(),
      },
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
fn installed_effect_dependency_key_capacity(
  entries : Int,
  units : Int64,
) -> @execution.ExecutionCapacity? {
  if entries < 0 || units < 0L {
    return None
  }
  let n = entries.to_int64()
  guard @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: n,
      scalar_arrays: 1L,
      scalar_items: n,
      // Early exact-wire DATA deduplication precedes the body parser/quote.
      // Its keys/entries are funded here before that staging map exists.
      maps: 3L,
      map_entries: 3L * n,
    })
    is Some(index) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: index.record_headers,
      reference_slots: index.reference_slots,
      scalar_words: index.scalar_words,
      owned_utf16_units: 2L * units,
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
  })
}

///|
fn installed_effect_dependency_shared_body_capacity() -> @execution.ExecutionCapacity? {
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 2L,
      reference_slots: 5L,
      scalar_words: 2L,
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
  })
}

///|
// Actual body/root/reference geometry before complete closure indexes and
// encoder ordering vectors. Fixed vocabulary remains borrowed; semantic keys
// and every reference edge are retained DATA, not physical-owner sharing.
fn installed_effect_dependency_graph_capacity(
  entries : Int,
  roots : Int,
  references : Int,
  key_units : Int64,
) -> @execution.ExecutionCapacity? {
  if entries < 0 || roots < 0 || references < 0 || key_units < 0L {
    return None
  }
  let n = entries.to_int64()
  let r = references.to_int64()
  let p = roots.to_int64()
  guard @shape.collection_construction_extent({
      // Kind indexes, normalized edge nodes, root references and the prepared
      // immutable snapshot retain no copied body value trees.
      records: 8L + 3L * n + 2L * r + 2L * p,
      record_references: 20L + 12L * n + 6L * r + 5L * p,
      record_words: 8L + 4L * n + 2L * p,
      reference_arrays: 8L + 3L * n,
      reference_items: 10L * n + 4L * r + 3L * p,
      scalar_arrays: 2L,
      scalar_items: 2L * n,
      // Each actual computation can own its observed position/interface/Model
      // sets. Their entries come from the complete admitted reference count.
      maps: 7L + 4L * n,
      map_entries: 6L * n + 4L * r + 2L * p,
    })
    is Some(index) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: index.record_headers,
      reference_slots: index.reference_slots,
      scalar_words: index.scalar_words,
      owned_utf16_units: 4L * key_units,
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
  })
}

///|
// issue_prepared_captured_effect_dependency_inventory emits the SAME admitted
// CanonicalValue bodies. No Source parser, normalization, new value tree or
// wire buffer is constructed here. Existing body/index holdings stay charged.
fn installed_effect_dependency_envelope_capacity(
  geometry : @encode.EncodingConstructionGeometry,
  entries : Int,
  key_units : Int64,
) -> @execution.ExecutionCapacity? {
  if entries < 0 || key_units < 0L || geometry.bytes < 0 || geometry.depth < 0 {
    return None
  }
  let n = entries.to_int64()
  let d = geometry.depth.to_int64()
  guard @encode.text_writer_construction_inventory(
      geometry.bytes,
      geometry.nodes,
      geometry.depth,
    )
    is Some(writer) &&
    @shape.reference_array_retained_extent(1L, n) is Some(output) &&
    @shape.collection_construction_extent({
      // One (key,body) pair and key String per entry. Heap sort is in-place;
      // map returns a separate array while ordered pairs/keys still coexist.
      records: 2L * n + 3L,
      record_references: 2L * n + 3L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(ordering) &&
    @shape.collection_construction_extent({
      // Canonical emit_value borrows every value/key. Its synchronous stack
      // owns one cursor1H1R1W plus parent variant1H1R1W per open container.
      records: 2L * d + 2L,
      record_references: 2L * d + 2L,
      record_words: 2L * d,
      reference_arrays: 1L,
      reference_items: d,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(emission) &&
    @execution.checked_preparation_add_product(0L, key_units, 2L) is Some(keys) else {
    return None
  }
  let bytes = geometry.bytes.to_int64()
  @execution.preparation_execution_capacity({
    // Final String, inventory and Result plus its returned body-reference
    // vector. These are additional roots; body value trees are only borrowed.
    retained: {
      record_headers: output.record_headers + 3L,
      reference_slots: output.reference_slots + 4L,
      scalar_words: output.scalar_words,
      owned_utf16_units: bytes,
      owned_wire_bytes: 0L,
    },
    workspace: {
      // The writer recipe ALREADY includes its final String. Split that one
      // header/text domain into returned holding, leaving old/new builder
      // backing and all writer controls live until this constructor returns.
      record_headers: writer.record_headers -
      1L +
      ordering.record_headers +
      emission.record_headers +
      1L,
      reference_slots: writer.reference_slots +
      ordering.reference_slots +
      emission.reference_slots +
      3L,
      scalar_words: writer.scalar_words +
      ordering.scalar_words +
      emission.scalar_words +
      2L,
      owned_utf16_units: writer.owned_utf16_units - bytes + keys,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
