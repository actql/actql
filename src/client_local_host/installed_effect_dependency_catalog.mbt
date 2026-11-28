///|
fn installed_effect_catalog_role(kind : String) -> Bool {
  match kind {
    "source_contract"
    | "source_view_contract"
    | "data_policy"
    | "request_schema"
    | "carrier_schema"
    | "schema_evidence"
    | "capability_evidence" => true
    _ => false
  }
}

///|
// Two actual indexes: complete input-body keys and the visited typed edges.
// No maximum Environment forest, byte-as-entry conversion or policy ceiling.
fn installed_effect_catalog_index_capacity(
  entries : Int,
  references : Int,
  names : Int64,
) -> @execution.ExecutionCapacity? {
  if entries < 0 || references < 0 || names < 0L {
    return None
  }
  guard @shape.collection_construction_extent({
      records: 16L,
      record_references: 32L,
      record_words: 32L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: entries.to_int64() + references.to_int64(),
    })
    is Some(index) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: index.record_headers,
      reference_slots: index.reference_slots,
      scalar_words: index.scalar_words,
      owned_utf16_units: 2L * names,
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
// Fresh registered Run only. Bodies/roots were admitted once by the same
// funded group; only actual missing immutable Catalog edges are resolved.
// Cold has no Program resolver and still requires complete persisted DATA.
fn close_installed_effect_catalog_references(
  program : @checked.CheckedProgram,
  control : ClientEffectOperationControls,
  bodies : Array[@publication.CapturedEffectDependencyBody],
  roots : Array[@publication.CapturedEffectDependencyBody],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  grow : (@execution.ExecutionCapacity) -> Result[
    Unit,
    ClientInstalledManagedRunIssue,
  ],
  segment : (
    ((Int) -> Bool) -> Result[
      ClientEffectDependencyGroupStep,
      ClientInstalledManagedRunIssue,
    ],
  ) -> Result[ClientEffectDependencyGroupStep, ClientInstalledManagedRunIssue],
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let initial = match
    segment(work => {
      let mut refs = 0L
      let mut names = 0L
      for collection in [bodies, roots] {
        for body in collection {
          let count = @publication.captured_effect_dependency_body_reference_count(
            body,
          )
          if !work(1) || !work(count) {
            return Err(InsufficientCapacity)
          }
          let (_, units) = @publication.captured_effect_dependency_body_index_geometry(
            body,
          )
          refs += count.to_int64()
          names += units
        }
      }
      if refs > 65536L {
        return Err(Unsupported)
      }
      Ok(Index(refs.to_int(), names))
    }) {
    Ok(Index(refs, names)) => (refs, names)
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  guard installed_effect_catalog_index_capacity(
      bodies.length(),
      initial.0,
      initial.1,
    )
    is Some(capacity) else {
    return Err(InsufficientCapacity)
  }
  match grow(capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let known : Map[String, String] = Map([])
  let visited : Map[String, Bool] = Map([])
  match
    segment(work => {
      for body in bodies {
        let kind = @publication.captured_effect_dependency_body_kind(body)
        let cid = @publication.captured_effect_dependency_body_cid(body)
        if !work(kind.length() + 1) || !work(cid.length()) {
          return Err(InsufficientCapacity)
        }
        let key = kind + "\u0000" + cid
        let wire = @publication.captured_effect_dependency_body_json(body)
        if known.get(key) is Some(previous) {
          if !work(wire.length()) {
            return Err(InsufficientCapacity)
          }
          if previous != wire {
            return Err(ForeignOriginal)
          }
        } else {
          known[key] = wire
        }
      }
      Ok(Units(0L))
    }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let mut body_index = 0
  let mut root_index = 0
  let mut total_refs = initial.0
  while body_index < bodies.length() || root_index < roots.length() {
    let body = if body_index < bodies.length() {
      let value = bodies[body_index]
      body_index += 1
      value
    } else {
      let value = roots[root_index]
      root_index += 1
      value
    }
    let references = @publication.captured_effect_dependency_body_reference_count(
      body,
    )
    for edge in 0..<references {
      let selected = match
        segment(work => {
          if !work(1) {
            return Err(InsufficientCapacity)
          }
          guard @publication.captured_effect_dependency_body_reference_at(
              body, edge,
            )
            is Some((kind, cid)) else {
            return Err(ForeignOriginal)
          }
          if !work(kind.length() + 1) || !work(cid.length()) {
            return Err(InsufficientCapacity)
          }
          let key = kind + "\u0000" + cid
          if visited.contains(key) {
            return Ok(Units(0L))
          }
          visited[key] = true
          if known.contains(key) || !installed_effect_catalog_role(kind) {
            return Ok(Units(0L))
          }
          let selection = match
            @checked.begin_checked_local_catalog_selection(
              program, 0, kind, cid,
            ) {
            Err(_) => return Err(Unsupported)
            Ok(value) => value
          }
          while @checked.checked_local_catalog_selection_remaining(selection) >
                0 {
            let visits = Int::min(
              256,
              @checked.checked_local_catalog_selection_remaining(selection),
            )
            if !work(visits) {
              return Err(InsufficientCapacity)
            }
            match
              @checked.advance_checked_local_catalog_selection(
                selection,
                visits,
                work=Some(work),
              ) {
              Err(_) => return Err(Unsupported)
              Ok(_) => ()
            }
          }
          match
            @checked.census_checked_local_catalog_selection(
              selection, max_bytes, max_nodes, max_depth, work,
            ) {
            Err(_) => Err(Unsupported)
            Ok(census) => Ok(CatalogCensus(census))
          }
        }) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      guard selected is CatalogCensus(census) else { continue }
      let geometry = @checked.checked_local_dependency_census_geometry(census)
      guard installed_effect_dependency_body_capacity(geometry)
        is Some(capacity) else {
        return Err(InsufficientCapacity)
      }
      // Raw-cache and subsequent typed-key/body slots are actual selected
      // constructors, prepaid before the first writer/parser/cache insertion.
      let names = match
        segment(work => {
          guard @publication.captured_effect_dependency_body_reference_at(
              body, edge,
            )
            is Some((kind, cid)) else {
            return Err(ForeignOriginal)
          }
          if !work(kind.length() + 1) || !work(cid.length()) {
            return Err(InsufficientCapacity)
          }
          Ok(Units(kind.length().to_int64() + cid.length().to_int64() + 1L))
        }) {
        Ok(Units(value)) => value
        Err(issue) => return Err(issue)
        _ => return Err(ForeignOriginal)
      }
      // Group admission already retains the depth-bounded Work controls.
      // This late edge needs its entry and does not start a second frame.
      guard installed_effect_catalog_index_capacity(2, 0, 2L * names)
        is Some(keys) &&
        installed_effect_dependency_catalog_entry_capacity() is Some(slots) &&
        standard_create_sum_capacities(
          [capacity, keys, slots],
          sequential_workspace=true,
        )
        is Some(capacity) else {
        return Err(InsufficientCapacity)
      }
      // Return the lexical Work view before Resource/current/grow callbacks.
      match grow(capacity) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let added = match
        segment(work => {
          let cid = @checked.checked_local_dependency_census_cid(census)
          guard @publication.captured_effect_dependency_body_reference_at(
              body, edge,
            )
            is Some((kind, expected)) &&
            cid == expected else {
            return Err(ForeignOriginal)
          }
          if !work(kind.length() + 1) || !work(cid.length()) {
            return Err(InsufficientCapacity)
          }
          let key = kind + "\u0000" + cid
          let shared = control.dependency_static.get(key)
          let original = match
            @checked.emit_censused_checked_local_dependency_body(
              census,
              work,
              shared=shared.map(value => value.0),
            ) {
            Err(_) => return Err(Unsupported)
            Ok(value) => value
          }
          control.dependency_static[key] = (original, geometry)
          let wire = @checked.checked_local_dependency_body_json(original)
          for _ in 0..<6 {
            if !work(wire.length()) {
              return Err(InsufficientCapacity)
            }
          }
          if !work(geometry.nodes) {
            return Err(InsufficientCapacity)
          }
          let value = match
            @publication.admit_captured_effect_dependency_body(
              kind,
              Some(cid),
              wire,
              max_bytes,
              max_nodes,
              max_depth,
            ) {
            Err(_) => return Err(Unsupported)
            Ok(value) => value
          }
          Ok(Bodies([value]))
        }) {
        Ok(Bodies(values)) => values[0]
        Err(issue) => return Err(issue)
        _ => return Err(ForeignOriginal)
      }
      let (refs, names) = match
        segment(work => {
          let count = @publication.captured_effect_dependency_body_reference_count(
            added,
          )
          if !work(1) || !work(count) {
            return Err(InsufficientCapacity)
          }
          let (_, names) = @publication.captured_effect_dependency_body_index_geometry(
            added,
          )
          Ok(Index(count, names))
        }) {
        Ok(Index(count, names)) => (count, names)
        Err(issue) => return Err(issue)
        _ => return Err(ForeignOriginal)
      }
      if refs > 65536 - total_refs {
        return Err(Unsupported)
      }
      guard installed_effect_catalog_index_capacity(0, refs, names)
        is Some(delta) else {
        return Err(InsufficientCapacity)
      }
      match grow(delta) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard control.dependency_group is Some((entries, roots_count)) &&
        entries < 2147483647 else {
        return Err(ForeignOriginal)
      }
      control.dependency_group = Some((entries + 1, roots_count))
      total_refs += refs
      match
        segment(work => {
          let kind = @publication.captured_effect_dependency_body_kind(added)
          let cid = @publication.captured_effect_dependency_body_cid(added)
          if !work(kind.length() + 1) || !work(cid.length()) {
            return Err(InsufficientCapacity)
          }
          known[kind + "\u0000" + cid] = @publication.captured_effect_dependency_body_json(
            added,
          )
          bodies.push(added)
          Ok(Units(0L))
        }) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
  }
  Ok(())
}
