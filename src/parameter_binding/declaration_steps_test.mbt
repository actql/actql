///|
fn staged_declaration_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_literal(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap().node,
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
test "staged declarations retain the actual original type before default and resume without rereading it" {
  // Actual literal order is z,a. The existing reader chooses canonical a,z.
  let root = staged_declaration_cursor(
    "{\"z\":{\"type\":\"number\",\"default\":3},\"a\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2}},\"default\":{\"v\":\"1.20\"},\"meta\":{\"note\":\"kept\"}}}",
  )
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationHeader,
  )
  assert_true(@parameter_binding.declaration_read_type_cursor(original) is None)
  assert_true(
    @parameter_binding.declaration_read_pending_syntax(original) is None,
  )
  @parameter_binding.advance_declaration_read(original)
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationType,
  )
  let cursor = @parameter_binding.declaration_read_type_cursor(original)
  assert_true(
    physical_equal(
      cursor,
      @parameter_binding.declaration_read_type_cursor(original),
    ),
  )
  assert_eq(
    @decode.cursor_path(cursor.unwrap()),
    @decode.cursor_path(@decode.field_at(root, 1).unwrap().1),
  )
  @parameter_binding.advance_declaration_read(original)
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationValue,
  )
  assert_true(@parameter_binding.declaration_read_type_cursor(original) is None)
  let pending = @parameter_binding.declaration_read_pending_syntax(original)
  assert_true(
    physical_equal(
      pending,
      @parameter_binding.declaration_read_pending_syntax(original),
    ),
  )
  let syntax = pending.unwrap()
  assert_true(syntax.default_value is Some(_))
  assert_true(syntax.metadata is Some(_))
  // The ordinary finishing API resumes this SAME typed original. A repeated
  // type reader would create a different ParameterType and source Cursor.
  let first = @parameter_binding.finish_declaration_read(original).unwrap()
  let declaration = @parameter_binding.declaration_at(first, 0).unwrap()
  assert_eq(declaration.name, "a")
  assert_true(physical_equal(declaration.parameter_type, syntax.parameter_type))
  assert_true(
    physical_equal(
      @parameter_binding.declaration_source(declaration),
      cursor.unwrap(),
    ),
  )
  assert_true(@parameter_binding.has_default(declaration))
  assert_eq(@parameter_binding.declaration_at(first, 1).unwrap().name, "z")
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationComplete,
  )
  assert_true(@parameter_binding.declaration_read_type_cursor(original) is None)
  assert_true(
    @parameter_binding.declaration_read_pending_syntax(original) is None,
  )
  @parameter_binding.advance_declaration_read(original)
  assert_true(
    physical_equal(
      first,
      @parameter_binding.finish_declaration_read(original).unwrap(),
    ),
  )
}

///|
test "staged declarations keep metadata refusal before default and later type work" {
  let root = staged_declaration_cursor(
    "{\"a\":{\"type\":\"number\",\"default\":\"bad\",\"meta\":{}},\"z\":{\"type\":\"unknown\"}}",
  )
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  @parameter_binding.advance_declaration_read(original)
  let syntax = @parameter_binding.declaration_read_pending_syntax(original).unwrap()
  let meta = syntax.metadata.unwrap()
  assert_true(syntax.default_value is Some(_))
  @parameter_binding.advance_declaration_read(original)
  let refusal = @parameter_binding.finish_declaration_read(original)
  guard refusal is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original metadata refusal")
  }
  assert_eq(kind, @parameter_binding.InvalidMetadata)
  assert_eq(path, @decode.cursor_path(meta))
  assert_eq(span, @decode.cursor_span(meta))
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationComplete,
  )
  @parameter_binding.advance_declaration_read(original)
  assert_true(
    physical_equal(
      refusal,
      @parameter_binding.finish_declaration_read(original),
    ),
  )
}

///|
test "staged declarations keep earlier default refusal before later invalid name" {
  let root = staged_declaration_cursor(
    "{\"a\":{\"type\":\"number\",\"minimum\":5,\"default\":3},\"bad-name\":{\"type\":\"unknown\"}}",
  )
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  @parameter_binding.advance_declaration_read(original)
  let default = @parameter_binding.declaration_read_pending_syntax(original).unwrap().default_value.unwrap()
  let refusal = @parameter_binding.finish_declaration_read(original)
  guard refusal is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original default constraint refusal")
  }
  assert_eq(kind, @parameter_binding.NumericConstraint)
  assert_eq(path, @decode.cursor_path(default))
  assert_eq(span, @decode.cursor_span(default))
}

