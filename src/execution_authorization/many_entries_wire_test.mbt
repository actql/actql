///|
/// This independent wire is within both the existing Common limits and the
/// optional 32,768-byte installer ceiling. A physical Host must price its own
/// representation; it cannot reject these entries as a language restriction
/// merely because one selected allocator/profile cannot hold their graph.
test "canonical many-entry Account remains admissible inside a 32768-byte wire" {
  let entries : Array[String] = []
  for index in 0..<210 {
    entries.push(
      "{\"entry_id\":\"e" +
      (1000 + index).to_string() +
      "\",\"outcome\":\"allow\",\"principal\":{\"all\":true},\"connection\":{\"all\":true},\"resource\":{\"all\":true},\"operation\":{\"all\":true},\"exclusions\":[]}",
    )
  }
  let wire = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"original-account\",\"entries\":[" +
    entries.join(",") +
    "]}"
  assert_eq(@utf8.encode(wire).length(), 32642)
  let account = admit_account_configuration_json(wire).unwrap()
  assert_eq(account.account_id(), "original-account")
  assert_eq(account.representation_extent().entry_records, 210L)
}
