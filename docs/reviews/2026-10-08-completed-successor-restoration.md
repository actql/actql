# Restore completed descendants in a reconstructed resident holder

An original two-task recovery Run completed Source, producer and consumer exactly once. With the repaired Cloud reconciliation Worker, the consumer's durable completed status was accepted through outbound observations. The next Output plan was relayed to the recreated producer holder, whose in-memory custody contained only the producer. It rejected the consumer plan as `foreign-dispatch`. Common Run routing did not reconstruct the missing descendant. No additional executor entry occurred.

The original Run is `sha256:ddd13a5d0d5704e3b26a06fbd3602d005fad9a332b19aeaffbb208cbfa619da0`. Its consumer dispatch is `sha256:5d52e6d333ae4fed8b9f086c1637f783da2e0d90d29044346237a9c114d551e7`. The failed recovery used Cloud source `19e4057e28800e9b5dd50155cf6cea5c814ea73a`, executable source `2306e226803bb5e40de3866f51469b71f72a50e5`, artifact `sha256:a9bcc998d1dd4cda8a140b6306948aa18f24537b3f6426b13760e862126a13b6`, OSS `556e5c37630284449f390f2fce41438bf2ec90ac`, and Native SHA-256 `746f7d68ba32fb1a9a8dd0304e51963d2ad0fabcb415fecb041f400869af1ba0`. Private receipt identifiers: `completed-holder-original-initial-recovery-7TIE5o` and `completed-holder-original-initial-run-resume-MTW4NJ`. Worker, Native and relay shutdown were confirmed. Journals, payload custody and unresolved release obligations remain preserved.

## Change

The Native holder reads the exact completed consumer envelope and projects its producer through the existing checked retained-input route. A small Native Host role-projection API exposes that selection; it grants no execution, transfer or cleanup authority. Before physical restoration, the caller checks the current exclusive slot, delegation, saved completion/start claimant and original component-holding identity. It then uses `prepare_resident_completed_attempt` and the existing output/input-cleanup Owners. Source, Compute, new attempts and new input borrows are not reachable from restoration.

An already-live consumer owner is retained. Pending restoration keeps the same Runtime in the existing holder custody entry. Failed setup cannot become local cleanup success merely because physical close succeeded: the historical journal must confirm formal release. Descendants keep separate Runtime, input cleanup and component custody, and existing dependency order fences producer cleanup until descendants finish.

## Verification and remaining work

- Based on OSS main `05c6867d2d11915388ea14347a6da6ce29c75bd5`.
- Native focused tests: 23/23 passed (`completed-successor-native-tests-MKqx0Z` / `focused-test-Kn2Tod`). The selection includes the new journal-reopen/checked-edge and failed-restoration cases, completed-output selection, release replay, and stopped retained cleanup. Test sources were dirty at execution and were preserved unchanged for the submitted implementation; source hashes are recorded with the private evidence.
- The earlier bounded executable build reached its 180-second limit without a successful artifact (`completed-successor-native-build-VFVNTv`). A subsequent Native type check passed (`completed-successor-native-check-hk2x3r`); later API and tests were compiled by the successful Native test gate. An early test runner argument failure and two test assertion compilation failures are preserved; they are not test passes.
- The Native interface was regenerated with the existing `moon info` generator (`completed-successor-native-interface-w3r7Tm`). No wire or identity-domain change is introduced.
- Not yet verified: physical descendant restoration through a newly built Native CLI, original-Run ACK/Result/formal release, fresh normal/recovery A/B/C in the final formal cohort, required CI, or actual Preview. These remain completion blockers, not separate closed issues.

Final destination is OSS main. Cloud adoption must use the merged main SHA and matching formal five-package/Native artifacts. Cloud #203/#204 provide the preceding package and query-reconciliation work; their success does not complete this recovery. Historical #88 obligations and the older ProxyWorker HTTP failure remain separate unresolved records.
