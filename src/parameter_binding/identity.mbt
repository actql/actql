///|
// Rest frames retain owned values, not a second projected tree. Each frame
// schedules one child at a time; traversal space does not grow with array width.
priv enum IdentityFrame {
  ArrayRest(@value.FrozenArray[@value.Value], @contract.ParameterType, Int)
  ObjectRest(
    @value.FrozenArray[(String, @value.Value)],
    @contract.ParameterFields,
    Int,
    Bool,
    Bool
  )
}

///|
fn marker(
  output : @encode.Writer,
  kind : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(output)
  @encode.key(output, "$actql_value")
  @encode.begin_array(output)
  @encode.string_value(output, kind)
}

///|
fn end_marker(output : @encode.Writer) -> Unit raise @encode.EncodeFailure {
  @encode.end_array(output)
  @encode.end_object(output)
}

///|
fn needs_escape(values : @value.FrozenArray[(String, @value.Value)]) -> Bool {
  // Checked object fields are already sorted by UTF-16 code units.
  let mut low = 0
  let mut high = @value.element_count(values)
  while low < high {
    let mid = low + (high - low) / 2
    let (name, _) = @value.element_at(values, mid).unwrap()
    let order = @canonical.compare_utf16(name, "$actql_value")
    if order == 0 {
      return true
    } else if order < 0 {
      low = mid + 1
    } else {
      high = mid
    }
  }
  false
}

///|
fn emit_bound_value(
  root : @value.Value,
  parameter : @contract.ParameterType,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let pending : Array[IdentityFrame] = []
  let mut current = Some((root, parameter))
  while current is Some(_) || !pending.is_empty() {
    if current is Some((value, parameter)) {
      current = None
      match value {
        @value.Null => @encode.null_value(output)
        @value.Boolean(b) => @encode.bool_value(output, b)
        @value.Number(n) => @encode.number_value(output, n)
        @value.Text(text) =>
          if parameter.rule is @contract.Duration {
            // Ready can only be constructed after this exact duration check.
            let milliseconds = @scalar.read_duration_ms(text).unwrap()
            marker(output, "duration")
            @encode.number_value(output, milliseconds.to_double())
            end_marker(output)
          } else {
            @encode.string_value(output, text)
          }
        @value.Date(text) | @value.Timestamp(text) =>
          @encode.string_value(output, text)
        @value.Decimal(decimal) => {
          marker(output, "decimal")
          @encode.begin_object(output)
          @encode.key(output, "coefficient")
          @encode.string_value(output, decimal.coefficient)
          @encode.key(output, "precision")
          @encode.number_value(output, decimal.precision.to_double())
          @encode.key(output, "scale")
          @encode.number_value(output, decimal.scale.to_double())
          @encode.key(output, "version")
          @encode.string_value(output, "aoa-decimal-value/0.1")
          @encode.end_object(output)
          end_marker(output)
        }
        @value.Array(items) => {
          guard! parameter.rule is @contract.Items(item, ..)
          @encode.begin_array(output)
          pending.push(ArrayRest(items, item, 0))
        }
        @value.Object(entries) => {
          guard! parameter.rule is @contract.Properties(fields)
          let escaped = needs_escape(entries)
          if escaped {
            marker(output, "object")
            @encode.begin_array(output)
          } else {
            @encode.begin_object(output)
          }
          pending.push(ObjectRest(entries, fields, 0, escaped, false))
        }
        // Ordinary Parameter declaration admission excludes vector and Ref.
        @value.Vector(_) => abort("invalid bound Parameter domain")
      }
    } else {
      match pending.pop().unwrap() {
        ArrayRest(items, item, index) =>
          if @value.element_at(items, index) is Some(value) {
            pending.push(ArrayRest(items, item, index + 1))
            current = Some((value, item))
          } else {
            @encode.end_array(output)
          }
        ObjectRest(entries, fields, index, escaped, pair_open) => {
          if pair_open {
            @encode.end_array(output)
          }
          if @value.element_at(entries, index) is Some((name, value)) {
            let (_, field) = @contract.parameter_field_at(fields, index).unwrap()
            if escaped {
              @encode.begin_array(output)
              @encode.string_value(output, name)
            } else {
              @encode.key(output, name)
            }
            pending.push(
              ObjectRest(entries, fields, index + 1, escaped, escaped),
            )
            current = Some((value, field))
          } else if escaped {
            @encode.end_array(output)
            end_marker(output)
          } else {
            @encode.end_object(output)
          }
        }
      }
    }
  }
}

///|
/// Emit the exact Parameter Values CID preimage, not the wire envelope with CID.
/// The writer's budgets cover all wrappers and the enclosing version/values map.
pub fn emit_values(
  values : BoundValues,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(output)
  @encode.key(output, "values")
  @encode.begin_object(output)
  for entry in values.entries {
    @encode.key(output, entry.name)
    emit_value_identity(entry, output)
  }
  @encode.end_object(output)
  @encode.key(output, "version")
  @encode.string_value(output, "actql-parameter-values/0.1")
  @encode.end_object(output)
}

///|
/// Emit one admitted Parameter's typed identity projection, not its wire value.
/// The sealed bound parameter retains the declaration type used for admission.
pub fn emit_value_identity(
  value : BoundParameter,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_bound_value(value.value.value, value.parameter_type, output)
}

///|
pub fn stringify_values(
  values : BoundValues,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let output = @encode.writer(max_bytes, max_nodes, max_depth)
  emit_values(values, output)
  @encode.finish(output)
}

///|
pub fn measure_values(
  values : BoundValues,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int raise @encode.EncodeFailure {
  let output = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
  emit_values(values, output)
  @encode.finish_measurement(output)
}

///|
/// Hash canonical UTF-8 directly, without a projected tree, String or byte array.
pub fn parameter_values_cid(
  values : BoundValues,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let output = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_values(values, output)
  "sha256:" + @encode.finish_hash(output)
}
