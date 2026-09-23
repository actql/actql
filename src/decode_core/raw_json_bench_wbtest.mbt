///|
fn raw_json_bench_value() -> Json {
  @json.parse(
    "{\"id\":123456,\"name\":\"sample\",\"active\":true,\"tags\":[\"a\",\"b\"]}",
  ) catch {
    _ => abort("invalid benchmark JSON")
  }
}

///|
let raw_json_bench_span : @span.Span = {
  start_byte: 0,
  end_byte: 72,
  start_line: 1,
  end_line: 1,
  start_column: 1,
  end_column: 73,
  source_path: "<physical>",
}

///|
let raw_json_bench_limits : Limits = {
  max_nodes: 32,
  max_depth: 4,
  max_string_bytes: 100,
  max_total_string_bytes: 100,
}

///|
fn source_copy_for_bench(value : Json) -> @source.Node {
  let span = raw_json_bench_span
  let value : @source.Value = match value {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(number, ..) => Number(number)
    String(text) => String(text)
    Array(items) => Array(items.map(source_copy_for_bench))
    Object(fields) =>
      Object(
        fields
        .to_array()
        .map(pair => @source.Field::{
          key: pair.0,
          key_span: span,
          value: source_copy_for_bench(pair.1),
        }),
      )
  }
  { value, span, }
}

///|
test "bench parsed JSON through source copy" (it : @bench.T) {
  let parsed = raw_json_bench_value()
  it.bench(fn() {
    for _ in 0..<1000 {
      it.keep(admit(source_copy_for_bench(parsed), raw_json_bench_limits))
    }
  })
}

///|
test "bench parsed JSON direct admission" (it : @bench.T) {
  let parsed = raw_json_bench_value()
  it.bench(fn() {
    for _ in 0..<1000 {
      it.keep(
        admit_raw_json(parsed, raw_json_bench_span, raw_json_bench_limits),
      )
    }
  })
}
