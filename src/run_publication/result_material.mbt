///|
// Checked copied material only. Physical read admission, Store generation,
// receiver lifetime and output acknowledgement remain with their adapters.
struct ResultMaterialSchema {
  fields : Array[String]
  contracts : Array[@contract.Contract]
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
struct ResultMaterialRow {
  schema : ResultMaterialSchema
  cells : Array[@admitted.CheckedValue]
}

///|
pub(all) enum ResultMaterialIssue {
  MaterialInvalidLimits
  MaterialInvalidSchema
  MaterialInvalidRow
  MaterialTypeMismatch
  MaterialForeignSchema
  MaterialOutputLimit
} derive(Eq, Debug)

///|
fn material_cursor(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @decode.Cursor? {
  guard @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: max_wire_bytes,
      max_nodes,
      max_depth,
    })
    is Ok(source) else {
    return None
  }
  @decode.admit(source, {
    max_nodes,
    max_depth,
    max_string_bytes: max_wire_bytes,
    max_total_string_bytes: max_wire_bytes,
  }).to_option()
}

///|
pub fn prepare_result_material_schema(
  schema_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_fields : Int,
) -> Result[ResultMaterialSchema, ResultMaterialIssue] {
  if max_wire_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_depth > 64 ||
    max_fields < 1 ||
    fields.is_empty() ||
    fields.length() > max_fields {
    return Err(MaterialInvalidLimits)
  }
  guard material_cursor(schema_wire, max_wire_bytes, max_nodes, max_depth)
    is Some(cursor) &&
    @decode.closed_object(cursor, fields) is Ok(schema) else {
    return Err(MaterialInvalidSchema)
  }
  let seen : Map[String, Unit] = Map([])
  let contracts : Array[@contract.Contract] = []
  for field in fields {
    if field.is_empty() || seen.contains(field) {
      return Err(MaterialInvalidSchema)
    }
    seen[field] = ()
    guard @decode.lookup(schema, field) is Some(value) &&
      @contract.read_checked(value, {
        max_nodes,
        max_depth,
        max_text_bytes: max_wire_bytes,
      })
      is Ok(contract) else {
      return Err(MaterialInvalidSchema)
    }
    contracts.push(contract)
  }
  Ok({ fields: fields.copy(), contracts, max_wire_bytes, max_nodes, max_depth, })
}

///|
pub fn admit_result_material_row(
  schema : ResultMaterialSchema,
  row_wire : String,
) -> Result[ResultMaterialRow, ResultMaterialIssue] {
  guard material_cursor(
      row_wire,
      schema.max_wire_bytes,
      schema.max_nodes,
      schema.max_depth,
    )
    is Some(cursor) &&
    @decode.closed_object(cursor, schema.fields) is Ok(row) else {
    return Err(MaterialInvalidRow)
  }
  let cells : Array[@admitted.CheckedValue] = []
  for index, field in schema.fields {
    guard @decode.lookup(row, field) is Some(value) else {
      return Err(MaterialInvalidRow)
    }
    match
      @admitted.admit_wire(schema.contracts[index], value, {
        max_nodes: schema.max_nodes,
        max_depth: schema.max_depth,
        max_text_bytes: schema.max_wire_bytes,
      }) {
      Ok(checked) => cells.push(checked)
      Err(_) => return Err(MaterialTypeMismatch)
    }
  }
  Ok({ schema, cells, })
}

///|
// ASCII escapes make terminal width independent of Unicode width tables and
// keep controls from creating extra rows or terminal commands. No truncation,
// normalization or scalar-domain conversion is performed.
fn material_table_text(text : String, max_bytes : Int) -> String? {
  let out = StringBuilder()
  let mut count = 0
  for char in text {
    let piece = if char == '\\' {
      "\\\\"
    } else if char.to_int() < 32 || char.to_int() > 126 {
      "\\u{" + char.to_int().to_hex() + "}"
    } else {
      char.to_string()
    }
    if piece.length() > max_bytes - count {
      return None
    }
    count += piece.length()
    out.write_string(piece)
  }
  Some(out.to_string())
}

///|
fn material_cell_text(
  checked : @admitted.CheckedValue,
  max_bytes : Int,
) -> String? {
  let text = match checked.value {
    @admitted.Null => "NULL"
    @admitted.Signed64(value) => value.to_string()
    _ =>
      match @admitted.canonical_scalar_text(checked, max_bytes) {
        Some(value) => value
        None => {
          let writer = @encode.writer(max_bytes, 8192, 64) catch {
            _ => return None
          }
          try {
            @admitted.emit_checked_wire_value(checked, writer)
            @encode.finish(writer)
          } catch {
            _ => return None
          }
        }
      }
  }
  material_table_text(text, max_bytes)
}

///|
pub fn render_result_material_table(
  schema : ResultMaterialSchema,
  rows : Array[ResultMaterialRow],
  max_rows : Int,
  max_output_bytes : Int,
) -> Result[String, ResultMaterialIssue] {
  if max_rows < 0 || max_output_bytes < 1 || rows.length() > max_rows {
    return Err(MaterialInvalidLimits)
  }
  let rendered : Array[Array[String]] = []
  let headers : Array[String] = []
  let widths : Array[Int] = []
  for field in schema.fields {
    guard material_table_text(field, max_output_bytes) is Some(text) else {
      return Err(MaterialOutputLimit)
    }
    headers.push(text)
    widths.push(text.length())
  }
  for row in rows {
    if !physical_equal(row.schema, schema) {
      return Err(MaterialForeignSchema)
    }
    let cells : Array[String] = []
    for index, value in row.cells {
      guard material_cell_text(value, max_output_bytes) is Some(text) else {
        return Err(MaterialOutputLimit)
      }
      widths[index] = Int::max(widths[index], text.length())
      cells.push(text)
    }
    rendered.push(cells)
  }
  // Check the full padded output before allocating padding or exposing bytes.
  let line_bytes = widths.fold(init=1L, (total, width) => {
      total + width.to_int64()
    }) +
    2L * (widths.length() - 1).to_int64()
  if line_bytes > max_output_bytes.to_int64() / (rows.length().to_int64() + 2L) {
    return Err(MaterialOutputLimit)
  }
  let out = StringBuilder()
  fn line(cells : Array[String]) {
    for index, cell in cells {
      if index > 0 {
        out.write_string("  ")
      }
      out.write_string(cell)
      if index + 1 < cells.length() {
        out.write_string(String::make(widths[index] - cell.length(), ' '))
      }
    }
    out.write_char('\n')
  }
  line(headers)
  line(widths.map(width => String::make(width, '-')))
  for cells in rendered {
    line(cells)
  }
  Ok(out.to_string())
}
