///|
// Test-only adapter for existing ordinary Host tests. Not an SDK export or a
// new Host input mode; full source routing is a later delivery unit.
fn limits() -> @aql.Limits {
  {
    frontend: {
      max_tokens: 100000,
      max_syntax_nodes: 100000,
      max_syntax_depth: 128,
      max_literal_bytes: 1000000,
      max_symbol_count: 10000,
      max_generated_steps: 10000,
      max_generated_fields: 100000,
      max_lowering_work: 10000000,
    },
    construction: {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 128, },
      tree: {
        max_nodes: 100000,
        max_depth: 128,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_origin_entries: 200000,
      max_output_bytes: 1000000,
    },
    max_stages: 128,
  }
}

///|
pub suberror FixtureRejected {
  FixtureRejected
}

///|
#export_name("structuralToJson")
pub fn structural_to_json(text : String) -> String {
  compile_text(text) catch {
    _ => ""
  }
}

///|
fn compile_text(text : String) -> String raise {
  let parsed = match @aql.parse(text, limits()) {
    Ok(p) => p
    Err(_) => raise FixtureRejected
  }
  let writer = @encode.writer(1000000, 100000, 128)
  @aql.emit_program_json(@aql.program(parsed), writer)
  @encode.finish(writer)
}

///|
#export_name("jsonToStructural")
pub fn json_to_structural(text : String) -> String {
  format_json(text) catch {
    _ => ""
  }
}

///|
fn format_json(text : String) -> String raise {
  let limits = limits()
  let parsed = match
    @syntax.parse(
      text,
      {
        source: limits.construction.source,
        tree: limits.construction.tree,
        max_stages: limits.max_stages,
      },
      format=Json,
    ) {
    Ok(p) => p
    Err(_) => raise FixtureRejected
  }
  match @aql.format(parsed, 1000000) {
    Ok(text) => text
    Err(e) => raise e
  }
}

///|
#export_name("jsonAdmissionDiagnostic")
pub fn json_admission_diagnostic(text : String) -> String {
  let caps = limits()
  match
    @syntax.parse(
      text,
      {
        source: caps.construction.source,
        tree: caps.construction.tree,
        max_stages: caps.max_stages,
      },
      format=Json,
    ) {
    Ok(_) => ""
    Err(e) => @debug.to_string(e)
  }
}
