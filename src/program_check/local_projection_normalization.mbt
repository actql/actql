///|
// The retained checked operation owns the complete schema and its immutable
// projection. Neither an equal mapping nor caller-provided JSON can issue this
// completion. The encoded canonical body is the existing REL.select params.
fn local_projection_normalization_entry(
  operation : @relation.CheckedOperation,
  step : Int,
  available : Int,
) -> (LocalSortNormalizationEntry, Int)? {
  let key = match @relation.operation(operation) {
    Rename => "rename"
    Drop => "drop"
    _ => return None
  }
  let source = @relation.source(operation)
  guard @decode.cursor_path(source)
    is [
      Key("stages"),
      Index(stage),
      Key("steps"),
      Index(original_step),
      Key(original_key),
    ] &&
    stage >= 0 &&
    original_step == step &&
    original_key == key else {
    return None
  }
  let path = "$.stages[" +
    stage.to_string() +
    "].steps[" +
    step.to_string() +
    "]." +
    key
  let mut remaining = match local_sort_text_work(path, available - 5) {
    Some(left) => left
    None => return None
  }
  let authored = @encode.writer(1024, 32, 8) catch { _ => return None }
  let canonical = @encode.writer(1024, 32, 8) catch { _ => return None }
  try {
    if key == "rename" {
      let input = @relation.input_schema(operation)
      let object = @decode.open_object(source).unwrap()
      @encode.begin_object(authored)
      // The checked complete input already owns canonical name order. Visit
      // it under the audit budget instead of sorting another authored array.
      for index in 0..<@schema.field_count(input) {
        if remaining <= 0 {
          return None
        }
        remaining -= 1
        let name = @schema.reference_name(
          @schema.field_at(input, index).unwrap().name,
        )
        guard @decode.lookup(object, name) is Some(original) else { continue }
        let value = @decode.text(original).unwrap()
        remaining = match local_sort_text_work(name, remaining) {
          Some(left) => left
          None => return None
        }
        remaining = match local_sort_text_work(value, remaining) {
          Some(left) => left
          None => return None
        }
        @encode.key(authored, name)
        @encode.string_value(authored, value)
      }
      @encode.end_object(authored)
    } else {
      @encode.begin_array(authored)
      for index in 0..<@decode.array_length(source).unwrap() {
        if remaining <= 0 {
          return None
        }
        remaining -= 1
        let name = @decode.text(@decode.element_at(source, index).unwrap()).unwrap()
        remaining = match local_sort_text_work(name, remaining) {
          Some(left) => left
          None => return None
        }
        @encode.string_value(authored, name)
      }
      @encode.end_array(authored)
    }
    @encode.begin_object(canonical)
    @encode.key(canonical, "columns")
    @encode.begin_array(canonical)
    for index in 0..<@relation.projection_field_count(operation) {
      if remaining <= 0 {
        return None
      }
      remaining -= 1
      let field = @relation.projection_field_at(operation, index).unwrap()
      let input = @schema.reference_name(field.input)
      let output = @schema.reference_name(field.output)
      remaining = match local_sort_text_work(input, remaining) {
        Some(left) => left
        None => return None
      }
      remaining = match local_sort_text_work(output, remaining) {
        Some(left) => left
        None => return None
      }
      if input == output {
        @encode.string_value(canonical, input)
      } else {
        @encode.begin_object(canonical)
        @encode.key(canonical, "from")
        @encode.string_value(canonical, input)
        @encode.key(canonical, "to")
        @encode.string_value(canonical, output)
        @encode.end_object(canonical)
      }
    }
    @encode.end_array(canonical)
    @encode.end_object(canonical)
    Some(
      (
        {
          operation,
          order: None,
          path,
          authored: @encode.finish(authored),
          canonical: @encode.finish(canonical),
        },
        remaining,
      ),
    )
  } catch {
    _ => None
  }
}
