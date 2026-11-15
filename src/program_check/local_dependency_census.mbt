///|
// DATA for one exact existing emitted body. It cannot construct a body, hash,
// execution capability or source permission. Its private owner is immutable.
struct CheckedLocalDependencyCensus {
  program : CheckedProgram
  unit : Int
  kind : LocalDependencyBodyKind
  cid : String
  geometry : @encode.EncodingConstructionGeometry
}

///|
// O(1) checked shape, before any selection/member vectors are constructed.
pub fn checked_local_dependency_static_count(
  program : CheckedProgram,
  unit_index : Int,
) -> Int? {
  guard program.units.get(unit_index) is Some(unit) &&
    @context.program_incoming_gates_count(program.gates, unit_index)
    is Some(gates) &&
    gates >= 0 &&
    unit.interfaces.length() <= (2147483647 - 6 - gates) / 2 else {
    return None
  }
  Some(6 + 2 * unit.interfaces.length() + gates)
}

///|
// Same fixed six roles, every import interface/type and every incoming gate.
// No caller-supplied role/CID vector or input-sized selection allocation.
pub fn checked_local_dependency_static_selection(
  program : CheckedProgram,
  unit_index : Int,
  index : Int,
) -> (String, LocalDependencyBodyKind)? {
  guard checked_local_dependency_static_count(program, unit_index)
    is Some(count) &&
    index >= 0 &&
    index < count &&
    program.units.get(unit_index) is Some(unit) else {
    return None
  }
  Some(
    match index {
      0 => ("local_dependencies", UnitDefinition)
      1 => ("local_body", LocalBody)
      2 => ("parameter_declarations", ParameterDeclarations)
      3 => ("used_values", UsedValues)
      4 => ("local_contracts", LocalContracts)
      5 => ("local_policy", LocalPolicy)
      _ => {
        let offset = index - 6
        if offset < 2 * unit.interfaces.length() {
          if offset % 2 == 0 {
            ("result_import_interface", ResultInterface(offset / 2))
          } else {
            ("result_import_type", ResultType(offset / 2))
          }
        } else {
          (
            "gate_requirement",
            IncomingGate(offset - 2 * unit.interfaces.length()),
          )
        }
      }
    },
  )
}

///|
// The caller has prepaid fixed/depth controls and the actual count vector.
// The same original scoped Work is consumed BEFORE graph/key/string visits.
pub fn census_checked_local_dependency_body(
  program : CheckedProgram,
  unit_index : Int,
  kind : LocalDependencyBodyKind,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Result[CheckedLocalDependencyCensus, LocalDependencyBodyIssue] {
  let writer = @encode.work_construction_census_writer(
    max_bytes, max_nodes, max_depth, work,
  ) catch {
    issue => return Err(Encoding(issue))
  }
  let cid = match
    emit_checked_local_dependency_body(program, unit_index, kind, writer) {
    Ok(cid) => cid
    Err(issue) => return Err(issue)
  }
  let geometry = @encode.finish_construction_measurement(writer) catch {
    issue => return Err(Encoding(issue))
  }
  Ok({ program, unit: unit_index, kind, cid, geometry, })
}

///|
pub fn checked_local_dependency_census_geometry(
  value : CheckedLocalDependencyCensus,
) -> @encode.EncodingConstructionGeometry {
  value.geometry
}

///|
// The caller has grown the SAME control for actual raw/tree/wire and sort
// construction, retaining its prior prefix. A fresh synchronous Work segment
// runs the unchanged canonical emitter; a census can never supply its text.
pub fn emit_censused_checked_local_dependency_body(
  value : CheckedLocalDependencyCensus,
  work : (Int) -> Bool,
  shared? : CheckedLocalDependencyBody? = None,
) -> Result[CheckedLocalDependencyBody, LocalDependencyBodyIssue] {
  let geometry = value.geometry
  let writer = try {
    match shared {
      None =>
        @encode.work_writer(
          geometry.bytes,
          geometry.nodes,
          geometry.depth,
          work,
        )
      Some(previous) => {
        if previous.cid != value.cid {
          return Err(ForeignBody)
        }
        @encode.work_comparing_writer(
          previous.wire,
          geometry.bytes,
          geometry.nodes,
          geometry.depth,
          work,
        )
      }
    }
  } catch {
    issue => return Err(Encoding(issue))
  }
  let cid = match
    emit_checked_local_dependency_body(
      value.program,
      value.unit,
      value.kind,
      writer,
    ) {
    Ok(cid) => cid
    Err(issue) => return Err(issue)
  }
  let (wire, bytes, nodes, depth) = try {
    match shared {
      None => @encode.finish_text_usage(writer)
      Some(previous) => {
        let (equal, bytes, nodes, depth) = @encode.finish_comparison_usage(
          writer,
        )
        if !equal {
          return Err(ForeignBody)
        }
        (previous.wire, bytes, nodes, depth)
      }
    }
  } catch {
    issue => return Err(Encoding(issue))
  }
  if cid != value.cid ||
    bytes != geometry.bytes ||
    nodes != geometry.nodes ||
    depth != geometry.depth {
    return Err(ForeignBody)
  }
  Ok({ owner: value.program, unit: value.unit, kind: value.kind, cid, wire, })
}

///|
pub fn checked_local_dependency_census_cid(
  value : CheckedLocalDependencyCensus,
) -> String {
  value.cid
}