///|
test "staged declarations retain absent empty and original parameter-count header outcomes" {
  let absent = @parameter_binding.prepare_declaration_read(
    None,
    limits(nodes=0, text=0, parameters=0),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(absent)
  assert_eq(
    @parameter_binding.declaration_read_phase(absent),
    @parameter_binding.DeclarationComplete,
  )
  assert_eq(
    @parameter_binding.declaration_count(
      @parameter_binding.finish_declaration_read(absent).unwrap(),
    ),
    0,
  )
  let root = staged_declaration_cursor("{}")
  let empty = @parameter_binding.prepare_declaration_read(Some(root), limits()).0.unwrap()
  @parameter_binding.advance_declaration_read(empty)
  guard @parameter_binding.finish_declaration_read(empty)
    is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original empty declaration refusal")
  }
  assert_eq(kind, @parameter_binding.EmptyDeclarations)
  assert_eq(path, @decode.cursor_path(root))
  assert_eq(span, @decode.cursor_span(root))
  let root = staged_declaration_cursor("{\"x\":{\"type\":\"unknown\"}}")
  let count = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(parameters=0),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(count)
  assert_true(
    @parameter_binding.finish_declaration_read(count)
    is Err(
      @parameter_binding.ParameterIssue(@parameter_binding.ParameterLimit, ..)
    ),
  )
  assert_true(@parameter_binding.declaration_read_pending_syntax(count) is None)
}

///|
test "staged header preserves original name refusal before null declaration value" {
  let root = staged_declaration_cursor("{\"bad-name\":null}")
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationType,
  )
  assert_true(
    @decode.is_null(
      @parameter_binding.declaration_read_type_cursor(original).unwrap(),
    ),
  )
  let refusal = @parameter_binding.finish_declaration_read(original)
  guard refusal is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original invalid name precedes null")
  }
  let child = @decode.field_at(root, 0).unwrap().1
  assert_eq(kind, @parameter_binding.InvalidName)
  assert_eq(path, @decode.cursor_path(child))
  assert_eq(span, @decode.cursor_key_span(child).unwrap())
}

///|
test "staged valid name retains original typed null refusal and nonnull cursor identity" {
  let root = staged_declaration_cursor("{\"a\":null}")
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationType,
  )
  let selected = @parameter_binding.declaration_read_type_cursor(original).unwrap()
  assert_true(@decode.is_null(selected))
  let refusal = @parameter_binding.finish_declaration_read(original)
  guard refusal is Err(@parameter_binding.Decode(issue)) else {
    fail("original required nonnull refusal")
  }
  assert_eq(issue.kind, @decode.UnexpectedNull)
  assert_eq(issue.path, @decode.cursor_path(selected))
  assert_eq(issue.span, @decode.cursor_span(selected))
  let original = staged_declaration_cursor("0")
  assert_true(
    physical_equal(original, @decode.require_non_null_cursor(original).unwrap()),
  )
  assert_true(
    @decode.require_non_null_cursor(selected)
    is Err({ kind: @decode.UnexpectedNull, .. }),
  )
}

///|
test "staged original type feeds the existing default Value constructor inventory before admission" {
  let root = staged_declaration_cursor(
    "{\"x\":{\"type\":\"string\",\"default\":\"" + "x".repeat(4096) + "\"}}",
  )
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(nodes=1000, text=10000),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  @parameter_binding.advance_declaration_read(original)
  let syntax = @parameter_binding.declaration_read_pending_syntax(original).unwrap()
  let geometry = @decode.observe_subtree_construction_geometry(
    syntax.default_value.unwrap(),
  )
  assert_eq((geometry.nodes, geometry.max_text_utf16), (1, 4096))
  let inventory = @value.parameter_syntax_value_body_construction_inventory(
    syntax, geometry,
  ).unwrap()
  assert_eq(inventory.owned_value_utf16_units, 0L)
  assert_eq(inventory.owned_decimal_scratch_utf16_units, 0L)
  let first = @parameter_binding.finish_declaration_read(original).unwrap()
  assert_true(
    physical_equal(
      @parameter_binding.declaration_at(first, 0).unwrap().parameter_type,
      syntax.parameter_type,
    ),
  )
  let root = staged_declaration_cursor(
    "{\"x\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"default\":\"1.20\"}}",
  )
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  @parameter_binding.advance_declaration_read(original)
  let syntax = @parameter_binding.declaration_read_pending_syntax(original).unwrap()
  let inventory = @value.parameter_syntax_value_body_construction_inventory(
    syntax,
    @decode.observe_subtree_construction_geometry(syntax.default_value.unwrap()),
  ).unwrap()
  // Actual checked precision4 and original default length4, never a second
  // precision ceiling or the adjacent String's4096 borrowed units.
  assert_eq(inventory.owned_value_utf16_units, 4L)
  assert_eq(inventory.owned_decimal_scratch_utf16_units, 14L)
  let first = @parameter_binding.finish_declaration_read(original).unwrap()
  assert_true(
    physical_equal(
      @parameter_binding.declaration_at(first, 0).unwrap().parameter_type,
      syntax.parameter_type,
    ),
  )
}
