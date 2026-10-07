///|
let retained_native_chain_document : String =
  #|{"version":"actql/0.1","id":"retained-three-stage","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"middle","inputs":{"x":{"result":{"stage":"acquire","result":"r"}}},"steps":[{"derive":{"n":"id + 10"}},{"select":["n"],"as":"out"}],"results":{"r":{"from":"out","fields":["n"]}}},{"id":"final","inputs":{"x":{"result":{"stage":"middle","result":"r"}}},"steps":[{"derive":{"answer":"n * 2"}},{"select":["answer"],"as":"out"}],"results":{"r":{"from":"out","fields":["answer"]}}}],"results":{"answer":{"from":{"stage":"final","result":"r"}}}}

///|
/// Independently authored expected rows and CIDs for the two Compute outputs.
/// These constants are not derived from an emitted Runtime schema or CID.
fn retained_native_chain_expected(task : Int) -> (String, String, String) {
  match task {
    1 =>
      (
        "[{\"n\":13},{\"n\":11},{\"n\":12}]", "sha256:6495e79b694d6e9c2240123ed4cadce8a5568370ec4d89032438bbf9ce22f628",
        "sha256:5f4e0eff3303f371430ef77d820139fa316f833976ad7f6f0df502db4d8cacb9",
      )
    2 =>
      (
        "[{\"answer\":26},{\"answer\":22},{\"answer\":24}]", "sha256:16f34bd61c9d1eaa64caf382f53063eaa65616019119a64d9c6b70f7cc09caca",
        "sha256:df54c5cfd41f56f2f68bde5711d0519c76a79480e641dee64fb8433d6ba518fa",
      )
    _ => abort("unexpected checked chain task")
  }
}

///|
/// Fixed canonical key order, independent from the product generation helper.
/// The dispatch identifies the actual occurrence; payload and task are fixed
/// expectations for this fixture, not values copied from emitted output facts.
fn retained_native_chain_generation(
  dispatch : @remote.DispatchRequest,
  task : Int,
) -> String {
  let (_, _, content) = retained_native_chain_expected(task)
  let preimage = "{\"dispatch_request_cid\":\"" +
    @remote.dispatch_request_identity(dispatch) +
    "\",\"physical_content_cid\":\"" +
    content +
    "\",\"task\":" +
    task.to_string() +
    ",\"version\":\"actql-native-remote-output-generation/0.1\"}"
  "sha256:" + @sha.text_hex(preimage).unwrap()
}

///|
priv struct RetainedNativeChainContext {
  caller : @host.ClientRequestIdentity
  selected : @host.ClientValuesSiteSelection
  cancel_tail : Bool
}

///|
test "Native retained three-stage chain preserves schemas identities and releases inputs" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    through_consumer_holder=true,
    chain=true,
  )
}

///|
test "Native retained chain cancellation before tail start releases original custody" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    through_consumer_holder=true,
    chain=true,
    cancel_chain_tail=true,
  )
}
