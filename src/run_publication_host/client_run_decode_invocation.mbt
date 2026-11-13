///|
// Each actual decoder invocation owns this sequence. The shared Read callback
// is not itself a replayable handoff token; no pending state survives a call.
fn client_run_decode_invocation(
  callback : (ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ],
) -> (ClientRunJournalConstruction) -> Result[Unit, ClientJournalDecodingIssue] {
  let phase = Ref(0)
  let poisoned = Ref(false)
  let input = Ref(0)
  let pending : Ref[(Int, Int64, Int, Int)?] = Ref(None)
  stage => {
    if poisoned.val {
      return Err(ClientJournalDecodingIssue::CustodyLost)
    }
    let next = match stage {
      RunJournalParse(bytes) if phase.val == 0 && bytes > 0 => {
        input.val = bytes
        1
      }
      RunJournalCanonical(bytes, text, nodes, depth) if phase.val == 1 &&
        bytes == input.val => {
        pending.val = Some((bytes, text, nodes, depth))
        2
      }
      RunJournalRetained(bytes, text, nodes, depth) if phase.val == 2 &&
        pending.val == Some((bytes, text, nodes, depth)) => 3
      _ => {
        phase.val = -1
        poisoned.val = true
        return Err(ClientJournalDecodingIssue::CustodyLost)
      }
    }
    // Refusal and reentrancy terminalize this invocation before calling out.
    phase.val = -1
    match callback(stage) {
      Err(issue) => {
        poisoned.val = true
        Err(issue)
      }
      Ok(_) => {
        if poisoned.val {
          return Err(ClientJournalDecodingIssue::CustodyLost)
        }
        phase.val = next
        Ok(())
      }
    }
  }
}
