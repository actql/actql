// Generated from independent fixed profile preimages. Do not edit.

///|
test "typed JSON serialization identity: json" {
  assert_eq(result_serialization_contract_cid("json", 4096, 16, 4).unwrap(), "sha256:f23fea019c655e7d23cc4636c1c766436ab3002aa24e00348aa8539735b848db")
}

///|
test "typed JSON serialization identity: jsonl" {
  assert_eq(result_serialization_contract_cid("jsonl", 4096, 16, 4).unwrap(), "sha256:61035606b44ad7f4dc24127825bcc46636f40ce5e06881cf9c97996dcb3bde84")
}

///|
test "typed JSON serialization identity: csv" {
  assert_eq(result_serialization_contract_cid("csv", 4096, 16, 4).unwrap(), "sha256:8bd0190f95dc6ae0aedea29755c907fd94ecdb677709b124b0f104fa339e9fd2")
}
