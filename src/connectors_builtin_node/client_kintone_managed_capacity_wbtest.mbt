///|
fn managed_kintone_capacity_original() -> @kintone_host.RecordDeclaration {
  let form = @kintone_catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\"}}}",
    "12",
    client_program_kintone_form_limits(8192, 2000, 24, 16, 512),
  ).unwrap()
  @kintone_host.declare_records(
    form,
    None,
    ["Subject"],
    "kintone",
    "kintone/0.1",
    "rows",
    client_program_kintone_value_limits(16, 512, 2000, 24, 8192),
    client_program_kintone_declaration_limits(200000, 20000, 24, 1, 16),
  ).unwrap()
}

///|
test "managed Kintone complete base keeps actual protocol limits and original geometry" {
  let original = managed_kintone_capacity_original()
  let page = client_program_kintone_page_limits(8192, 2000, 24, 2, 16, 64, 16)
  let values = client_program_kintone_value_limits(16, 512, 2000, 24, 8192)
  let limits = [
    8192, 49152, 2000, 24, 2, 4, 6, 2, 4096, 8192, 512, 2000, 8192, 8192, 2000, 24,
  ]
  let quote = fn(wire, secret, origin) {
    client_program_kintone_managed_source_reader_capacity(
      wire, secret, original, page, values, 1000, 2, 4096, origin, "rows", "",
    )
  }
  let base = quote(limits, 100000, "https://example.cybozu.com").unwrap()
  let retained = @execution.execution_capacity_retained_bytes(base)
  let execution = @execution.execution_capacity_execution_bytes(base)
  assert_true(retained > 0L)
  assert_true(execution >= retained)
  // Fixed declared limits are not substituted with the tiny fixture body.
  assert_true(execution < 536870912L)
  let longer = quote(limits, 100000, "https://longer-example.cybozu.com").unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(longer) > retained)
  assert_true(quote(limits, 0, "https://example.cybozu.com") is None)
  let mismatched = limits.copy()
  mismatched[0] = 8191
  assert_true(quote(mismatched, 100000, "https://example.cybozu.com") is None)
  mismatched[0] = 8192
  mismatched[7] = 1
  assert_true(quote(mismatched, 100000, "https://example.cybozu.com") is None)
  println(
    "Kintone complete initial retained=\{retained} execution=\{execution}",
  )
}

///|
test "Kintone metadata identity is funded in original initialization before caching" {
  let base = @client_local_host.installed_source_child_grant_construction_capacity().unwrap()
  let short = client_program_kintone_metadata_identity_capacity(
    base, 128, 7, 2, 25,
  ).unwrap()
  let longer = client_program_kintone_metadata_identity_capacity(
    base, 129, 7, 2, 25,
  ).unwrap()
  // One extra authored unit has at most six escaped units, four simultaneous
  // UTF16 copies and three UTF8 bytes per output unit: 6*(4*2+3)=66.
  assert_eq(
    @execution.execution_capacity_retained_bytes(longer) -
    @execution.execution_capacity_retained_bytes(short),
    66L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(longer) -
    @execution.execution_capacity_execution_bytes(short),
    66L,
  )
  assert_true(
    client_program_kintone_metadata_identity_capacity(base, -1, 7, 2, 25)
    is None,
  )
}
