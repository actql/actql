///|
let remote_test_checkpoint = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

///|
let remote_test_resolution = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

///|
fn remote_test_answer(decision : String, evidence : String) -> Json {
  {
    "checkpointCid": remote_test_checkpoint,
    "resolutionWire": "{\"checkpoint_cid\":\"\{remote_test_checkpoint}\",\"decision\":\"\{decision}\",\"resolution_cid\":\"\{remote_test_resolution}\"}",
    "approvalEvidenceWire": evidence,
  }
}

///|
test "signed resolution preserves exact checkpoint, decision and resolution identities" {
  assert_eq(
    remote_signed_resolution_binding(remote_test_answer("approved", "{}")),
    (remote_test_checkpoint, remote_test_resolution, "approved"),
  )
  assert_eq(
    remote_signed_resolution_binding(remote_test_answer("rejected", "")),
    (remote_test_checkpoint, remote_test_resolution, "rejected"),
  )
  for
    answer in [
      remote_test_answer("approved", ""),
      remote_test_answer("rejected", "{}"),
      remote_test_answer("unknown", ""),
    ] {
    let refused = try {
      ignore(remote_signed_resolution_binding(answer))
      false
    } catch {
      ClientStop("InvalidCheckpointAnswer") => true
      _ => false
    }
    assert_true(refused)
  }
}

///|
test "signed resolution validates committed, duplicate, refusal, foreign and malformed replies" {
  let answer = remote_test_answer("approved", "{}")
  let request = @utf8.encode(
    Json::object(Map([("items", Json::array([answer]))])).stringify(),
  )
  for status in ["committed", "duplicate"] {
    let reply = "{\"results\":[{\"status\":\"\{status}\",\"checkpointCid\":\"\{remote_test_checkpoint}\",\"decision\":\"approved\",\"resolutionCid\":\"\{remote_test_resolution}\"}]}"
    verify_remote_resolution_reply(request, @utf8.encode(reply), reply, 16384)
  }
  let refusal = "{\"results\":[{\"status\":\"invalid\",\"checkpointCid\":\"\{remote_test_checkpoint}\",\"reason\":\"authorization\"}]}"
  verify_remote_resolution_reply(request, @utf8.encode(refusal), refusal, 16384)
  for
    reply in [
      "{\"results\":[]}",
      "{\"results\":[],\"results\":[{\"status\":\"invalid\",\"checkpointCid\":\"\{remote_test_checkpoint}\",\"reason\":\"authorization\"}]}",
      "{\"results\":[{\"status\":\"committed\",\"checkpointCid\":\"\{remote_test_checkpoint}\",\"decision\":\"approved\",\"resolutionCid\":\"\{remote_test_checkpoint}\"}]}",
      "{\"results\":[{\"status\":\"committed\",\"checkpointCid\":\"\{remote_test_checkpoint}\",\"decision\":\"rejected\",\"resolutionCid\":\"\{remote_test_resolution}\"}]}",
      "{\"results\":[{\"status\":\"invalid\",\"checkpointCid\":\"\{remote_test_checkpoint}\"}]}",
    ] {
    let refused = try {
      verify_remote_resolution_reply(request, @utf8.encode(reply), reply, 16384)
      false
    } catch {
      ClientStop("ResolutionUnknown") => true
      _ => false
    }
    assert_true(refused)
  }
}
