///|
test "Mapping references use the published ASCII grammar" {
  for reference in ["mapping:a.v0", "mapping:crm.account/x_y-1.v12"] {
    assert_true(valid_mapping_ref(reference))
  }
  for
    reference in [
      "mapping:.hidden.v1", "mapping:crm.v", "mapping:crm.v1x", "mapping:crmé.v1",
      "mapping:crm space.v1", "mapping:crm.v-1", "command:crm.v1",
    ] {
    assert_true(!valid_mapping_ref(reference))
  }
}

///|
test "Command references use their distinct published ASCII grammar" {
  for reference in ["command:crm.invoke.v1", "command:.internal.v0"] {
    assert_true(valid_command_ref(reference))
  }
  for
    reference in [
      "command:.v1", "command:crm.v", "command:crm@x.v1", "mapping:x.v1",
    ] {
    assert_true(!valid_command_ref(reference))
  }
}
