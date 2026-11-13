///|
/// Constructor DATA for check_interactive_logical_map_binding, not binding
/// admission. Map/Plan identities and every reference still require that check.
/// Nested step-key hash/stringify and port-key parse/seal constructors must be
/// funded separately using these closed-shape geometry bounds and their owner
/// recipes. They are sequential; no key body is retained in the binding maps.
pub(all) struct InteractiveLogicalMapBindingConstruction {
  owner : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
  steps : Int
  ports : Int
  outputs : Int
  max_ports_per_step : Int
  max_coordinate_units : Int
  coordinate_retained_units : Int64
  port_body_concat_units : Int64
  step_key : (Int, Int, Int)
  step_key_preimage_fields : Int
  port_body : (Int, Int, Int)
  port_complete : (Int, Int, Int)
} derive(Eq, Debug)

///|
// Division toward zero also handles Int64::MIN without negating/overflowing.
fn interactive_binding_decimal_units(value : Int64) -> Int {
  let mut n = value
  let mut count = if n < 0L { 1 } else { 0 }
  while n != 0L {
    count += 1
    n /= 10L
  }
  if value == 0L {
    1
  } else {
    count
  }
}

///|
// Same left-associated body concatenations as the binding consumer. Literal
// parts are module-owned; sum each newly constructed prefix, not a guessed
// whole-body multiplier. Includes the final body; decimal text is separate.
fn interactive_binding_port_text(
  role_units : Int,
  digits : Int,
) -> (Int, Int64) {
  let mut prefix = "{\"version\":\"actql-logical-port-key/0.1\",\"compiled_plan_cid\":\"".length()
  let mut copies = 0L
  prefix += 71
  copies += prefix.to_int64()
  prefix += "\",\"step_id\":\"".length()
  copies += prefix.to_int64()
  prefix += 71
  copies += prefix.to_int64()
  prefix += "\",\"role\":\"".length()
  copies += prefix.to_int64()
  prefix += role_units
  copies += prefix.to_int64()
  prefix += "\",\"port_ordinal\":".length()
  copies += prefix.to_int64()
  prefix += digits
  copies += prefix.to_int64()
  prefix += 1
  copies += prefix.to_int64()
  (prefix, copies)
}

