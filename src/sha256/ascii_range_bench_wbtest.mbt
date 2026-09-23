///|
let ascii_bench_span : String = "x".repeat(256)

///|
fn hash_ascii_byte_bench() -> Bytes raise HashFailure {
  let h = hasher()
  for _ in 0..<1024 {
    for unit in ascii_bench_span {
      update_byte(h, unit.to_int().to_byte())
    }
  }
  finish_digest(h)
}

///|
fn hash_ascii_range_bench() -> Bytes raise HashFailure {
  let h = hasher()
  for _ in 0..<1024 {
    update_ascii_range(h, ascii_bench_span, 0, ascii_bench_span.length())
  }
  finish_digest(h)
}

///|
test "bench SHA-256 byte updates for 256 KiB ASCII" (it : @bench.T) {
  it.bench(fn() {
    it.keep(
      hash_ascii_byte_bench() catch {
        _ => abort("unexpected hash error")
      },
    )
  })
}

///|
test "bench SHA-256 checked ASCII spans for 256 KiB" (it : @bench.T) {
  it.bench(fn() {
    it.keep(
      hash_ascii_range_bench() catch {
        _ => abort("unexpected hash error")
      },
    )
  })
}
