///|
priv enum ClientEffectDependencyWireShape {
  Emitted(@encode.EncodingConstructionGeometry)
  OriginalRelation(@encode.EncodingConstructionGeometry)
  RetainedRoot(@publication.CapturedEffectDependencyBody)
  Observed(@source.JsonSourceGeometry)
}

///|
priv struct ClientEffectDependencyWireInput {
  kind : String
  identity : String?
  wire : String
  shape : ClientEffectDependencyWireShape
}

///|
// Closed phase results are immutable DATA only; no Work view/writer/cursor
// can escape a synchronous original segment through these alternatives.
priv enum ClientEffectDependencyGroupStep {
  Capacity(@execution.ExecutionCapacity)
  Units(Int64)
  Index(Int, Int64)
  Shape(Array[ClientEffectDependencyWireInput])
  Bodies(Array[@publication.CapturedEffectDependencyBody])
  Prepared(@publication.PreparedCapturedEffectDependencyInventory)
  Issued(@publication.CapturedEffectDependencyInventory)
  CatalogCensus(@checked.CheckedLocalDependencyCensus)
}

///|
// Shared by the exact existing Run control and captured-Read callers. Only
// numeric original growth and scoped original Work are injected; semantic
// bodies/roots are strict typed DATA, never supplied as callback authority.
fn prepare_funded_effect_dependency_inventory(
  kinds : Array[String],
  identities : Array[String?],
  wires : Array[String],
  roots : Array[@publication.CapturedEffectDependencyBody],
  cached : Map[
    String,
    (@checked.CheckedLocalDependencyBody, @encode.EncodingConstructionGeometry),
  ]?,
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
  original_artifacts? : Array[@publication_host.ClientEffectLocalResultArtifact]? = None,
  catalog_original? : (@checked.CheckedProgram, ClientEffectOperationControls)? = None,
) -> Result[
  (
    @publication.CapturedEffectDependencyInventory,
    @encode.EncodingConstructionGeometry,
  ),
  ClientInstalledManagedRunIssue,
] {
  let count = wires.length()
  if kinds.length() != count ||
    identities.length() != count ||
    max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_depth > 64 {
    return Err(ForeignOriginal)
  }
  // Actual count and borrowed length metadata only, before composite keys.
  let key_units = match
    segment(work => {
      let mut units = 0L
      for index in 0..<count {
        if !work(1) {
          return Err(InsufficientCapacity)
        }
        units += kinds[index].length().to_int64() +
          identities[index]
          .map(value => value.length().to_int64())
          .unwrap_or(70L) +
          1L
      }
      Ok(Units(units))
    }) {
    Ok(Units(units)) => units
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  guard installed_effect_dependency_key_capacity(count, key_units) is Some(keys) else {
    return Err(InsufficientCapacity)
  }
  match grow(keys) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if original_artifacts is Some(artifacts) && !artifacts.is_empty() {
    guard installed_effect_dependency_original_hash_capacity(artifacts.length())
      is Some(capacity) else {
      return Err(InsufficientCapacity)
    }
    match grow(capacity) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let inputs = match
    segment(work => {
      let values : Array[ClientEffectDependencyWireInput] = []
      let seen : Map[String, ClientEffectDependencyWireInput] = Map([])
      for index in 0..<count {
        if !work(1) {
          return Err(InsufficientCapacity)
        }
        let kind = kinds[index]
        let identity = identities[index]
        let wire = wires[index]
        // The complete Source set can reference the SAME immutable DATA from
        // many Result paths. Deduplicate the exact wire before quoting/parsing
        // its packet, as the later admitted-body set already does. Physical
        // Source occurrences, retained inputs and root owners stay separate.
        let selected = match identity {
          Some(cid) => {
            if !work(kind.length() + 1) || !work(cid.length()) {
              return Err(InsufficientCapacity)
            }
            Some(kind + "\u0000" + cid)
          }
          None => None
        }
        if selected is Some(key) && seen.get(key) is Some(previous) {
          if !work(wire.length()) {
            return Err(InsufficientCapacity)
          }
          if previous.wire != wire {
            return Err(ForeignOriginal)
          }
          continue
        }
        // A root admitted by this same dependency group already owns its
        // canonical body. Reuse it only under the same exact consumer limits
        // and full wire comparison; Result and Effect member custody is separate.
        if kind == "result_artifact" && identity is Some(cid) {
          let mut original : @publication.CapturedEffectDependencyBody? = None
          for root in roots {
            if !work(1) {
              return Err(InsufficientCapacity)
            }
            if @publication.captured_effect_dependency_body_kind(root) == kind &&
              @publication.captured_effect_dependency_body_cid(root) == cid {
              if !work(wire.length()) {
                return Err(InsufficientCapacity)
              }
              if @publication.captured_effect_dependency_body_json(root) != wire {
                return Err(ForeignOriginal)
              }
              if @publication.captured_effect_dependency_body_wire_usage(root)
                is Some((bytes, nodes, depth)) {
                if bytes > max_bytes || nodes > max_nodes || depth > max_depth {
                  return Err(Unsupported)
                }
                original = Some(root)
              }
              break
            }
          }
          if original is Some(root) {
            let input = { kind, identity, wire, shape: RetainedRoot(root), }
            if selected is Some(key) {
              seen[key] = input
            }
            values.push(input)
            continue
          }
        }
        let existing = match (cached, selected) {
          (Some(cache), Some(key)) => cache.get(key)
          _ => None
        }
        let mut shape = match existing {
          Some((body, geometry)) => {
            if !work(wire.length()) {
              return Err(InsufficientCapacity)
            }
            if @checked.checked_local_dependency_body_json(body) == wire {
              if geometry.bytes > max_bytes ||
                geometry.nodes > max_nodes ||
                geometry.depth > max_depth {
                return Err(Unsupported)
              }
              Emitted(geometry)
            } else {
              guard installed_effect_dependency_wire_geometry(
                  wire, max_bytes, max_nodes, max_depth, work,
                )
                is Some(geometry) else {
                return Err(Unsupported)
              }
              Observed(geometry)
            }
          }
          None => {
            guard installed_effect_dependency_wire_geometry(
                wire, max_bytes, max_nodes, max_depth, work,
              )
              is Some(geometry) else {
              return Err(Unsupported)
            }
            Observed(geometry)
          }
        }
        if kind == "relation_value" &&
          original_artifacts is Some(artifacts) &&
          shape is Observed(observed) &&
          identity is Some(cid) {
          for artifact in artifacts {
            if !work(1) {
              return Err(InsufficientCapacity)
            }
            let receipt = @publication_host.client_effect_local_relation_export_receipt(
              artifact,
            )
            let relation = @execution.completed_relation_export_identity(
              receipt,
            )
            if @execution.logical_relation_cid(relation) != cid {
              continue
            }
            let (bytes, nodes, _) = @execution.logical_relation_usage(relation)
            let (_, _, _, depth, _) = @execution.completed_relation_export_scalar_geometry(
              receipt,
            )
            guard installed_effect_dependency_original_relation_geometry(
                wire,
                cid,
                bytes,
                nodes,
                depth + 1,
                observed,
                work,
              )
              is Some(geometry) else {
              return Err(ForeignOriginal)
            }
            shape = OriginalRelation(geometry)
            break
          }
        }
        let input = { kind, identity, wire, shape, }
        if selected is Some(key) {
          seen[key] = input
        }
        values.push(input)
      }
      Ok(Shape(values))
    }) {
    Ok(Shape(values)) => values
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  let required = match
    segment(work => {
      let mut required = @execution.execution_capacity(0L, 0L).unwrap()
      for input in inputs {
        if !work(1) {
          return Err(InsufficientCapacity)
        }
        let added = match input.shape {
          // The SAME controller already retained its raw/canonical/parser quota
          // before producing this exact emitted wire. Do not buy it twice.
          Emitted(_) | RetainedRoot(_) => None
          // Unlike static emitted bodies, the exported Relation has only its
          // original text prefix so far. Buy the complete parser/body packet
          // on this same controller before admission; never treat it as prepaid.
          OriginalRelation(geometry) =>
            installed_effect_dependency_body_capacity(geometry)
          Observed(geometry) =>
            installed_effect_dependency_wire_capacity(
              geometry, max_bytes, max_nodes, max_depth,
            )
        }
        if !(input.shape is Emitted(_) || input.shape is RetainedRoot(_)) &&
          added is None {
          return Err(InsufficientCapacity)
        }
        if added is Some(added) {
          guard standard_create_sum_capacities(
              [required, added],
              sequential_workspace=true,
            )
            is Some(next) else {
            return Err(InsufficientCapacity)
          }
          required = next
        }
      }
      Ok(Capacity(required))
    }) {
    Ok(Capacity(value)) => value
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  match grow(required) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let bodies = match
    segment(work => {
      let bodies : Array[@publication.CapturedEffectDependencyBody] = []
      let seen : Map[
        String,
        (@publication.CapturedEffectDependencyBody, String),
      ] = Map([])
      for input in inputs {
        // A known kind+CID may share only after the complete original wire
        // agrees. Reusing already admitted immutable DATA avoids a second
        // parse/hash/graph walk for the same emitted dependency body.
        if input.identity is Some(identity) {
          if !work(input.kind.length() + 1) || !work(identity.length()) {
            return Err(InsufficientCapacity)
          }
          let selected = input.kind + "\u0000" + identity
          if seen.get(selected) is Some((_, previous)) {
            if !work(input.wire.length()) {
              return Err(InsufficientCapacity)
            }
            if previous != input.wire {
              return Err(ForeignOriginal)
            }
            continue
          }
        }
        if !work(1) {
          return Err(InsufficientCapacity)
        }
        let body = match input.shape {
          RetainedRoot(original) => original
          _ => {
            // Strict parser/admission/hash/canonical comparison all run. Debit the
            // actual borrowed wire span before each bounded codec traversal, with
            // scalar construction work bounded by its observed value inventory.
            for _ in 0..<6 {
              if !work(input.wire.length()) {
                return Err(InsufficientCapacity)
              }
            }
            let nodes = match input.shape {
              Emitted(g) | OriginalRelation(g) => g.nodes
              Observed(g) => Int::min(g.node_upper, max_nodes)
              RetainedRoot(_) => return Err(ForeignOriginal)
            }
            if !work(nodes) {
              return Err(InsufficientCapacity)
            }
            let body = match
              @publication.admit_captured_effect_dependency_body(
                input.kind,
                input.identity,
                input.wire,
                max_bytes,
                max_nodes,
                max_depth,
              ) {
              Ok(body) => body
              Err(_) => return Err(Unsupported)
            }
            body
          }
        }
        let cid = @publication.captured_effect_dependency_body_cid(body)
        if !work(input.kind.length() + 1) || !work(cid.length()) {
          return Err(InsufficientCapacity)
        }
        let key = input.kind + "\u0000" + cid
        match seen.get(key) {
          Some((_, previous)) => {
            if !work(input.wire.length()) {
              return Err(InsufficientCapacity)
            }
            if previous != input.wire {
              return Err(ForeignOriginal)
            }
          }
          None => {
            seen[key] = (body, input.wire)
            bodies.push(body)
          }
        }
      }
      Ok(Bodies(bodies))
    }) {
    Ok(Bodies(values)) => values
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  if catalog_original is Some((program, control)) {
    match
      close_installed_effect_catalog_references(
        program, control, bodies, roots, max_bytes, max_nodes, max_depth, grow, segment,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let (references, index_units) = match
    segment(work => {
      let mut references = roots.length().to_int64()
      let mut units = 0L
      for body in bodies {
        if !work(1) {
          return Err(InsufficientCapacity)
        }
        let count = @publication.captured_effect_dependency_body_reference_count(
          body,
        )
        if !work(count) {
          return Err(InsufficientCapacity)
        }
        let (_, names) = @publication.captured_effect_dependency_body_index_geometry(
          body,
        )
        references += count.to_int64()
        units += names
      }
      if references > 65536L {
        return Err(Unsupported)
      }
      Ok(Index(references.to_int(), units))
    }) {
    Ok(Index(references, units)) => (references, units)
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  guard installed_effect_dependency_graph_capacity(
      bodies.length(),
      roots.length(),
      references,
      index_units,
    )
    is Some(index) else {
    return Err(InsufficientCapacity)
  }
  match grow(index) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let prepared = match
    segment(work => {
      match
        @publication.prepare_captured_effect_dependency_inventory(
          bodies, roots, 2147483647, max_depth, work,
        ) {
        Ok(value) => Ok(Prepared(value))
        Err(_) => Err(Unsupported)
      }
    }) {
    Ok(Prepared(value)) => value
    Err(issue) => return Err(issue)
    _ => return Err(ForeignOriginal)
  }
  guard installed_effect_dependency_envelope_capacity(
      @publication.prepared_captured_effect_dependency_inventory_geometry(
        prepared,
      ),
      bodies.length(),
      index_units,
    )
    is Some(envelope) else {
    return Err(InsufficientCapacity)
  }
  match grow(envelope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    segment(work => {
      match
        @publication.issue_prepared_captured_effect_dependency_inventory(
          prepared, work,
        ) {
        Ok(value) => Ok(Issued(value))
        Err(_) => Err(Unsupported)
      }
    }) {
    Ok(Issued(value)) =>
      Ok(
        (
          value,
          @publication.prepared_captured_effect_dependency_inventory_geometry(
            prepared,
          ),
        ),
      )
    Err(issue) => Err(issue)
    _ => Err(ForeignOriginal)
  }
}
