///|
// Intrinsic wire bound from this SAME admitted source. Each admitted Number
// is a Double (not an arbitrary source lexeme): 32 units cover its finite
// shortest decimal spelling, while six bytes per text unit cover JSON escaping.
// Punctuation, null/boolean tokens and key quotes fit the same per-node bound.
// This is constructor DATA, not a selected allowance or permission to emit.
fn client_effect_material_source_geometry(
  cursor : @decode.Cursor,
  input_bytes : Int,
) -> (Int, Int, Int)? {
  let usage = @decode.admission_usage(cursor)
  let span = @decode.cursor_span(cursor)
  let original_bytes = Int::max(input_bytes, span.end_byte - span.start_byte)
  let units = Int::max(0, original_bytes).to_int64() +
    usage.total_string_bytes.to_int64() +
    32L * usage.nodes.to_int64()
  guard @execution.checked_preparation_add_product(2L, units, 6L) is Some(bytes) &&
    bytes < 2147483647L else {
    return None
  }
  Some((bytes.to_int(), usage.nodes, Int::max(1, usage.depth)))
}

///|
fn client_effect_funded_material_input(
  purpose : String,
  geometry : (Int, Int, Int),
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
  before_body : (String, Int, Int, Int) -> Bool,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  if !before_body(purpose, geometry.0, geometry.1, geometry.2) {
    return Err(Input(MaterialsConstructionRefused(purpose)))
  }
  try {
    let writer = @encode.writer(geometry.0, geometry.1, geometry.2)
    emit(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => Err(Input(MaterialsEncoding(purpose, issue)))
  }
}

///|
// The selected Local parent backs each construction before entry. Completed
// strings coexist until the outer material encoder returns; no environment,
// supplied value, source or identity is reconstructed from current defaults.
fn client_effect_funded_original_input_wires(
  prepared : PreparedClientEffectComputation,
  before_body : (String, Int, Int, Int) -> Bool,
) -> Result[(String, String?, String), ClientEffectRunMaterialsIssue] {
  guard client_effect_material_source_geometry(
      @syntax.program_body(prepared.source),
      @syntax.program_usage(prepared.source).source.input_bytes,
    )
    is Some(program_geometry) else {
    return Err(Input(MaterialsConstructionRefused("program")))
  }
  let program = match
    client_effect_funded_material_input(
      "program",
      program_geometry,
      writer => @syntax.emit_program_source(prepared.source, writer),
      before_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let parameters = match prepared.supplied {
    None => None
    Some(original) => {
      guard client_effect_material_source_geometry(original, 0)
        is Some(geometry) else {
        return Err(Input(MaterialsConstructionRefused("parameters")))
      }
      match
        client_effect_funded_material_input(
          "parameters",
          geometry,
          writer => @syntax.emit_admitted_source_value(original, writer),
          before_body,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
    }
  }
  let environment = @checked.effect_program_static_environment(
    prepared.candidate,
  )
  let wire = match
    client_effect_funded_material_input(
      "environment",
      @environment.emission_geometry(environment),
      writer => @environment.emit(environment, writer),
      before_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((program, parameters, wire))
}

///|
// Reserve the SAME Local inverse's next nested parser before UTF8 conversion.
// Byte-derived node bounds are intrinsic to this JSON value, not capacity.
fn client_effect_material_read_funded(
  purpose : String,
  wire : String,
  nodes : Int,
  depth : Int,
  before_body : ((String, Int, Int, Int) -> Bool)?,
) -> Bool {
  match before_body {
    None => true
    Some(fund) =>
      match @scalar.admit_utf8_length(wire, 2147483646) {
        Err(_) => false
        Ok(bytes) =>
          fund(purpose, bytes, Int::min(nodes, Int::max(1, bytes)), depth)
      }
  }
}

///|
/// Borrow the SAME allowed compiler's checked owner before Local funding.
/// This does not validate a Run, issue authority or copy any original input.
pub fn client_effect_allowed_run_owner(
  value : ClientEffectAllowedRun,
) -> PreparedClientEffectComputation {
  value.compilation.owner
}