///|
/// Requires the separately exposed scanner-control inventory funded before entry.
/// This scalar walk borrows admitted CanonicalValue fields, holds only fixed
/// indices/options/tuples, and performs no parse, hash, writer, decimal String,
/// array/map construction or validation replay. The returned small record and
/// collection quotation controls likewise belong to that scanner basis.
/// The limits are the existing binding invocation's work/codec limits, not a
/// fresh grant. A sizing refusal does not classify the document as invalid.
pub fn interactive_logical_map_binding_construction(
  map : RunEvidenceValue,
  plan : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> InteractiveLogicalMapBindingConstruction? {
  if map.name != "logical_map" ||
    plan.name != "compiled_plan" ||
    max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 0 {
    return None
  }
  guard @json.object_field(map.value, "steps") is Some(@json.Array(steps)) else {
    return None
  }
  let step_count = @json.array_count(steps)
  if step_count > max_nodes {
    return None
  }
  let mut ports_total = 0L
  let mut outputs = 0
  let mut max_ports = 0
  let mut max_coordinate = 0
  let mut coordinate_retained = 0L
  let mut concat_peak = 0L
  let mut step_bytes = 0
  let mut port_bytes = 0
  for i in 0..<step_count {
    guard @json.array_at(steps, i) is Some(step) &&
      @json.object_field(step, "key") is Some(key) &&
      interactive_integer(key, "stage_ordinal") is Some(stage) &&
      @json.object_field(key, "occurrence") is Some(occurrence) &&
      @json.object_field(step, "ports") is Some(@json.Array(ports)) else {
      return None
    }
    let input_only = evidence_string(occurrence, "kind") == Some("input_output")
    guard interactive_integer(
        occurrence,
        if input_only {
          "input_port_ordinal"
        } else {
          "operation_ordinal"
        },
      )
      is Some(ordinal) else {
      return None
    }
    let coordinate = if input_only {
      "{\"kind\":\"input_output\",\"input_port_ordinal\":}".length()
    } else {
      "{\"kind\":\"operation\",\"operation_ordinal\":}".length()
    }
    let key_bytes = "{\"version\":\"actql-logical-step-key/0.1\",\"compiled_plan_cid\":\"\",\"stage_ordinal\":,\"occurrence\":,\"self_cid\":\"\"}".length() +
      71 +
      71 +
      interactive_binding_decimal_units(stage) +
      coordinate +
      interactive_binding_decimal_units(ordinal)
    step_bytes = Int::max(step_bytes, key_bytes)
    let count = @json.array_count(ports)
    ports_total += count.to_int64()
    if ports_total + step_count.to_int64() > max_nodes.to_int64() {
      return None
    }
    max_ports = Int::max(max_ports, count)
    let mut coordinate_units = 0L
    for j in 0..<count {
      guard @json.array_at(ports, j) is Some(port) &&
        evidence_string(port, "role") is Some(role) &&
        interactive_integer(port, "port_ordinal") is Some(ordinal) else {
        return None
      }
      let digits = interactive_binding_decimal_units(ordinal)
      let coord = role.length() + 1 + digits
      coordinate_units += coord.to_int64()
      max_coordinate = Int::max(max_coordinate, coord)
      let (body, prefixes) = interactive_binding_port_text(
        role.length(),
        digits,
      )
      port_bytes = Int::max(port_bytes, body)
      // Two ordinal.to_string calls; role+":" and complete coordinate.
      concat_peak = Int64::max(
        concat_peak,
        prefixes +
        2L * digits.to_int64() +
        (role.length() + 1).to_int64() +
        coord.to_int64(),
      )
      if role == "output" {
        outputs += 1
      }
    }
    coordinate_retained = Int64::max(coordinate_retained, coordinate_units)
  }
  guard @shape.collection_construction_extent({
      // Stored output tuples and one outputs.get comparison tuple stay
      // separate from fixed lookup/control carriers. Source census, co-counting
      // alternatives: top Plan checks/root8H8R; step/key checks16H16R;
      // port fields/source comparisons29H24R5W; contract Some2H2R;
      // success/failure carriers3H2R. Nested codecs own their own controls.
      records: outputs.to_int64() + 1L + 8L + 16L + 29L + 2L + 3L,
      record_references: 3L * outputs.to_int64() + 3L + 8L + 16L + 24L + 2L + 2L,
      record_words: 5L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 3L + (if step_count > 0 { 1L } else { 0L }),
      map_entries: step_count.to_int64() +
      ports_total +
      outputs.to_int64() +
      max_ports.to_int64(),
    })
    is Some(maps) &&
    @shape.add_collection_construction_extents(maps, {
      // Active coordinate Strings +8 body concatenations +2 coordinate
      // concatenations +2 decimal Strings. Nested codecs own their outputs.
      record_headers: max_ports.to_int64() + 8L + 2L + 2L,
      reference_slots: 0L,
      scalar_words: 0L,
    })
    is Some(owner) else {
    return None
  }
  Some({
    owner,
    owned_utf16_units: coordinate_retained + concat_peak,
    steps: step_count,
    ports: ports_total.to_int(),
    outputs,
    max_ports_per_step: max_ports,
    max_coordinate_units: max_coordinate,
    coordinate_retained_units: coordinate_retained,
    port_body_concat_units: concat_peak,
    step_key: (
      step_bytes,
      if step_count > 0 {
        8
      } else {
        0
      },
      if step_count > 0 {
        2
      } else {
        0
      },
    ),
    step_key_preimage_fields: if step_count > 0 {
      4
    } else {
      0
    },
    port_body: (
      port_bytes,
      if ports_total > 0L {
        6
      } else {
        0
      },
      if ports_total > 0L {
        1
      } else {
        0
      },
    ),
    port_complete: (
      if ports_total > 0L {
        port_bytes + ",\"self_cid\":\"\"".length() + 71
      } else {
        0
      },
      if ports_total > 0L {
        7
      } else {
        0
      },
      if ports_total > 0L {
        1
      } else {
        0
      },
    ),
  })
}

///|
let interactive_binding_scanner_inventory : (
  @shape.CollectionConstructionExtent,
  Int,
  Int,
) = {
  let quote = @shape.collection_construction_quotation_extent()
  (
    {
      // Root/step/port scalar lookups:16H13R3W (all alternatives co-counted).
      // Port prefix measurement tuple1H2W; final DATA1H4R9W, its three
      // geometry tuples3H9W and enclosing Some1H1R. Collection quotation
      // argument1H10W, added extent argument1H3W; add_extent's three checked
      // scalar Some plus result record/Some5H1R9W. Main quote stays owned by
      // decode_shape rather than copying its implementation constants here.
      record_headers: 16L +
      1L +
      1L +
      3L +
      1L +
      1L +
      1L +
      5L +
      quote.record_headers,
      reference_slots: 13L + 4L + 1L + 1L + quote.reference_slots,
      scalar_words: 3L + 2L + 9L + 9L + 10L + 3L + 9L + quote.scalar_words,
    },
    // Final DATA has4reference/9scalar fields; the collection inventory
    // argument has10scalar fields. This componentwise envelope covers both.
    4,
    10,
  )
}

///|
/// Module-retained finite scalar measurement controls and maximum record
/// layout. Fund these BEFORE calling the borrowed binding-geometry scanner;
/// the returned DATA cannot retroactively back its own construction. No input
/// text, permission, pricing, resource reservation, or allocator grant lives here.
pub fn interactive_logical_map_binding_scanner_controls() -> (
  @shape.CollectionConstructionExtent,
  Int,
  Int,
) {
  interactive_binding_scanner_inventory
}
