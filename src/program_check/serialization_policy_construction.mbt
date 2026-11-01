///|
/// Construction DATA for the existing Serialization provenance walk. Source
/// bodies are original checked objects; this allocates no policy/identity or
/// encoded body. Bounds cover all possible contributors, before path selection.
pub(all) struct SerializationPolicyConstruction {
  collections : @shape.CollectionConstructionInventory
  key_utf16_units : Int64
  effective : (Int, Int, Int)
  response_total : (Int, Int, Int)?
  response_max : (Int, Int, Int)?
  bodies : Int
}

///|
pub fn serialization_source_policy_construction(
  program : CheckedProgram,
  unit : Int,
) -> SerializationPolicyConstruction? {
  guard program.units.get(unit) is Some(selected) else { return None }
  let steps = @pipeline.step_count(selected.pipeline)
  let inputs = @pipeline.input_count(selected.pipeline)
  let mut edges = 0L
  let mut predicates = 0L
  for index in 0..<steps {
    let step = @pipeline.step_at(selected.pipeline, index).unwrap()
    edges += @pipeline.input_occurrence_count(step).to_int64()
    match step.operation {
      @pipeline.Unary(operation) | @pipeline.WindowGroup(operation) =>
        predicates += @relation.binding_count(operation).to_int64()
      _ => ()
    }
  }
  // Imported publication contributors are borrowed, never recursively cloned.
  // The whole existing checked Source inventory bounds their unique originals.
  let count = source_execution_count(program)
  guard count <= 2147483647 / 2 else { return None }
  let mut total_bytes = 0L
  let mut total_nodes = 0L
  let mut maximum = (0, 0, 0)
  for index in 0..<count {
    let subject = source_execution_at(program, index).unwrap().subject
    let measure = @encode.measuring_writer(2147483647, 2147483647, 100) catch {
      _ => return None
    }
    emit_source_response_policy(subject.response_policy, measure) catch {
      _ => return None
    }
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(measure) catch {
      _ => return None
    }
    total_bytes += bytes.to_int64()
    total_nodes += nodes.to_int64()
    maximum = (
      Int::max(maximum.0, bytes),
      Int::max(maximum.1, nodes),
      Int::max(maximum.2, depth),
    )
  }
  if total_bytes > 2147483647L || total_nodes > 2147483647L {
    return None
  }
  // Two data-policy CIDs and one response CID per original Source, before
  // deduplication. The longest classification and Bool spellings bound output.
  let effective = @encode.measuring_writer(2147483647, 2147483647, 100) catch {
    _ => return None
  }
  let cid = "sha256:" + "0".repeat(64)
  emit_effective_policy_parts(
    @environment.Confidential,
    false,
    count * 2,
    _ => cid,
    count,
    _ => cid,
    effective,
  ) catch {
    _ => return None
  }
  let geometry = @encode.finish_measurement_usage(effective) catch {
    _ => return None
  }
  let n = steps.to_int64()
  let s = count.to_int64()
  let i = inputs.to_int64()
  // Existing provenance records (including per-binding predicates), edge and
  // import records, occurrence variants, effective CID sort tuples and body
  // tuples. Containers use the shared collection owner's old/new overlap.
  let records = 6L * n + 2L * edges + 8L * s + 2L * i + predicates
  Some({
    collections: {
      records,
      record_references: 8L * records,
      record_words: 4L * records,
      reference_arrays: 48L,
      reference_items: 6L * n + 3L * edges + 12L * s + 3L * i + predicates,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 5L,
      map_entries: n + i + 3L * s + 1L,
    },
    // stage/input/join Int32 spelling, retained once per unique Source key.
    key_utf16_units: 37L * s,
    effective: geometry,
    response_total: if count == 0 {
      None
    } else {
      Some((total_bytes.to_int(), total_nodes.to_int(), maximum.2))
    },
    response_max: if count == 0 {
      None
    } else {
      Some(maximum)
    },
    bodies: count + 1,
  })
}
