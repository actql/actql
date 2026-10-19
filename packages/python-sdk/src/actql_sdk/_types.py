# Generated from registered ActQL contracts; do not edit.
from __future__ import annotations
from typing import Any, Literal, NotRequired, Required, TypedDict

SubmissionName = str

NamedSubmissionAttempt0AttemptRef = TypedDict("NamedSubmissionAttempt0AttemptRef", {"operation": Required["Literal[\"submit\"]"], "attemptId": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome0SubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome0SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome0SubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome0SubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome0SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome0AdmissionRef = TypedDict("NamedSubmissionAttempt0Outcome0AdmissionRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome0Admission = TypedDict("NamedSubmissionAttempt0Outcome0Admission", {"ref": Required["NamedSubmissionAttempt0Outcome0AdmissionRef"], "durability": Required["Literal[\"volatile\", \"durable\"]"], "revision": Required["int"]}, total=False)

NamedSubmissionAttempt0Outcome0UnresolvedHistorySubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome0UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome0UnresolvedHistorySubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome0UnresolvedHistorySubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome0UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome0UnresolvedHistory = TypedDict("NamedSubmissionAttempt0Outcome0UnresolvedHistory", {"submissionRef": Required["NamedSubmissionAttempt0Outcome0UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

NamedSubmissionAttempt0Outcome0 = TypedDict("NamedSubmissionAttempt0Outcome0", {"kind": Required["Literal[\"ready\"]"], "submissionRef": Required["NamedSubmissionAttempt0Outcome0SubmissionRef"], "intentCid": Required["str"], "admission": Required["NamedSubmissionAttempt0Outcome0Admission"], "unresolvedHistory": NotRequired["NamedSubmissionAttempt0Outcome0UnresolvedHistory"]}, total=False)

NamedSubmissionAttempt0Outcome1SubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome1SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome1SubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome1SubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome1SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome1HeldCheckpoint = TypedDict("NamedSubmissionAttempt0Outcome1HeldCheckpoint", {"checkpointId": Required["str"], "checkpointCid": Required["str"], "kind": Required["Literal[\"run_scope\", \"read_access\", \"data_egress\", \"cost_scope\", \"effect_set\"]"], "expiresAt": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome1Held = TypedDict("NamedSubmissionAttempt0Outcome1Held", {"kind": Required["Literal[\"held\"]"], "requestId": Required["str"], "prepareAttemptId": Required["str"], "state": Required["Literal[\"waiting_checkpoint\", \"resuming\", \"ended\"]"], "durability": Required["Literal[\"durable\"]"], "lookupExpiresAt": Required["str"], "checkpoint": NotRequired["NamedSubmissionAttempt0Outcome1HeldCheckpoint"], "endReason": NotRequired["str"], "terminalErrorCode": NotRequired["str"]}, total=False)

NamedSubmissionAttempt0Outcome1UnresolvedHistorySubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome1UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome1UnresolvedHistorySubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome1UnresolvedHistorySubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome1UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome1UnresolvedHistory = TypedDict("NamedSubmissionAttempt0Outcome1UnresolvedHistory", {"submissionRef": Required["NamedSubmissionAttempt0Outcome1UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

NamedSubmissionAttempt0Outcome1 = TypedDict("NamedSubmissionAttempt0Outcome1", {"kind": Required["Literal[\"held\"]"], "submissionRef": Required["NamedSubmissionAttempt0Outcome1SubmissionRef"], "intentCid": Required["str"], "held": Required["NamedSubmissionAttempt0Outcome1Held"], "unresolvedHistory": NotRequired["NamedSubmissionAttempt0Outcome1UnresolvedHistory"]}, total=False)

NamedSubmissionAttempt0Outcome2SubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome2SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome2SubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome2SubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome2SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome2UnresolvedHistorySubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome2UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome2UnresolvedHistorySubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome2UnresolvedHistorySubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome2UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome2UnresolvedHistory = TypedDict("NamedSubmissionAttempt0Outcome2UnresolvedHistory", {"submissionRef": Required["NamedSubmissionAttempt0Outcome2UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

NamedSubmissionAttempt0Outcome2 = TypedDict("NamedSubmissionAttempt0Outcome2", {"kind": Required["Literal[\"preparing\"]"], "submissionRef": Required["NamedSubmissionAttempt0Outcome2SubmissionRef"], "intentCid": Required["str"], "unresolvedHistory": NotRequired["NamedSubmissionAttempt0Outcome2UnresolvedHistory"]}, total=False)

NamedSubmissionAttempt0Outcome3SubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome3SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome3SubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome3SubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome3SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome3Problem = TypedDict("NamedSubmissionAttempt0Outcome3Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

NamedSubmissionAttempt0Outcome3UnresolvedHistorySubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome3UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome3UnresolvedHistorySubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome3UnresolvedHistorySubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome3UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome3UnresolvedHistory = TypedDict("NamedSubmissionAttempt0Outcome3UnresolvedHistory", {"submissionRef": Required["NamedSubmissionAttempt0Outcome3UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

NamedSubmissionAttempt0Outcome3 = TypedDict("NamedSubmissionAttempt0Outcome3", {"kind": Required["Literal[\"not_accepted\"]"], "submissionRef": Required["NamedSubmissionAttempt0Outcome3SubmissionRef"], "intentCid": Required["str"], "checkObservation": NotRequired["Any"], "problem": Required["NamedSubmissionAttempt0Outcome3Problem"], "unresolvedHistory": NotRequired["NamedSubmissionAttempt0Outcome3UnresolvedHistory"]}, total=False)

NamedSubmissionAttempt0Outcome4SubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome4SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome4SubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome4SubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome4SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome4Problem = TypedDict("NamedSubmissionAttempt0Outcome4Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

NamedSubmissionAttempt0Outcome4UnresolvedHistorySubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome4UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome4UnresolvedHistorySubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome4UnresolvedHistorySubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome4UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome4UnresolvedHistory = TypedDict("NamedSubmissionAttempt0Outcome4UnresolvedHistory", {"submissionRef": Required["NamedSubmissionAttempt0Outcome4UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

NamedSubmissionAttempt0Outcome4 = TypedDict("NamedSubmissionAttempt0Outcome4", {"kind": Required["Literal[\"preparation_failed\"]"], "submissionRef": Required["NamedSubmissionAttempt0Outcome4SubmissionRef"], "intentCid": Required["str"], "checkObservation": NotRequired["Any"], "problem": Required["NamedSubmissionAttempt0Outcome4Problem"], "unresolvedHistory": NotRequired["NamedSubmissionAttempt0Outcome4UnresolvedHistory"]}, total=False)

NamedSubmissionAttempt0Outcome5SubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome5SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome5SubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome5SubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome5SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome5Problem = TypedDict("NamedSubmissionAttempt0Outcome5Problem", {"code": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome5UnresolvedHistorySubmissionRefEpoch = TypedDict("NamedSubmissionAttempt0Outcome5UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome5UnresolvedHistorySubmissionRef = TypedDict("NamedSubmissionAttempt0Outcome5UnresolvedHistorySubmissionRef", {"epoch": Required["NamedSubmissionAttempt0Outcome5UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

NamedSubmissionAttempt0Outcome5UnresolvedHistory = TypedDict("NamedSubmissionAttempt0Outcome5UnresolvedHistory", {"submissionRef": Required["NamedSubmissionAttempt0Outcome5UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

NamedSubmissionAttempt0Outcome5 = TypedDict("NamedSubmissionAttempt0Outcome5", {"kind": Required["Literal[\"unresolvable\"]"], "submissionRef": Required["NamedSubmissionAttempt0Outcome5SubmissionRef"], "problem": Required["NamedSubmissionAttempt0Outcome5Problem"], "unresolvedHistory": NotRequired["NamedSubmissionAttempt0Outcome5UnresolvedHistory"]}, total=False)

NamedSubmissionAttempt0 = TypedDict("NamedSubmissionAttempt0", {"kind": Required["Literal[\"observed\"]"], "requestName": Required["str"], "intentCid": Required["str"], "attemptRef": Required["NamedSubmissionAttempt0AttemptRef"], "outcome": Required["NamedSubmissionAttempt0Outcome0 | NamedSubmissionAttempt0Outcome1 | NamedSubmissionAttempt0Outcome2 | NamedSubmissionAttempt0Outcome3 | NamedSubmissionAttempt0Outcome4 | NamedSubmissionAttempt0Outcome5"]}, total=False)

NamedSubmissionAttempt1AttemptRef = TypedDict("NamedSubmissionAttempt1AttemptRef", {"operation": Required["Literal[\"submit\"]"], "attemptId": Required["str"]}, total=False)

NamedSubmissionAttempt1 = TypedDict("NamedSubmissionAttempt1", {"kind": Required["Literal[\"refused\"]"], "requestName": Required["str"], "intentCid": Required["str"], "attemptRef": Required["NamedSubmissionAttempt1AttemptRef"], "guarantee": Required["Literal[\"attempt_uncommitted_unconsumed\"]"], "reason": Required["Literal[\"authorization\", \"admission_capacity\", \"epoch_expired\", \"epoch_not_yet_valid\"]"]}, total=False)

NamedSubmissionAttempt2AttemptRef = TypedDict("NamedSubmissionAttempt2AttemptRef", {"operation": Required["Literal[\"submit\"]"], "attemptId": Required["str"]}, total=False)

NamedSubmissionAttempt2 = TypedDict("NamedSubmissionAttempt2", {"kind": Required["Literal[\"conflict\"]"], "requestName": Required["str"], "intentCid": Required["str"], "attemptRef": Required["NamedSubmissionAttempt2AttemptRef"], "reason": Required["Literal[\"intent\"]"]}, total=False)

NamedSubmissionAttempt = NamedSubmissionAttempt0 | NamedSubmissionAttempt1 | NamedSubmissionAttempt2

SubmittedIntent = TypedDict("SubmittedIntent", {"kind": Required["Literal[\"program\", \"aql\"]"], "input": Required["dict[str, Any]"], "parameters": Required["None | dict[str, Any]"], "stopBefore": NotRequired["Literal[\"commit\"]"], "readOnly": NotRequired["Literal[True]"]}, total=False)

InstalledEffectContinuationRequestedStop = TypedDict("InstalledEffectContinuationRequestedStop", {"intent_cid": Required["str"]}, total=False)

InstalledEffectContinuation = TypedDict("InstalledEffectContinuation", {"version": Required["Literal[\"actql-installed-effect-continuation/0.1\"]"], "run_definition_cid": Required["str"], "unit_id": Required["str"], "preview_cid": Required["str"], "provider": Required["dict[str, Any]"], "target_read_binding": NotRequired["dict[str, Any]"], "requested_stop": NotRequired["InstalledEffectContinuationRequestedStop"]}, total=False)

SubmissionEpoch = TypedDict("SubmissionEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionRefEpoch = TypedDict("SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionRef = TypedDict("SubmissionRef", {"epoch": Required["SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome0SubmissionRefEpoch = TypedDict("SubmissionOutcome0SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome0SubmissionRef = TypedDict("SubmissionOutcome0SubmissionRef", {"epoch": Required["SubmissionOutcome0SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome0AdmissionRef = TypedDict("SubmissionOutcome0AdmissionRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

SubmissionOutcome0Admission = TypedDict("SubmissionOutcome0Admission", {"ref": Required["SubmissionOutcome0AdmissionRef"], "durability": Required["Literal[\"volatile\", \"durable\"]"], "revision": Required["int"]}, total=False)

SubmissionOutcome0UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionOutcome0UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome0UnresolvedHistorySubmissionRef = TypedDict("SubmissionOutcome0UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionOutcome0UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome0UnresolvedHistory = TypedDict("SubmissionOutcome0UnresolvedHistory", {"submissionRef": Required["SubmissionOutcome0UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionOutcome0 = TypedDict("SubmissionOutcome0", {"kind": Required["Literal[\"ready\"]"], "submissionRef": Required["SubmissionOutcome0SubmissionRef"], "intentCid": Required["str"], "admission": Required["SubmissionOutcome0Admission"], "unresolvedHistory": NotRequired["SubmissionOutcome0UnresolvedHistory"]}, total=False)

SubmissionOutcome1SubmissionRefEpoch = TypedDict("SubmissionOutcome1SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome1SubmissionRef = TypedDict("SubmissionOutcome1SubmissionRef", {"epoch": Required["SubmissionOutcome1SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome1HeldCheckpoint = TypedDict("SubmissionOutcome1HeldCheckpoint", {"checkpointId": Required["str"], "checkpointCid": Required["str"], "kind": Required["Literal[\"run_scope\", \"read_access\", \"data_egress\", \"cost_scope\", \"effect_set\"]"], "expiresAt": Required["str"]}, total=False)

SubmissionOutcome1Held = TypedDict("SubmissionOutcome1Held", {"kind": Required["Literal[\"held\"]"], "requestId": Required["str"], "prepareAttemptId": Required["str"], "state": Required["Literal[\"waiting_checkpoint\", \"resuming\", \"ended\"]"], "durability": Required["Literal[\"durable\"]"], "lookupExpiresAt": Required["str"], "checkpoint": NotRequired["SubmissionOutcome1HeldCheckpoint"], "endReason": NotRequired["str"], "terminalErrorCode": NotRequired["str"]}, total=False)

SubmissionOutcome1UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionOutcome1UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome1UnresolvedHistorySubmissionRef = TypedDict("SubmissionOutcome1UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionOutcome1UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome1UnresolvedHistory = TypedDict("SubmissionOutcome1UnresolvedHistory", {"submissionRef": Required["SubmissionOutcome1UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionOutcome1 = TypedDict("SubmissionOutcome1", {"kind": Required["Literal[\"held\"]"], "submissionRef": Required["SubmissionOutcome1SubmissionRef"], "intentCid": Required["str"], "held": Required["SubmissionOutcome1Held"], "unresolvedHistory": NotRequired["SubmissionOutcome1UnresolvedHistory"]}, total=False)

SubmissionOutcome2SubmissionRefEpoch = TypedDict("SubmissionOutcome2SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome2SubmissionRef = TypedDict("SubmissionOutcome2SubmissionRef", {"epoch": Required["SubmissionOutcome2SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome2UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionOutcome2UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome2UnresolvedHistorySubmissionRef = TypedDict("SubmissionOutcome2UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionOutcome2UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome2UnresolvedHistory = TypedDict("SubmissionOutcome2UnresolvedHistory", {"submissionRef": Required["SubmissionOutcome2UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionOutcome2 = TypedDict("SubmissionOutcome2", {"kind": Required["Literal[\"preparing\"]"], "submissionRef": Required["SubmissionOutcome2SubmissionRef"], "intentCid": Required["str"], "unresolvedHistory": NotRequired["SubmissionOutcome2UnresolvedHistory"]}, total=False)

SubmissionOutcome3SubmissionRefEpoch = TypedDict("SubmissionOutcome3SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome3SubmissionRef = TypedDict("SubmissionOutcome3SubmissionRef", {"epoch": Required["SubmissionOutcome3SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome3Problem = TypedDict("SubmissionOutcome3Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

SubmissionOutcome3UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionOutcome3UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome3UnresolvedHistorySubmissionRef = TypedDict("SubmissionOutcome3UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionOutcome3UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome3UnresolvedHistory = TypedDict("SubmissionOutcome3UnresolvedHistory", {"submissionRef": Required["SubmissionOutcome3UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionOutcome3 = TypedDict("SubmissionOutcome3", {"kind": Required["Literal[\"not_accepted\"]"], "submissionRef": Required["SubmissionOutcome3SubmissionRef"], "intentCid": Required["str"], "checkObservation": NotRequired["Any"], "problem": Required["SubmissionOutcome3Problem"], "unresolvedHistory": NotRequired["SubmissionOutcome3UnresolvedHistory"]}, total=False)

SubmissionOutcome4SubmissionRefEpoch = TypedDict("SubmissionOutcome4SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome4SubmissionRef = TypedDict("SubmissionOutcome4SubmissionRef", {"epoch": Required["SubmissionOutcome4SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome4Problem = TypedDict("SubmissionOutcome4Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

SubmissionOutcome4UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionOutcome4UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionOutcome4UnresolvedHistorySubmissionRef = TypedDict("SubmissionOutcome4UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionOutcome4UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionOutcome4UnresolvedHistory = TypedDict("SubmissionOutcome4UnresolvedHistory", {"submissionRef": Required["SubmissionOutcome4UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionOutcome4 = TypedDict("SubmissionOutcome4", {"kind": Required["Literal[\"preparation_failed\"]"], "submissionRef": Required["SubmissionOutcome4SubmissionRef"], "intentCid": Required["str"], "checkObservation": NotRequired["Any"], "problem": Required["SubmissionOutcome4Problem"], "unresolvedHistory": NotRequired["SubmissionOutcome4UnresolvedHistory"]}, total=False)

SubmissionOutcome = SubmissionOutcome0 | SubmissionOutcome1 | SubmissionOutcome2 | SubmissionOutcome3 | SubmissionOutcome4

SubmissionLookup0SubmissionRefEpoch = TypedDict("SubmissionLookup0SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup0SubmissionRef = TypedDict("SubmissionLookup0SubmissionRef", {"epoch": Required["SubmissionLookup0SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup0AdmissionRef = TypedDict("SubmissionLookup0AdmissionRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

SubmissionLookup0Admission = TypedDict("SubmissionLookup0Admission", {"ref": Required["SubmissionLookup0AdmissionRef"], "durability": Required["Literal[\"volatile\", \"durable\"]"], "revision": Required["int"]}, total=False)

SubmissionLookup0UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionLookup0UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup0UnresolvedHistorySubmissionRef = TypedDict("SubmissionLookup0UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionLookup0UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup0UnresolvedHistory = TypedDict("SubmissionLookup0UnresolvedHistory", {"submissionRef": Required["SubmissionLookup0UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionLookup0 = TypedDict("SubmissionLookup0", {"kind": Required["Literal[\"ready\"]"], "submissionRef": Required["SubmissionLookup0SubmissionRef"], "intentCid": Required["str"], "admission": Required["SubmissionLookup0Admission"], "unresolvedHistory": NotRequired["SubmissionLookup0UnresolvedHistory"]}, total=False)

SubmissionLookup1SubmissionRefEpoch = TypedDict("SubmissionLookup1SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup1SubmissionRef = TypedDict("SubmissionLookup1SubmissionRef", {"epoch": Required["SubmissionLookup1SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup1HeldCheckpoint = TypedDict("SubmissionLookup1HeldCheckpoint", {"checkpointId": Required["str"], "checkpointCid": Required["str"], "kind": Required["Literal[\"run_scope\", \"read_access\", \"data_egress\", \"cost_scope\", \"effect_set\"]"], "expiresAt": Required["str"]}, total=False)

SubmissionLookup1Held = TypedDict("SubmissionLookup1Held", {"kind": Required["Literal[\"held\"]"], "requestId": Required["str"], "prepareAttemptId": Required["str"], "state": Required["Literal[\"waiting_checkpoint\", \"resuming\", \"ended\"]"], "durability": Required["Literal[\"durable\"]"], "lookupExpiresAt": Required["str"], "checkpoint": NotRequired["SubmissionLookup1HeldCheckpoint"], "endReason": NotRequired["str"], "terminalErrorCode": NotRequired["str"]}, total=False)

SubmissionLookup1UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionLookup1UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup1UnresolvedHistorySubmissionRef = TypedDict("SubmissionLookup1UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionLookup1UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup1UnresolvedHistory = TypedDict("SubmissionLookup1UnresolvedHistory", {"submissionRef": Required["SubmissionLookup1UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionLookup1 = TypedDict("SubmissionLookup1", {"kind": Required["Literal[\"held\"]"], "submissionRef": Required["SubmissionLookup1SubmissionRef"], "intentCid": Required["str"], "held": Required["SubmissionLookup1Held"], "unresolvedHistory": NotRequired["SubmissionLookup1UnresolvedHistory"]}, total=False)

SubmissionLookup2SubmissionRefEpoch = TypedDict("SubmissionLookup2SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup2SubmissionRef = TypedDict("SubmissionLookup2SubmissionRef", {"epoch": Required["SubmissionLookup2SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup2UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionLookup2UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup2UnresolvedHistorySubmissionRef = TypedDict("SubmissionLookup2UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionLookup2UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup2UnresolvedHistory = TypedDict("SubmissionLookup2UnresolvedHistory", {"submissionRef": Required["SubmissionLookup2UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionLookup2 = TypedDict("SubmissionLookup2", {"kind": Required["Literal[\"preparing\"]"], "submissionRef": Required["SubmissionLookup2SubmissionRef"], "intentCid": Required["str"], "unresolvedHistory": NotRequired["SubmissionLookup2UnresolvedHistory"]}, total=False)

SubmissionLookup3SubmissionRefEpoch = TypedDict("SubmissionLookup3SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup3SubmissionRef = TypedDict("SubmissionLookup3SubmissionRef", {"epoch": Required["SubmissionLookup3SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup3Problem = TypedDict("SubmissionLookup3Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

SubmissionLookup3UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionLookup3UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup3UnresolvedHistorySubmissionRef = TypedDict("SubmissionLookup3UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionLookup3UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup3UnresolvedHistory = TypedDict("SubmissionLookup3UnresolvedHistory", {"submissionRef": Required["SubmissionLookup3UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionLookup3 = TypedDict("SubmissionLookup3", {"kind": Required["Literal[\"not_accepted\"]"], "submissionRef": Required["SubmissionLookup3SubmissionRef"], "intentCid": Required["str"], "problem": Required["SubmissionLookup3Problem"], "unresolvedHistory": NotRequired["SubmissionLookup3UnresolvedHistory"]}, total=False)

SubmissionLookup4SubmissionRefEpoch = TypedDict("SubmissionLookup4SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup4SubmissionRef = TypedDict("SubmissionLookup4SubmissionRef", {"epoch": Required["SubmissionLookup4SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup4Problem = TypedDict("SubmissionLookup4Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

SubmissionLookup4UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionLookup4UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup4UnresolvedHistorySubmissionRef = TypedDict("SubmissionLookup4UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionLookup4UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup4UnresolvedHistory = TypedDict("SubmissionLookup4UnresolvedHistory", {"submissionRef": Required["SubmissionLookup4UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionLookup4 = TypedDict("SubmissionLookup4", {"kind": Required["Literal[\"preparation_failed\"]"], "submissionRef": Required["SubmissionLookup4SubmissionRef"], "intentCid": Required["str"], "problem": Required["SubmissionLookup4Problem"], "unresolvedHistory": NotRequired["SubmissionLookup4UnresolvedHistory"]}, total=False)

SubmissionLookup5SubmissionRefEpoch = TypedDict("SubmissionLookup5SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup5SubmissionRef = TypedDict("SubmissionLookup5SubmissionRef", {"epoch": Required["SubmissionLookup5SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup5Problem = TypedDict("SubmissionLookup5Problem", {"code": Required["str"]}, total=False)

SubmissionLookup5UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionLookup5UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionLookup5UnresolvedHistorySubmissionRef = TypedDict("SubmissionLookup5UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionLookup5UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionLookup5UnresolvedHistory = TypedDict("SubmissionLookup5UnresolvedHistory", {"submissionRef": Required["SubmissionLookup5UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionLookup5 = TypedDict("SubmissionLookup5", {"kind": Required["Literal[\"unresolvable\"]"], "submissionRef": Required["SubmissionLookup5SubmissionRef"], "problem": Required["SubmissionLookup5Problem"], "unresolvedHistory": NotRequired["SubmissionLookup5UnresolvedHistory"]}, total=False)

SubmissionLookup = SubmissionLookup0 | SubmissionLookup1 | SubmissionLookup2 | SubmissionLookup3 | SubmissionLookup4 | SubmissionLookup5

CancellationRefField = TypedDict("CancellationRefField", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

CancellationCancelRef = TypedDict("CancellationCancelRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

Cancellation = TypedDict("Cancellation", {"ref": Required["CancellationRefField"], "kind": Required["Literal[\"accepted\", \"already_requested\", \"already_terminal\"]"], "revision": Required["int"], "cancelRef": Required["CancellationCancelRef"]}, total=False)

RunRef = TypedDict("RunRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

Connection = TypedDict("Connection", {"mode": Required["Literal[\"local\", \"remote\", \"hybrid\"]"], "owner": Required["Literal[\"local\", \"remote\", \"cloud\"]"], "workspaceId": NotRequired["str"], "consentRefs": Required["list[str]"], "runners": Required["list[str]"], "durability": NotRequired["Literal[\"volatile\", \"durable\"]"], "movementPolicyRef": NotRequired["str"], "cloudConnectionRef": NotRequired["str"]}, total=False)

ProfileSubmissionEpoch = TypedDict("ProfileSubmissionEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

ProfileLimits = TypedDict("ProfileLimits", {"maxReadWireBytes": Required["int"], "maxRowWireBytes": Required["int"], "maxRowRetainedValueBytes": Required["int"], "maxRetainedValueBytes": Required["int"], "maxRows": Required["int"], "maxBatchRows": Required["int"], "maxBatchRetainedValueBytes": Required["int"]}, total=False)

Profile = TypedDict("Profile", {"version": Required["Literal[\"actql-client-host/0.1\"]"], "mode": Required["Literal[\"local\", \"remote\", \"hybrid\"]"], "owner": Required["Literal[\"local\", \"remote\", \"cloud\"]"], "durability": Required["Literal[\"volatile\", \"durable\"]"], "submissionEpoch": NotRequired["ProfileSubmissionEpoch"], "scopeRef": Required["str"], "workspaceId": NotRequired["str"], "capabilities": Required["list[str]"], "limits": Required["ProfileLimits"]}, total=False)

AdmissionRef = TypedDict("AdmissionRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

Admission = TypedDict("Admission", {"ref": Required["AdmissionRef"], "durability": Required["Literal[\"volatile\", \"durable\"]"], "revision": Required["int"]}, total=False)

LookupFoundRef = TypedDict("LookupFoundRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

LookupFound = TypedDict("LookupFound", {"kind": Required["Literal[\"found\"]"], "requestId": Required["str"], "ref": Required["LookupFoundRef"], "durability": Required["Literal[\"volatile\", \"durable\"]"], "lookupExpiresAt": Required["str"]}, total=False)

LookupNotFound = TypedDict("LookupNotFound", {"kind": Required["Literal[\"not_found\"]"]}, total=False)

LookupUnknown = TypedDict("LookupUnknown", {"kind": Required["Literal[\"unknown\"]"], "reason": Required["str"]}, total=False)

HeldCheckpoint = TypedDict("HeldCheckpoint", {"checkpointId": Required["str"], "checkpointCid": Required["str"], "kind": Required["Literal[\"run_scope\", \"read_access\", \"data_egress\", \"cost_scope\", \"effect_set\"]"], "expiresAt": Required["str"]}, total=False)

Held = TypedDict("Held", {"kind": Required["Literal[\"held\"]"], "requestId": Required["str"], "prepareAttemptId": Required["str"], "state": Required["Literal[\"waiting_checkpoint\", \"resuming\", \"ended\"]"], "durability": Required["Literal[\"durable\"]"], "lookupExpiresAt": Required["str"], "checkpoint": NotRequired["HeldCheckpoint"], "endReason": NotRequired["str"], "terminalErrorCode": NotRequired["str"]}, total=False)

CheckpointSummary0Subject0 = TypedDict("CheckpointSummary0Subject0", {"kind": Required["Literal[\"prepare_attempt\"]"], "prepareAttemptId": Required["str"], "requestId": Required["str"]}, total=False)

CheckpointSummary0Subject1 = TypedDict("CheckpointSummary0Subject1", {"kind": Required["Literal[\"run_unit\"]"], "runId": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

CheckpointSummary0RequiredArtifact = TypedDict("CheckpointSummary0RequiredArtifact", {"type": Required["str"], "cid": Required["str"]}, total=False)

CheckpointSummary0 = TypedDict("CheckpointSummary0", {"checkpointId": Required["str"], "checkpointCid": Required["str"], "kind": Required["Literal[\"run_scope\", \"read_access\", \"data_egress\", \"cost_scope\", \"effect_set\"]"], "phase": Required["Literal[\"preflight\", \"commit\"]"], "subject": Required["CheckpointSummary0Subject0 | CheckpointSummary0Subject1"], "requiredArtifact": Required["CheckpointSummary0RequiredArtifact"], "reviewProjectionCid": Required["str"], "requirements": Required["list[str]"], "createdAt": Required["str"], "expiresAt": Required["str"], "humanSummary": Required["str"]}, total=False)

CheckpointSummary1Subject = TypedDict("CheckpointSummary1Subject", {"kind": Required["Literal[\"run_unit\"]"], "runId": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

CheckpointSummary1RequiredArtifact = TypedDict("CheckpointSummary1RequiredArtifact", {"type": Required["Literal[\"model_invocation_scope\"]"], "cid": Required["str"]}, total=False)

CheckpointSummary1 = TypedDict("CheckpointSummary1", {"checkpointId": Required["str"], "checkpointCid": Required["str"], "kind": Required["Literal[\"model_invocation\"]"], "phase": Required["Literal[\"preflight\"]"], "subject": Required["CheckpointSummary1Subject"], "requiredArtifact": Required["CheckpointSummary1RequiredArtifact"], "reviewProjectionCid": Required["str"], "requirements": Required["list[Literal[\"invocation_scope_approved\"]]"], "createdAt": Required["str"], "expiresAt": Required["str"], "humanSummary": Required["str"], "preparedInvocationCid": Required["str"]}, total=False)

CheckpointSummary = CheckpointSummary0 | CheckpointSummary1

CheckpointReview = TypedDict("CheckpointReview", {"kind": Required["Literal[\"review\"]"], "checkpointCid": Required["str"], "artifactCid": Required["str"], "byteLength": Required["int"], "contentBase64": Required["str"]}, total=False)

ResolveItem = TypedDict("ResolveItem", {"checkpointCid": Required["str"], "resolutionWire": Required["str"], "approvalEvidenceWire": Required["str"]}, total=False)

ResolveResult = TypedDict("ResolveResult", {"checkpointCid": Required["str"], "status": Required["Literal[\"committed\", \"duplicate\", \"conflicting\", \"expired\", \"cancelled\", \"invalid\"]"], "decision": NotRequired["Literal[\"approved\", \"rejected\"]"], "resolutionCid": NotRequired["str"], "reason": NotRequired["str"]}, total=False)

RequestCancellationRef = TypedDict("RequestCancellationRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

RequestCancellation = TypedDict("RequestCancellation", {"requestId": Required["str"], "kind": Required["Literal[\"accepted\", \"already_requested\", \"already_terminal\"]"], "ref": NotRequired["RequestCancellationRef"], "revision": NotRequired["int"]}, total=False)

ResourceListingResourcesItem = TypedDict("ResourceListingResourcesItem", {"name": Required["str"], "outcome": Required["str"]}, total=False)

ResourceListing = TypedDict("ResourceListing", {"resourceConnection": Required["str"], "observationCid": Required["str"], "resources": Required["list[ResourceListingResourcesItem]"], "snapshotComplete": Required["bool"], "snapshotTruncated": Required["bool"], "resultTruncated": Required["bool"]}, total=False)

ResourceInspection = TypedDict("ResourceInspection", {"resourceConnection": Required["str"], "resource": Required["str"], "observationCid": Required["str"], "status": Required["Literal[\"ready\", \"catalog_required\"]"], "reason": NotRequired["Literal[\"listing_truncated\", \"not_visible\", \"not_observed\", \"not_found\", \"describe_unavailable\"]"], "summaryJson": NotRequired["str"]}, total=False)

ResourcePeek = TypedDict("ResourcePeek", {"resourceConnection": Required["str"], "resource": Required["str"], "observationCid": Required["str"], "fields": Required["list[str]"], "rowsJson": Required["str"], "limited": Required["bool"]}, total=False)

SubmitPreparationError = TypedDict("SubmitPreparationError", {"code": Required["Literal[\"ClientProgramInvalidInput\", \"ClientParametersInvalid\", \"ClientParametersTooLarge\", \"ClientProgramUnsupported\", \"ClientProgramAnalysisLimit\", \"ClientProgramImplementationLimit\", \"ClientProgramNeedsInputs\", \"ClientProgramRejected\"]"]}, total=False)

ResultDescriptionRef = TypedDict("ResultDescriptionRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

ResultDescriptionColumnsItem = TypedDict("ResultDescriptionColumnsItem", {"name": Required["str"], "contract": Required["ValueContract"]}, total=False)

ResultDescriptionSerialization = TypedDict("ResultDescriptionSerialization", {"format": Required["Literal[\"json\", \"jsonl\", \"csv\"]"], "version": Required["Literal[\"actql-json/0.1\", \"actql-jsonl/0.1\", \"actql-csv/0.1\"]"], "contractCid": Required["str"]}, total=False)

ResultDescription = TypedDict("ResultDescription", {"ref": Required["ResultDescriptionRef"], "resultName": Required["str"], "programDefinitionCid": Required["str"], "resultDefinitionCid": Required["str"], "resultArtifactCid": Required["str"], "resultSchemaCid": Required["str"], "columns": Required["list[ResultDescriptionColumnsItem]"], "serialization": Required["ResultDescriptionSerialization"]}, total=False)

CancellationRef = TypedDict("CancellationRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

CancellationLookup0CancellationRef = TypedDict("CancellationLookup0CancellationRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

CancellationLookup0CancellationCancelRef = TypedDict("CancellationLookup0CancellationCancelRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

CancellationLookup0Cancellation = TypedDict("CancellationLookup0Cancellation", {"ref": Required["CancellationLookup0CancellationRef"], "kind": Required["Literal[\"accepted\", \"already_requested\", \"already_terminal\"]"], "revision": Required["int"], "cancelRef": Required["CancellationLookup0CancellationCancelRef"]}, total=False)

CancellationLookup0 = TypedDict("CancellationLookup0", {"kind": Required["Literal[\"found\"]"], "cancellation": Required["CancellationLookup0Cancellation"]}, total=False)

CancellationLookup1CancelRef = TypedDict("CancellationLookup1CancelRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

CancellationLookup1 = TypedDict("CancellationLookup1", {"kind": Required["Literal[\"unknown\"]"], "cancelRef": Required["CancellationLookup1CancelRef"]}, total=False)

CancellationLookup = CancellationLookup0 | CancellationLookup1

SubmissionRestartSubmissionRefEpoch = TypedDict("SubmissionRestartSubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionRestartSubmissionRef = TypedDict("SubmissionRestartSubmissionRef", {"epoch": Required["SubmissionRestartSubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionRestart = TypedDict("SubmissionRestart", {"submissionRef": Required["SubmissionRestartSubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

OperationAttemptRef = TypedDict("OperationAttemptRef", {"operation": Required["Literal[\"submit\", \"cancel\"]"], "attemptId": Required["str"]}, total=False)

CancellationAttempt0AttemptRef = TypedDict("CancellationAttempt0AttemptRef", {"operation": Required["Literal[\"cancel\"]"], "attemptId": Required["str"]}, total=False)

CancellationAttempt0CancellationRef = TypedDict("CancellationAttempt0CancellationRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

CancellationAttempt0CancellationCancelRef = TypedDict("CancellationAttempt0CancellationCancelRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

CancellationAttempt0Cancellation = TypedDict("CancellationAttempt0Cancellation", {"ref": Required["CancellationAttempt0CancellationRef"], "kind": Required["Literal[\"accepted\"]"], "revision": Required["int"], "cancelRef": Required["CancellationAttempt0CancellationCancelRef"]}, total=False)

CancellationAttempt0 = TypedDict("CancellationAttempt0", {"kind": Required["Literal[\"accepted\"]"], "attemptRef": Required["CancellationAttempt0AttemptRef"], "cancellation": Required["CancellationAttempt0Cancellation"]}, total=False)

CancellationAttempt1AttemptRef = TypedDict("CancellationAttempt1AttemptRef", {"operation": Required["Literal[\"cancel\"]"], "attemptId": Required["str"]}, total=False)

CancellationAttempt1CancellationRef = TypedDict("CancellationAttempt1CancellationRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

CancellationAttempt1CancellationCancelRef = TypedDict("CancellationAttempt1CancellationCancelRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

CancellationAttempt1Cancellation = TypedDict("CancellationAttempt1Cancellation", {"ref": Required["CancellationAttempt1CancellationRef"], "kind": Required["Literal[\"already_requested\", \"already_terminal\"]"], "revision": Required["int"], "cancelRef": Required["CancellationAttempt1CancellationCancelRef"]}, total=False)

CancellationAttempt1 = TypedDict("CancellationAttempt1", {"kind": Required["Literal[\"already_satisfied\"]"], "attemptRef": Required["CancellationAttempt1AttemptRef"], "cancellation": Required["CancellationAttempt1Cancellation"]}, total=False)

CancellationAttempt2AttemptRef = TypedDict("CancellationAttempt2AttemptRef", {"operation": Required["Literal[\"cancel\"]"], "attemptId": Required["str"]}, total=False)

CancellationAttempt2CancelRef = TypedDict("CancellationAttempt2CancelRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

CancellationAttempt2 = TypedDict("CancellationAttempt2", {"kind": Required["Literal[\"refused\"]"], "attemptRef": Required["CancellationAttempt2AttemptRef"], "guarantee": Required["Literal[\"attempt_uncommitted_unconsumed\"]"], "reason": Required["Literal[\"authorization\", \"admission_capacity\"]"], "cancelRef": NotRequired["CancellationAttempt2CancelRef"]}, total=False)

CancellationAttempt3AttemptRef = TypedDict("CancellationAttempt3AttemptRef", {"operation": Required["Literal[\"cancel\"]"], "attemptId": Required["str"]}, total=False)

CancellationAttempt3CancelRef = TypedDict("CancellationAttempt3CancelRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"], "cancelId": Required["str"], "expectedRevision": Required["int"]}, total=False)

CancellationAttempt3 = TypedDict("CancellationAttempt3", {"kind": Required["Literal[\"conflict\"]"], "attemptRef": Required["CancellationAttempt3AttemptRef"], "reason": Required["Literal[\"intent\", \"control_revision\"]"], "cancelRef": Required["CancellationAttempt3CancelRef"]}, total=False)

CancellationAttempt = CancellationAttempt0 | CancellationAttempt1 | CancellationAttempt2 | CancellationAttempt3

SubmissionAttempt0AttemptRef = TypedDict("SubmissionAttempt0AttemptRef", {"operation": Required["Literal[\"submit\"]"], "attemptId": Required["str"]}, total=False)

SubmissionAttempt0Outcome0SubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome0SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome0SubmissionRef = TypedDict("SubmissionAttempt0Outcome0SubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome0SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome0AdmissionRef = TypedDict("SubmissionAttempt0Outcome0AdmissionRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

SubmissionAttempt0Outcome0Admission = TypedDict("SubmissionAttempt0Outcome0Admission", {"ref": Required["SubmissionAttempt0Outcome0AdmissionRef"], "durability": Required["Literal[\"volatile\", \"durable\"]"], "revision": Required["int"]}, total=False)

SubmissionAttempt0Outcome0UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome0UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome0UnresolvedHistorySubmissionRef = TypedDict("SubmissionAttempt0Outcome0UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome0UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome0UnresolvedHistory = TypedDict("SubmissionAttempt0Outcome0UnresolvedHistory", {"submissionRef": Required["SubmissionAttempt0Outcome0UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionAttempt0Outcome0 = TypedDict("SubmissionAttempt0Outcome0", {"kind": Required["Literal[\"ready\"]"], "submissionRef": Required["SubmissionAttempt0Outcome0SubmissionRef"], "intentCid": Required["str"], "admission": Required["SubmissionAttempt0Outcome0Admission"], "unresolvedHistory": NotRequired["SubmissionAttempt0Outcome0UnresolvedHistory"]}, total=False)

SubmissionAttempt0Outcome1SubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome1SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome1SubmissionRef = TypedDict("SubmissionAttempt0Outcome1SubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome1SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome1HeldCheckpoint = TypedDict("SubmissionAttempt0Outcome1HeldCheckpoint", {"checkpointId": Required["str"], "checkpointCid": Required["str"], "kind": Required["Literal[\"run_scope\", \"read_access\", \"data_egress\", \"cost_scope\", \"effect_set\"]"], "expiresAt": Required["str"]}, total=False)

SubmissionAttempt0Outcome1Held = TypedDict("SubmissionAttempt0Outcome1Held", {"kind": Required["Literal[\"held\"]"], "requestId": Required["str"], "prepareAttemptId": Required["str"], "state": Required["Literal[\"waiting_checkpoint\", \"resuming\", \"ended\"]"], "durability": Required["Literal[\"durable\"]"], "lookupExpiresAt": Required["str"], "checkpoint": NotRequired["SubmissionAttempt0Outcome1HeldCheckpoint"], "endReason": NotRequired["str"], "terminalErrorCode": NotRequired["str"]}, total=False)

SubmissionAttempt0Outcome1UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome1UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome1UnresolvedHistorySubmissionRef = TypedDict("SubmissionAttempt0Outcome1UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome1UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome1UnresolvedHistory = TypedDict("SubmissionAttempt0Outcome1UnresolvedHistory", {"submissionRef": Required["SubmissionAttempt0Outcome1UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionAttempt0Outcome1 = TypedDict("SubmissionAttempt0Outcome1", {"kind": Required["Literal[\"held\"]"], "submissionRef": Required["SubmissionAttempt0Outcome1SubmissionRef"], "intentCid": Required["str"], "held": Required["SubmissionAttempt0Outcome1Held"], "unresolvedHistory": NotRequired["SubmissionAttempt0Outcome1UnresolvedHistory"]}, total=False)

SubmissionAttempt0Outcome2SubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome2SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome2SubmissionRef = TypedDict("SubmissionAttempt0Outcome2SubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome2SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome2UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome2UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome2UnresolvedHistorySubmissionRef = TypedDict("SubmissionAttempt0Outcome2UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome2UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome2UnresolvedHistory = TypedDict("SubmissionAttempt0Outcome2UnresolvedHistory", {"submissionRef": Required["SubmissionAttempt0Outcome2UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionAttempt0Outcome2 = TypedDict("SubmissionAttempt0Outcome2", {"kind": Required["Literal[\"preparing\"]"], "submissionRef": Required["SubmissionAttempt0Outcome2SubmissionRef"], "intentCid": Required["str"], "unresolvedHistory": NotRequired["SubmissionAttempt0Outcome2UnresolvedHistory"]}, total=False)

SubmissionAttempt0Outcome3SubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome3SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome3SubmissionRef = TypedDict("SubmissionAttempt0Outcome3SubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome3SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome3Problem = TypedDict("SubmissionAttempt0Outcome3Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

SubmissionAttempt0Outcome3UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome3UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome3UnresolvedHistorySubmissionRef = TypedDict("SubmissionAttempt0Outcome3UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome3UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome3UnresolvedHistory = TypedDict("SubmissionAttempt0Outcome3UnresolvedHistory", {"submissionRef": Required["SubmissionAttempt0Outcome3UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionAttempt0Outcome3 = TypedDict("SubmissionAttempt0Outcome3", {"kind": Required["Literal[\"not_accepted\"]"], "submissionRef": Required["SubmissionAttempt0Outcome3SubmissionRef"], "intentCid": Required["str"], "checkObservation": NotRequired["Any"], "problem": Required["SubmissionAttempt0Outcome3Problem"], "unresolvedHistory": NotRequired["SubmissionAttempt0Outcome3UnresolvedHistory"]}, total=False)

SubmissionAttempt0Outcome4SubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome4SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome4SubmissionRef = TypedDict("SubmissionAttempt0Outcome4SubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome4SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome4Problem = TypedDict("SubmissionAttempt0Outcome4Problem", {"code": Required["str"], "classification": Required["Literal[\"invalid_input\", \"requirements\", \"implementation_limit\", \"authorization\", \"operation_failed\"]"]}, total=False)

SubmissionAttempt0Outcome4UnresolvedHistorySubmissionRefEpoch = TypedDict("SubmissionAttempt0Outcome4UnresolvedHistorySubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt0Outcome4UnresolvedHistorySubmissionRef = TypedDict("SubmissionAttempt0Outcome4UnresolvedHistorySubmissionRef", {"epoch": Required["SubmissionAttempt0Outcome4UnresolvedHistorySubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt0Outcome4UnresolvedHistory = TypedDict("SubmissionAttempt0Outcome4UnresolvedHistory", {"submissionRef": Required["SubmissionAttempt0Outcome4UnresolvedHistorySubmissionRef"], "acknowledgement": Required["Literal[\"possible_prior_execution_and_effects\"]"]}, total=False)

SubmissionAttempt0Outcome4 = TypedDict("SubmissionAttempt0Outcome4", {"kind": Required["Literal[\"preparation_failed\"]"], "submissionRef": Required["SubmissionAttempt0Outcome4SubmissionRef"], "intentCid": Required["str"], "checkObservation": NotRequired["Any"], "problem": Required["SubmissionAttempt0Outcome4Problem"], "unresolvedHistory": NotRequired["SubmissionAttempt0Outcome4UnresolvedHistory"]}, total=False)

SubmissionAttempt0 = TypedDict("SubmissionAttempt0", {"kind": Required["Literal[\"recorded\", \"already_satisfied\"]"], "attemptRef": Required["SubmissionAttempt0AttemptRef"], "outcome": Required["SubmissionAttempt0Outcome0 | SubmissionAttempt0Outcome1 | SubmissionAttempt0Outcome2 | SubmissionAttempt0Outcome3 | SubmissionAttempt0Outcome4"]}, total=False)

SubmissionAttempt1AttemptRef = TypedDict("SubmissionAttempt1AttemptRef", {"operation": Required["Literal[\"submit\"]"], "attemptId": Required["str"]}, total=False)

SubmissionAttempt1 = TypedDict("SubmissionAttempt1", {"kind": Required["Literal[\"refused\"]"], "attemptRef": Required["SubmissionAttempt1AttemptRef"], "guarantee": Required["Literal[\"attempt_uncommitted_unconsumed\"]"], "reason": Required["Literal[\"authorization\"]"]}, total=False)

SubmissionAttempt2AttemptRef = TypedDict("SubmissionAttempt2AttemptRef", {"operation": Required["Literal[\"submit\"]"], "attemptId": Required["str"]}, total=False)

SubmissionAttempt2SubmissionRefEpoch = TypedDict("SubmissionAttempt2SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt2SubmissionRef = TypedDict("SubmissionAttempt2SubmissionRef", {"epoch": Required["SubmissionAttempt2SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt2 = TypedDict("SubmissionAttempt2", {"kind": Required["Literal[\"refused\"]"], "attemptRef": Required["SubmissionAttempt2AttemptRef"], "submissionRef": Required["SubmissionAttempt2SubmissionRef"], "intentCid": Required["str"], "guarantee": Required["Literal[\"attempt_uncommitted_unconsumed\"]"], "reason": Required["Literal[\"admission_capacity\", \"epoch_expired\", \"epoch_not_yet_valid\"]"]}, total=False)

SubmissionAttempt3AttemptRef = TypedDict("SubmissionAttempt3AttemptRef", {"operation": Required["Literal[\"submit\"]"], "attemptId": Required["str"]}, total=False)

SubmissionAttempt3SubmissionRefEpoch = TypedDict("SubmissionAttempt3SubmissionRefEpoch", {"version": Required["Literal[\"actql-submission-epoch/0.1\"]"], "authorityScopeCid": Required["str"], "epochNonce": Required["str"], "notBefore": Required["int"], "expiresAt": Required["int"], "authenticator": Required["str"]}, total=False)

SubmissionAttempt3SubmissionRef = TypedDict("SubmissionAttempt3SubmissionRef", {"epoch": Required["SubmissionAttempt3SubmissionRefEpoch"], "nonce": Required["str"]}, total=False)

SubmissionAttempt3 = TypedDict("SubmissionAttempt3", {"kind": Required["Literal[\"conflict\"]"], "attemptRef": Required["SubmissionAttempt3AttemptRef"], "submissionRef": Required["SubmissionAttempt3SubmissionRef"], "intentCid": Required["str"], "reason": Required["Literal[\"intent\", \"restart_decision\"]"]}, total=False)

SubmissionAttempt = SubmissionAttempt0 | SubmissionAttempt1 | SubmissionAttempt2 | SubmissionAttempt3

OwnerRef = TypedDict("OwnerRef", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerCursorOwner = TypedDict("OwnerCursorOwner", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerCursor = TypedDict("OwnerCursor", {"owner": Required["OwnerCursorOwner"], "value": Required["str"]}, total=False)

OwnerObservationsRef = TypedDict("OwnerObservationsRef", {"namespaceId": Required["str"], "authorityScopeCid": Required["str"], "runDefinitionCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem0Problem = TypedDict("OwnerObservationsOwnersItem0Problem", {"kind": Required["Literal[\"acquisition_failed\", \"limit_exceeded\", \"history_unrecoverable\", \"cursor_mismatch\"]"]}, total=False)

OwnerObservationsOwnersItem0 = TypedDict("OwnerObservationsOwnersItem0", {"owner": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "kind": Required["Literal[\"unavailable\"]"], "problem": NotRequired["OwnerObservationsOwnersItem0Problem"]}, total=False)

OwnerObservationsOwnersItem1OwnerRef = TypedDict("OwnerObservationsOwnersItem1OwnerRef", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem1History0 = TypedDict("OwnerObservationsOwnersItem1History0", {"kind": Required["Literal[\"not_provided\"]"]}, total=False)

OwnerObservationsOwnersItem1History1 = TypedDict("OwnerObservationsOwnersItem1History1", {"kind": Required["Literal[\"retention_expired\"]"]}, total=False)

OwnerObservationsOwnersItem1History2 = TypedDict("OwnerObservationsOwnersItem1History2", {"kind": Required["Literal[\"history_unrecoverable\"]"]}, total=False)

OwnerObservationsOwnersItem1History3 = TypedDict("OwnerObservationsOwnersItem1History3", {"kind": Required["Literal[\"cursor_mismatch\"]"]}, total=False)

OwnerObservationsOwnersItem1History4 = TypedDict("OwnerObservationsOwnersItem1History4", {"kind": Required["Literal[\"cursor_expired\"]"]}, total=False)

OwnerObservationsOwnersItem1History5 = TypedDict("OwnerObservationsOwnersItem1History5", {"kind": Required["Literal[\"limit_exceeded\"]"]}, total=False)

OwnerObservationsOwnersItem1History6 = TypedDict("OwnerObservationsOwnersItem1History6", {"kind": Required["Literal[\"acquisition_failed\"]"]}, total=False)

OwnerObservationsOwnersItem1History7EntriesItem = TypedDict("OwnerObservationsOwnersItem1History7EntriesItem", {"revision": Required["int"], "entryCid": Required["str"], "state": Required["Literal[\"prepared\", \"dispatching\", \"applied\", \"accepted\", \"failed\", \"unknown\"]"]}, total=False)

OwnerObservationsOwnersItem1History7CursorOwner = TypedDict("OwnerObservationsOwnersItem1History7CursorOwner", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem1History7Cursor = TypedDict("OwnerObservationsOwnersItem1History7Cursor", {"owner": Required["OwnerObservationsOwnersItem1History7CursorOwner"], "value": Required["str"]}, total=False)

OwnerObservationsOwnersItem1History7 = TypedDict("OwnerObservationsOwnersItem1History7", {"kind": Required["Literal[\"page\"]"], "entries": Required["list[OwnerObservationsOwnersItem1History7EntriesItem]"], "cursor": NotRequired["OwnerObservationsOwnersItem1History7Cursor"]}, total=False)

OwnerObservationsOwnersItem1Snapshot = TypedDict("OwnerObservationsOwnersItem1Snapshot", {"revision": NotRequired["int"], "value": Required["RunState"]}, total=False)

OwnerObservationsOwnersItem1 = TypedDict("OwnerObservationsOwnersItem1", {"owner": Required["Literal[\"run\"]"], "ownerRef": Required["OwnerObservationsOwnersItem1OwnerRef"], "kind": Required["Literal[\"observed\"]"], "history": Required["OwnerObservationsOwnersItem1History0 | OwnerObservationsOwnersItem1History1 | OwnerObservationsOwnersItem1History2 | OwnerObservationsOwnersItem1History3 | OwnerObservationsOwnersItem1History4 | OwnerObservationsOwnersItem1History5 | OwnerObservationsOwnersItem1History6 | OwnerObservationsOwnersItem1History7"], "snapshot": Required["OwnerObservationsOwnersItem1Snapshot"]}, total=False)

OwnerObservationsOwnersItem2OwnerRef = TypedDict("OwnerObservationsOwnersItem2OwnerRef", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem2History0 = TypedDict("OwnerObservationsOwnersItem2History0", {"kind": Required["Literal[\"not_provided\"]"]}, total=False)

OwnerObservationsOwnersItem2History1 = TypedDict("OwnerObservationsOwnersItem2History1", {"kind": Required["Literal[\"retention_expired\"]"]}, total=False)

OwnerObservationsOwnersItem2History2 = TypedDict("OwnerObservationsOwnersItem2History2", {"kind": Required["Literal[\"history_unrecoverable\"]"]}, total=False)

OwnerObservationsOwnersItem2History3 = TypedDict("OwnerObservationsOwnersItem2History3", {"kind": Required["Literal[\"cursor_mismatch\"]"]}, total=False)

OwnerObservationsOwnersItem2History4 = TypedDict("OwnerObservationsOwnersItem2History4", {"kind": Required["Literal[\"cursor_expired\"]"]}, total=False)

OwnerObservationsOwnersItem2History5 = TypedDict("OwnerObservationsOwnersItem2History5", {"kind": Required["Literal[\"limit_exceeded\"]"]}, total=False)

OwnerObservationsOwnersItem2History6 = TypedDict("OwnerObservationsOwnersItem2History6", {"kind": Required["Literal[\"acquisition_failed\"]"]}, total=False)

OwnerObservationsOwnersItem2History7EntriesItem = TypedDict("OwnerObservationsOwnersItem2History7EntriesItem", {"revision": Required["int"], "entryCid": Required["str"], "state": Required["Literal[\"prepared\", \"dispatching\", \"applied\", \"accepted\", \"failed\", \"unknown\"]"]}, total=False)

OwnerObservationsOwnersItem2History7CursorOwner = TypedDict("OwnerObservationsOwnersItem2History7CursorOwner", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem2History7Cursor = TypedDict("OwnerObservationsOwnersItem2History7Cursor", {"owner": Required["OwnerObservationsOwnersItem2History7CursorOwner"], "value": Required["str"]}, total=False)

OwnerObservationsOwnersItem2History7 = TypedDict("OwnerObservationsOwnersItem2History7", {"kind": Required["Literal[\"page\"]"], "entries": Required["list[OwnerObservationsOwnersItem2History7EntriesItem]"], "cursor": NotRequired["OwnerObservationsOwnersItem2History7Cursor"]}, total=False)

OwnerObservationsOwnersItem2SnapshotProblem = TypedDict("OwnerObservationsOwnersItem2SnapshotProblem", {"kind": Required["Literal[\"limit_exceeded\", \"acquisition_failed\"]"]}, total=False)

OwnerObservationsOwnersItem2 = TypedDict("OwnerObservationsOwnersItem2", {"owner": Required["Literal[\"run\"]"], "ownerRef": Required["OwnerObservationsOwnersItem2OwnerRef"], "kind": Required["Literal[\"observed\"]"], "history": Required["OwnerObservationsOwnersItem2History0 | OwnerObservationsOwnersItem2History1 | OwnerObservationsOwnersItem2History2 | OwnerObservationsOwnersItem2History3 | OwnerObservationsOwnersItem2History4 | OwnerObservationsOwnersItem2History5 | OwnerObservationsOwnersItem2History6 | OwnerObservationsOwnersItem2History7"], "snapshotProblem": Required["OwnerObservationsOwnersItem2SnapshotProblem"]}, total=False)

OwnerObservationsOwnersItem3OwnerRef = TypedDict("OwnerObservationsOwnersItem3OwnerRef", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem3History0 = TypedDict("OwnerObservationsOwnersItem3History0", {"kind": Required["Literal[\"not_provided\"]"]}, total=False)

OwnerObservationsOwnersItem3History1 = TypedDict("OwnerObservationsOwnersItem3History1", {"kind": Required["Literal[\"retention_expired\"]"]}, total=False)

OwnerObservationsOwnersItem3History2 = TypedDict("OwnerObservationsOwnersItem3History2", {"kind": Required["Literal[\"history_unrecoverable\"]"]}, total=False)

OwnerObservationsOwnersItem3History3 = TypedDict("OwnerObservationsOwnersItem3History3", {"kind": Required["Literal[\"cursor_mismatch\"]"]}, total=False)

OwnerObservationsOwnersItem3History4 = TypedDict("OwnerObservationsOwnersItem3History4", {"kind": Required["Literal[\"cursor_expired\"]"]}, total=False)

OwnerObservationsOwnersItem3History5 = TypedDict("OwnerObservationsOwnersItem3History5", {"kind": Required["Literal[\"limit_exceeded\"]"]}, total=False)

OwnerObservationsOwnersItem3History6 = TypedDict("OwnerObservationsOwnersItem3History6", {"kind": Required["Literal[\"acquisition_failed\"]"]}, total=False)

OwnerObservationsOwnersItem3History7EntriesItem = TypedDict("OwnerObservationsOwnersItem3History7EntriesItem", {"revision": Required["int"], "entryCid": Required["str"], "state": Required["Literal[\"prepared\", \"dispatching\", \"applied\", \"accepted\", \"failed\", \"unknown\"]"]}, total=False)

OwnerObservationsOwnersItem3History7CursorOwner = TypedDict("OwnerObservationsOwnersItem3History7CursorOwner", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem3History7Cursor = TypedDict("OwnerObservationsOwnersItem3History7Cursor", {"owner": Required["OwnerObservationsOwnersItem3History7CursorOwner"], "value": Required["str"]}, total=False)

OwnerObservationsOwnersItem3History7 = TypedDict("OwnerObservationsOwnersItem3History7", {"kind": Required["Literal[\"page\"]"], "entries": Required["list[OwnerObservationsOwnersItem3History7EntriesItem]"], "cursor": NotRequired["OwnerObservationsOwnersItem3History7Cursor"]}, total=False)

OwnerObservationsOwnersItem3SnapshotValue = TypedDict("OwnerObservationsOwnersItem3SnapshotValue", {"state": Required["Literal[\"prepared\", \"dispatching\", \"applied\", \"accepted\", \"failed\", \"unknown\"]"]}, total=False)

OwnerObservationsOwnersItem3Snapshot = TypedDict("OwnerObservationsOwnersItem3Snapshot", {"revision": NotRequired["int"], "value": Required["OwnerObservationsOwnersItem3SnapshotValue"]}, total=False)

OwnerObservationsOwnersItem3 = TypedDict("OwnerObservationsOwnersItem3", {"owner": Required["Literal[\"effect\"]"], "ownerRef": Required["OwnerObservationsOwnersItem3OwnerRef"], "kind": Required["Literal[\"observed\"]"], "history": Required["OwnerObservationsOwnersItem3History0 | OwnerObservationsOwnersItem3History1 | OwnerObservationsOwnersItem3History2 | OwnerObservationsOwnersItem3History3 | OwnerObservationsOwnersItem3History4 | OwnerObservationsOwnersItem3History5 | OwnerObservationsOwnersItem3History6 | OwnerObservationsOwnersItem3History7"], "snapshot": Required["OwnerObservationsOwnersItem3Snapshot"]}, total=False)

OwnerObservationsOwnersItem4OwnerRef = TypedDict("OwnerObservationsOwnersItem4OwnerRef", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem4History0 = TypedDict("OwnerObservationsOwnersItem4History0", {"kind": Required["Literal[\"not_provided\"]"]}, total=False)

OwnerObservationsOwnersItem4History1 = TypedDict("OwnerObservationsOwnersItem4History1", {"kind": Required["Literal[\"retention_expired\"]"]}, total=False)

OwnerObservationsOwnersItem4History2 = TypedDict("OwnerObservationsOwnersItem4History2", {"kind": Required["Literal[\"history_unrecoverable\"]"]}, total=False)

OwnerObservationsOwnersItem4History3 = TypedDict("OwnerObservationsOwnersItem4History3", {"kind": Required["Literal[\"cursor_mismatch\"]"]}, total=False)

OwnerObservationsOwnersItem4History4 = TypedDict("OwnerObservationsOwnersItem4History4", {"kind": Required["Literal[\"cursor_expired\"]"]}, total=False)

OwnerObservationsOwnersItem4History5 = TypedDict("OwnerObservationsOwnersItem4History5", {"kind": Required["Literal[\"limit_exceeded\"]"]}, total=False)

OwnerObservationsOwnersItem4History6 = TypedDict("OwnerObservationsOwnersItem4History6", {"kind": Required["Literal[\"acquisition_failed\"]"]}, total=False)

OwnerObservationsOwnersItem4History7EntriesItem = TypedDict("OwnerObservationsOwnersItem4History7EntriesItem", {"revision": Required["int"], "entryCid": Required["str"], "state": Required["Literal[\"prepared\", \"dispatching\", \"applied\", \"accepted\", \"failed\", \"unknown\"]"]}, total=False)

OwnerObservationsOwnersItem4History7CursorOwner = TypedDict("OwnerObservationsOwnersItem4History7CursorOwner", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsOwnersItem4History7Cursor = TypedDict("OwnerObservationsOwnersItem4History7Cursor", {"owner": Required["OwnerObservationsOwnersItem4History7CursorOwner"], "value": Required["str"]}, total=False)

OwnerObservationsOwnersItem4History7 = TypedDict("OwnerObservationsOwnersItem4History7", {"kind": Required["Literal[\"page\"]"], "entries": Required["list[OwnerObservationsOwnersItem4History7EntriesItem]"], "cursor": NotRequired["OwnerObservationsOwnersItem4History7Cursor"]}, total=False)

OwnerObservationsOwnersItem4SnapshotProblem = TypedDict("OwnerObservationsOwnersItem4SnapshotProblem", {"kind": Required["Literal[\"limit_exceeded\", \"acquisition_failed\"]"]}, total=False)

OwnerObservationsOwnersItem4 = TypedDict("OwnerObservationsOwnersItem4", {"owner": Required["Literal[\"effect\"]"], "ownerRef": Required["OwnerObservationsOwnersItem4OwnerRef"], "kind": Required["Literal[\"observed\"]"], "history": Required["OwnerObservationsOwnersItem4History0 | OwnerObservationsOwnersItem4History1 | OwnerObservationsOwnersItem4History2 | OwnerObservationsOwnersItem4History3 | OwnerObservationsOwnersItem4History4 | OwnerObservationsOwnersItem4History5 | OwnerObservationsOwnersItem4History6 | OwnerObservationsOwnersItem4History7"], "snapshotProblem": Required["OwnerObservationsOwnersItem4SnapshotProblem"]}, total=False)

OwnerObservationsRevisionVectorItemOwner = TypedDict("OwnerObservationsRevisionVectorItemOwner", {"kind": Required["Literal[\"run\", \"effect\", \"publication\", \"delivery\", \"site\"]"], "scopeCid": Required["str"], "streamCid": Required["str"]}, total=False)

OwnerObservationsRevisionVectorItemHistoryHead1 = TypedDict("OwnerObservationsRevisionVectorItemHistoryHead1", {"generation": Required["str"], "revision": Required["int"], "entryCid": Required["str"]}, total=False)

OwnerObservationsRevisionVectorItem = TypedDict("OwnerObservationsRevisionVectorItem", {"owner": Required["OwnerObservationsRevisionVectorItemOwner"], "snapshotCid": NotRequired["str"], "historyHead": NotRequired["None | OwnerObservationsRevisionVectorItemHistoryHead1"]}, total=False)

OwnerObservationsUnmatchedCursorsItem = TypedDict("OwnerObservationsUnmatchedCursorsItem", {"index": Required["int"], "kind": Required["Literal[\"unavailable\"]"]}, total=False)

OwnerObservations = TypedDict("OwnerObservations", {"ref": Required["OwnerObservationsRef"], "consistency": Required["Literal[\"non_atomic\"]"], "ordering": Required["Literal[\"owner_local\"]"], "owners": Required["list[OwnerObservationsOwnersItem0 | OwnerObservationsOwnersItem1 | OwnerObservationsOwnersItem2 | OwnerObservationsOwnersItem3 | OwnerObservationsOwnersItem4]"], "revisionVector": Required["list[OwnerObservationsRevisionVectorItem]"], "unmatchedCursors": NotRequired["list[OwnerObservationsUnmatchedCursorsItem]"]}, total=False)

RunStateCheckpoint = TypedDict("RunStateCheckpoint", {"checkpoint_id": Required["str"], "checkpoint_cid": Required["str"], "kind": Required["Literal[\"run_scope\", \"read_access\", \"data_egress\", \"cost_scope\", \"effect_set\", \"model_invocation\"]"]}, total=False)

RunStateNextAction0 = TypedDict("RunStateNextAction0", {"kind": Required["Literal[\"resolve_checkpoint\"]"], "checkpoint_id": Required["str"]}, total=False)

RunStateNextAction1 = TypedDict("RunStateNextAction1", {"kind": Required["Literal[\"reconcile\"]"], "effects": Required["list[str]"]}, total=False)

RunStateNextAction2 = TypedDict("RunStateNextAction2", {"kind": Required["Literal[\"read_result\"]"], "results": Required["list[str]"]}, total=False)

RunStateNextAction3 = TypedDict("RunStateNextAction3", {"kind": Required["Literal[\"refresh_availability\"]"], "results": Required["list[str]"]}, total=False)

RunStateNextAction4 = TypedDict("RunStateNextAction4", {"kind": Required["Literal[\"none\"]"]}, total=False)

RunStateNextAction5 = TypedDict("RunStateNextAction5", {"kind": Required["Literal[\"reconcile_run\"]"], "reason": Required["Literal[\"execution_unknown\"]"]}, total=False)

RunStateTerminalError = TypedDict("RunStateTerminalError", {"code": Required["str"], "message": Required["str"]}, total=False)

RunStateResultAvailabilityValue = TypedDict("RunStateResultAvailabilityValue", {"state": Required["Literal[\"available\", \"unavailable\", \"unknown\"]"], "observed_at": Required["str"], "reason": Required["Literal[\"confirmed_present\", \"retention_expired\", \"deleted\", \"policy_unavailable\", \"integrity_failed\", \"not_published\", \"store_query_failed\", \"clock_uncertain\", \"verification_pending\"]"], "cause_cid": NotRequired["str"]}, total=False)

RunStateControl = TypedDict("RunStateControl", {"revision": Required["int"], "cancellation_requested": Required["bool"], "physical_stop": Required["Literal[\"unknown\", \"confirmed\"]"]}, total=False)

RunState = TypedDict("RunState", {"version": Required["Literal[\"actql-run-state/0.1\"]"], "run_id": Required["str"], "status": Required["Literal[\"preparing\", \"running\", \"waiting_checkpoint\", \"resuming\", \"needs_reconciliation\", \"succeeded\", \"failed\", \"cancelled\"]"], "updated_at": Required["str"], "checkpoint": NotRequired["RunStateCheckpoint"], "next_action": Required["RunStateNextAction0 | RunStateNextAction1 | RunStateNextAction2 | RunStateNextAction3 | RunStateNextAction4 | RunStateNextAction5"], "result_available": Required["bool"], "terminal_error": NotRequired["RunStateTerminalError"], "result_availability": Required["dict[str, RunStateResultAvailabilityValue]"], "control": NotRequired["RunStateControl"], "revision": Required["int"]}, total=False)

CheckOutcome0ReportRunnableReasonsItem = TypedDict("CheckOutcome0ReportRunnableReasonsItem", {"code": Required["str"]}, total=False)

CheckOutcome0ReportRunnable = TypedDict("CheckOutcome0ReportRunnable", {"verdict": Required["Literal[\"yes\", \"no\"]"], "reasons": Required["list[CheckOutcome0ReportRunnableReasonsItem]"]}, total=False)

CheckOutcome0ReportOmissions = TypedDict("CheckOutcome0ReportOmissions", {"requirements": Required["Literal[True]"]}, total=False)

CheckOutcome0ReportInputsItem = TypedDict("CheckOutcome0ReportInputsItem", {"document_id": Required["Literal[\"source\", \"program\", \"parameter_declarations\", \"parameters\"]"], "revision": Required["str"], "kind": Required["Literal[\"text\", \"structured\"]"], "byte_length": Required["int"]}, total=False)

CheckOutcome0ReportCoverageLimitsItem0 = TypedDict("CheckOutcome0ReportCoverageLimitsItem0", {"code": Required["str"]}, total=False)

CheckOutcome0ReportCoverageLimitsItem1Location = TypedDict("CheckOutcome0ReportCoverageLimitsItem1Location", {"kind": Required["Literal[\"structured\"]"], "document_id": Required["Literal[\"program\"]"], "revision": Required["str"], "pointer": Required["str"]}, total=False)

CheckOutcome0ReportCoverageLimitsItem1 = TypedDict("CheckOutcome0ReportCoverageLimitsItem1", {"code": Required["Literal[\"implementation_limit\", \"analysis_budget_exhausted\"]"], "location": Required["CheckOutcome0ReportCoverageLimitsItem1Location"]}, total=False)

CheckOutcome0ReportCoverageLimitsItem2Facts = TypedDict("CheckOutcome0ReportCoverageLimitsItem2Facts", {"issue": Required["Literal[\"function_lowering_unresolved\"]"]}, total=False)

CheckOutcome0ReportCoverageLimitsItem2Location = TypedDict("CheckOutcome0ReportCoverageLimitsItem2Location", {"kind": Required["Literal[\"text\"]"], "document_id": Required["Literal[\"source\"]"], "revision": Required["str"], "start_byte": Required["int"], "end_byte": Required["int"], "precision": Required["Literal[\"exact\", \"approximate\"]"]}, total=False)

CheckOutcome0ReportCoverageLimitsItem2 = TypedDict("CheckOutcome0ReportCoverageLimitsItem2", {"code": Required["Literal[\"implementation_limit\"]"], "facts": Required["CheckOutcome0ReportCoverageLimitsItem2Facts"], "location": NotRequired["CheckOutcome0ReportCoverageLimitsItem2Location"]}, total=False)

CheckOutcome0ReportCoverageUnresolvedItem = TypedDict("CheckOutcome0ReportCoverageUnresolvedItem", {"boundary": Required["str"], "reason": Required["Literal[\"unresolved_protected\"]"]}, total=False)

CheckOutcome0ReportCoverage = TypedDict("CheckOutcome0ReportCoverage", {"limits": Required["list[CheckOutcome0ReportCoverageLimitsItem0 | CheckOutcome0ReportCoverageLimitsItem1 | CheckOutcome0ReportCoverageLimitsItem2]"], "unresolved": Required["list[CheckOutcome0ReportCoverageUnresolvedItem]"]}, total=False)

CheckOutcome0ReportReasonsItemLocation0 = TypedDict("CheckOutcome0ReportReasonsItemLocation0", {"kind": Required["Literal[\"text\"]"], "document_id": Required["Literal[\"source\"]"], "revision": Required["str"], "start_byte": Required["int"], "end_byte": Required["int"], "precision": Required["Literal[\"exact\", \"approximate\"]"]}, total=False)

CheckOutcome0ReportReasonsItemLocation1 = TypedDict("CheckOutcome0ReportReasonsItemLocation1", {"kind": Required["Literal[\"structured\"]"], "document_id": Required["Literal[\"program\", \"parameter_declarations\", \"parameters\"]"], "revision": Required["str"], "pointer": Required["str"]}, total=False)

CheckOutcome0ReportReasonsItemFixesItemTarget = TypedDict("CheckOutcome0ReportReasonsItemFixesItemTarget", {"document_id": Required["Literal[\"source\"]"], "revision": Required["str"]}, total=False)

CheckOutcome0ReportReasonsItemFixesItemEditsItem = TypedDict("CheckOutcome0ReportReasonsItemFixesItemEditsItem", {"start_byte": Required["int"], "end_byte": Required["int"], "replacement": Required["Literal[\"*/\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFixesItem = TypedDict("CheckOutcome0ReportReasonsItemFixesItem", {"code": Required["Literal[\"close_block_comment\"]"], "applicability": Required["Literal[\"requires_review\"]"], "risk": Required["Literal[\"syntax_structure\"]"], "target": Required["CheckOutcome0ReportReasonsItemFixesItemTarget"], "edits": Required["list[CheckOutcome0ReportReasonsItemFixesItemEditsItem]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts0 = TypedDict("CheckOutcome0ReportReasonsItemFacts0", {"parameter": Required["str"]}, total=False)

CheckOutcome0ReportReasonsItemFacts1 = TypedDict("CheckOutcome0ReportReasonsItemFacts1", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "actual_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0PathItem0 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0PathItem1 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0", {"kind": Required["Literal[\"numeric\"]"], "path": Required["list[CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0PathItem0 | CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0PathItem1]"], "integer": Required["bool"], "minimum": NotRequired["int | float"], "maximum": NotRequired["int | float"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1PathItem0 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1PathItem1 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1", {"kind": Required["Literal[\"duration\"]"], "path": Required["list[CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1PathItem0 | CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1PathItem1]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2PathItem0 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2PathItem1 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2 = TypedDict("CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2", {"kind": Required["Literal[\"array_length\"]"], "path": Required["list[CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2PathItem0 | CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2PathItem1]"], "length": Required["int"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2Admission = TypedDict("CheckOutcome0ReportReasonsItemFacts2Admission", {"contract_schema_cid": Required["Literal[\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"]"], "kind": Required["Literal[\"parameter_declaration\"]"], "contract": Required["ValueContract"], "supplier": Required["Literal[\"caller\"]"], "constraints": Required["list[CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem0 | CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem1 | CheckOutcome0ReportReasonsItemFacts2AdmissionConstraintsItem2]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts2 = TypedDict("CheckOutcome0ReportReasonsItemFacts2", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "admission": NotRequired["CheckOutcome0ReportReasonsItemFacts2Admission"]}, total=False)

CheckOutcome0ReportReasonsItemFacts3 = TypedDict("CheckOutcome0ReportReasonsItemFacts3", {"parameter": Required["str"], "constraint": Required["Literal[\"numeric\", \"duration\", \"array_length\", \"array_size\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts4 = TypedDict("CheckOutcome0ReportReasonsItemFacts4", {"expected_type": Required["Literal[\"number\", \"boolean\", \"string\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts5 = TypedDict("CheckOutcome0ReportReasonsItemFacts5", {"parameter": Required["str"], "domain": Required["Literal[\"positive_safe_integer\", \"nonnegative_safe_integer\", \"unit_fraction\", \"finite_number\", \"duration\", \"positive_milliseconds\", \"signed_milliseconds\", \"timestamp\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts6 = TypedDict("CheckOutcome0ReportReasonsItemFacts6", {"operation": Required["Literal[\"components\"]"], "issue": Required["Literal[\"invalid_kind\", \"invalid_output_rows\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts7 = TypedDict("CheckOutcome0ReportReasonsItemFacts7", {"operation": Required["Literal[\"subgraph\"]"], "issue": Required["Literal[\"invalid_node_selector\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts8 = TypedDict("CheckOutcome0ReportReasonsItemFacts8", {"document": Required["Literal[\"parameters\", \"parameter_declarations\"]"], "issue": Required["Literal[\"invalid_unicode\", \"unexpected_end\", \"unexpected_token\", \"invalid_string\", \"invalid_escape\", \"invalid_number\", \"number_out_of_range\", \"negative_zero\", \"expected_colon\", \"expected_array_separator\", \"expected_object_separator\", \"duplicate_key\", \"trailing_content\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts9 = TypedDict("CheckOutcome0ReportReasonsItemFacts9", {"issue": Required["Literal[\"unexpected_end\", \"unexpected_token\", \"invalid_escape\", \"invalid_scalar\", \"empty_identifier\", \"unterminated_comment\", \"invalid_number\", \"invalid_parameter\", \"unknown_reference\", \"invalid_arguments\", \"expected_boolean\", \"invalid_bounds\", \"function_lowering_unresolved\", \"missing_field\", \"wrong_type\", \"unexpected_null\", \"invalid_structure\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts10 = TypedDict("CheckOutcome0ReportReasonsItemFacts10", {"contract_cid": Required["Literal[\"sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9\"]"], "schema_cid": Required["Literal[\"sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265\"]"], "schema_pointer": Required["Literal[\"/schema\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts11 = TypedDict("CheckOutcome0ReportReasonsItemFacts11", {"profile_cid": Required["Literal[\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts12 = TypedDict("CheckOutcome0ReportReasonsItemFacts12", {"namespace": Required["str"], "connector": Required["str"], "resource": Required["str"], "view": NotRequired["str"]}, total=False)

CheckOutcome0ReportReasonsItemFacts13ReferenceItem = TypedDict("CheckOutcome0ReportReasonsItemFacts13ReferenceItem", {"value": Required["str"], "quoted": Required["bool"]}, total=False)

CheckOutcome0ReportReasonsItemFacts13 = TypedDict("CheckOutcome0ReportReasonsItemFacts13", {"namespace": Required["str"], "reference": Required["list[CheckOutcome0ReportReasonsItemFacts13ReferenceItem]"]}, total=False)

CheckOutcome0ReportReasonsItemFacts14 = TypedDict("CheckOutcome0ReportReasonsItemFacts14", {"argument": Required["Literal[\"count\", \"offset\"]"], "constraint": Required["Literal[\"safe_integer\"]"], "expected_type": Required["Literal[\"number\", \"int64\"]"], "maximum": Required["Literal[9007199254740991]"], "minimum": Required["Literal[0, 1]"], "operation": Required["Literal[\"take\"]"], "parameter": Required["str"], "stage": Required["Literal[\"binding\"]"]}, total=False)

CheckOutcome0ReportReasonsItem = TypedDict("CheckOutcome0ReportReasonsItem", {"code": Required["str"], "location": NotRequired["CheckOutcome0ReportReasonsItemLocation0 | CheckOutcome0ReportReasonsItemLocation1"], "fixes": NotRequired["list[CheckOutcome0ReportReasonsItemFixesItem]"], "facts": NotRequired["CheckOutcome0ReportReasonsItemFacts0 | CheckOutcome0ReportReasonsItemFacts1 | CheckOutcome0ReportReasonsItemFacts2 | CheckOutcome0ReportReasonsItemFacts3 | CheckOutcome0ReportReasonsItemFacts4 | CheckOutcome0ReportReasonsItemFacts5 | CheckOutcome0ReportReasonsItemFacts6 | CheckOutcome0ReportReasonsItemFacts7 | CheckOutcome0ReportReasonsItemFacts8 | CheckOutcome0ReportReasonsItemFacts9 | CheckOutcome0ReportReasonsItemFacts10 | CheckOutcome0ReportReasonsItemFacts11 | CheckOutcome0ReportReasonsItemFacts12 | CheckOutcome0ReportReasonsItemFacts13 | CheckOutcome0ReportReasonsItemFacts14"]}, total=False)

CheckOutcome0ReportRequirementsItemLocation0 = TypedDict("CheckOutcome0ReportRequirementsItemLocation0", {"kind": Required["Literal[\"text\"]"], "document_id": Required["Literal[\"source\"]"], "revision": Required["str"], "start_byte": Required["int"], "end_byte": Required["int"], "precision": Required["Literal[\"exact\", \"approximate\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemLocation1 = TypedDict("CheckOutcome0ReportRequirementsItemLocation1", {"kind": Required["Literal[\"structured\"]"], "document_id": Required["Literal[\"program\", \"parameter_declarations\", \"parameters\"]"], "revision": Required["str"], "pointer": Required["str"]}, total=False)

CheckOutcome0ReportRequirementsItemFixesItemTarget = TypedDict("CheckOutcome0ReportRequirementsItemFixesItemTarget", {"document_id": Required["Literal[\"source\"]"], "revision": Required["str"]}, total=False)

CheckOutcome0ReportRequirementsItemFixesItemEditsItem = TypedDict("CheckOutcome0ReportRequirementsItemFixesItemEditsItem", {"start_byte": Required["int"], "end_byte": Required["int"], "replacement": Required["Literal[\"*/\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFixesItem = TypedDict("CheckOutcome0ReportRequirementsItemFixesItem", {"code": Required["Literal[\"close_block_comment\"]"], "applicability": Required["Literal[\"requires_review\"]"], "risk": Required["Literal[\"syntax_structure\"]"], "target": Required["CheckOutcome0ReportRequirementsItemFixesItemTarget"], "edits": Required["list[CheckOutcome0ReportRequirementsItemFixesItemEditsItem]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts0 = TypedDict("CheckOutcome0ReportRequirementsItemFacts0", {"parameter": Required["str"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts1 = TypedDict("CheckOutcome0ReportRequirementsItemFacts1", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "actual_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem0 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem1 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0", {"kind": Required["Literal[\"numeric\"]"], "path": Required["list[CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem0 | CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem1]"], "integer": Required["bool"], "minimum": NotRequired["int | float"], "maximum": NotRequired["int | float"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem0 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem1 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1", {"kind": Required["Literal[\"duration\"]"], "path": Required["list[CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem0 | CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem1]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem0 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem1 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2", {"kind": Required["Literal[\"array_length\"]"], "path": Required["list[CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem0 | CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem1]"], "length": Required["int"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2Admission = TypedDict("CheckOutcome0ReportRequirementsItemFacts2Admission", {"contract_schema_cid": Required["Literal[\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"]"], "kind": Required["Literal[\"parameter_declaration\"]"], "contract": Required["ValueContract"], "supplier": Required["Literal[\"caller\"]"], "constraints": Required["list[CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem0 | CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem1 | CheckOutcome0ReportRequirementsItemFacts2AdmissionConstraintsItem2]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts2 = TypedDict("CheckOutcome0ReportRequirementsItemFacts2", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "admission": NotRequired["CheckOutcome0ReportRequirementsItemFacts2Admission"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts3 = TypedDict("CheckOutcome0ReportRequirementsItemFacts3", {"parameter": Required["str"], "constraint": Required["Literal[\"numeric\", \"duration\", \"array_length\", \"array_size\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts4 = TypedDict("CheckOutcome0ReportRequirementsItemFacts4", {"expected_type": Required["Literal[\"number\", \"boolean\", \"string\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts5 = TypedDict("CheckOutcome0ReportRequirementsItemFacts5", {"parameter": Required["str"], "domain": Required["Literal[\"positive_safe_integer\", \"nonnegative_safe_integer\", \"unit_fraction\", \"finite_number\", \"duration\", \"positive_milliseconds\", \"signed_milliseconds\", \"timestamp\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts6 = TypedDict("CheckOutcome0ReportRequirementsItemFacts6", {"operation": Required["Literal[\"components\"]"], "issue": Required["Literal[\"invalid_kind\", \"invalid_output_rows\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts7 = TypedDict("CheckOutcome0ReportRequirementsItemFacts7", {"operation": Required["Literal[\"subgraph\"]"], "issue": Required["Literal[\"invalid_node_selector\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts8 = TypedDict("CheckOutcome0ReportRequirementsItemFacts8", {"document": Required["Literal[\"parameters\", \"parameter_declarations\"]"], "issue": Required["Literal[\"invalid_unicode\", \"unexpected_end\", \"unexpected_token\", \"invalid_string\", \"invalid_escape\", \"invalid_number\", \"number_out_of_range\", \"negative_zero\", \"expected_colon\", \"expected_array_separator\", \"expected_object_separator\", \"duplicate_key\", \"trailing_content\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts9 = TypedDict("CheckOutcome0ReportRequirementsItemFacts9", {"issue": Required["Literal[\"unexpected_end\", \"unexpected_token\", \"invalid_escape\", \"invalid_scalar\", \"empty_identifier\", \"unterminated_comment\", \"invalid_number\", \"invalid_parameter\", \"unknown_reference\", \"invalid_arguments\", \"expected_boolean\", \"invalid_bounds\", \"function_lowering_unresolved\", \"missing_field\", \"wrong_type\", \"unexpected_null\", \"invalid_structure\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts10 = TypedDict("CheckOutcome0ReportRequirementsItemFacts10", {"contract_cid": Required["Literal[\"sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9\"]"], "schema_cid": Required["Literal[\"sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265\"]"], "schema_pointer": Required["Literal[\"/schema\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts11 = TypedDict("CheckOutcome0ReportRequirementsItemFacts11", {"profile_cid": Required["Literal[\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts12 = TypedDict("CheckOutcome0ReportRequirementsItemFacts12", {"namespace": Required["str"], "connector": Required["str"], "resource": Required["str"], "view": NotRequired["str"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts13ReferenceItem = TypedDict("CheckOutcome0ReportRequirementsItemFacts13ReferenceItem", {"value": Required["str"], "quoted": Required["bool"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts13 = TypedDict("CheckOutcome0ReportRequirementsItemFacts13", {"namespace": Required["str"], "reference": Required["list[CheckOutcome0ReportRequirementsItemFacts13ReferenceItem]"]}, total=False)

CheckOutcome0ReportRequirementsItemFacts14 = TypedDict("CheckOutcome0ReportRequirementsItemFacts14", {"argument": Required["Literal[\"count\", \"offset\"]"], "constraint": Required["Literal[\"safe_integer\"]"], "expected_type": Required["Literal[\"number\", \"int64\"]"], "maximum": Required["Literal[9007199254740991]"], "minimum": Required["Literal[0, 1]"], "operation": Required["Literal[\"take\"]"], "parameter": Required["str"], "stage": Required["Literal[\"binding\"]"]}, total=False)

CheckOutcome0ReportRequirementsItem = TypedDict("CheckOutcome0ReportRequirementsItem", {"code": Required["Literal[\"parameter_value_required\", \"parameter_consumer_condition\", \"host_capacity_policy_required\", \"numeric_reduction_profile_required\"]"], "location": NotRequired["CheckOutcome0ReportRequirementsItemLocation0 | CheckOutcome0ReportRequirementsItemLocation1"], "fixes": NotRequired["list[CheckOutcome0ReportRequirementsItemFixesItem]"], "facts": Required["CheckOutcome0ReportRequirementsItemFacts0 | CheckOutcome0ReportRequirementsItemFacts1 | CheckOutcome0ReportRequirementsItemFacts2 | CheckOutcome0ReportRequirementsItemFacts3 | CheckOutcome0ReportRequirementsItemFacts4 | CheckOutcome0ReportRequirementsItemFacts5 | CheckOutcome0ReportRequirementsItemFacts6 | CheckOutcome0ReportRequirementsItemFacts7 | CheckOutcome0ReportRequirementsItemFacts8 | CheckOutcome0ReportRequirementsItemFacts9 | CheckOutcome0ReportRequirementsItemFacts10 | CheckOutcome0ReportRequirementsItemFacts11 | CheckOutcome0ReportRequirementsItemFacts12 | CheckOutcome0ReportRequirementsItemFacts13 | CheckOutcome0ReportRequirementsItemFacts14"]}, total=False)

CheckOutcome0ReportScope = TypedDict("CheckOutcome0ReportScope", {"kind": Required["Literal[\"template_only\", \"bound_input\"]"]}, total=False)

CheckOutcome0Report = TypedDict("CheckOutcome0Report", {"runnable": Required["CheckOutcome0ReportRunnable"], "context_ref": Required["str"], "omissions": NotRequired["CheckOutcome0ReportOmissions"], "inputs": Required["list[CheckOutcome0ReportInputsItem]"], "coverage": Required["CheckOutcome0ReportCoverage"], "reasons": Required["list[CheckOutcome0ReportReasonsItem]"], "requirements": Required["list[CheckOutcome0ReportRequirementsItem]"], "scope": Required["CheckOutcome0ReportScope"], "verdict": Required["Literal[\"invalid\", \"undetermined\", \"verified\"]"]}, total=False)

CheckOutcome0 = TypedDict("CheckOutcome0", {"outcome": Required["Literal[\"completed\"]"], "report": Required["CheckOutcome0Report"], "outcome_schema_cid": Required["str"], "reason_schema_cid": Required["Literal[\"sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5\"]"], "version": Required["Literal[\"actql-check-outcome/0.1\"]"]}, total=False)

CheckOutcome1PartialReportRunnableReasonsItem = TypedDict("CheckOutcome1PartialReportRunnableReasonsItem", {"code": Required["str"]}, total=False)

CheckOutcome1PartialReportRunnable = TypedDict("CheckOutcome1PartialReportRunnable", {"verdict": Required["Literal[\"yes\", \"no\"]"], "reasons": Required["list[CheckOutcome1PartialReportRunnableReasonsItem]"]}, total=False)

CheckOutcome1PartialReportOmissions = TypedDict("CheckOutcome1PartialReportOmissions", {"requirements": Required["Literal[True]"]}, total=False)

CheckOutcome1PartialReportInputsItem = TypedDict("CheckOutcome1PartialReportInputsItem", {"document_id": Required["Literal[\"source\", \"program\", \"parameter_declarations\", \"parameters\"]"], "revision": Required["str"], "kind": Required["Literal[\"text\", \"structured\"]"], "byte_length": Required["int"]}, total=False)

CheckOutcome1PartialReportCoverageLimitsItem0 = TypedDict("CheckOutcome1PartialReportCoverageLimitsItem0", {"code": Required["str"]}, total=False)

CheckOutcome1PartialReportCoverageLimitsItem1Location = TypedDict("CheckOutcome1PartialReportCoverageLimitsItem1Location", {"kind": Required["Literal[\"structured\"]"], "document_id": Required["Literal[\"program\"]"], "revision": Required["str"], "pointer": Required["str"]}, total=False)

CheckOutcome1PartialReportCoverageLimitsItem1 = TypedDict("CheckOutcome1PartialReportCoverageLimitsItem1", {"code": Required["Literal[\"implementation_limit\", \"analysis_budget_exhausted\"]"], "location": Required["CheckOutcome1PartialReportCoverageLimitsItem1Location"]}, total=False)

CheckOutcome1PartialReportCoverageLimitsItem2Facts = TypedDict("CheckOutcome1PartialReportCoverageLimitsItem2Facts", {"issue": Required["Literal[\"function_lowering_unresolved\"]"]}, total=False)

CheckOutcome1PartialReportCoverageLimitsItem2Location = TypedDict("CheckOutcome1PartialReportCoverageLimitsItem2Location", {"kind": Required["Literal[\"text\"]"], "document_id": Required["Literal[\"source\"]"], "revision": Required["str"], "start_byte": Required["int"], "end_byte": Required["int"], "precision": Required["Literal[\"exact\", \"approximate\"]"]}, total=False)

CheckOutcome1PartialReportCoverageLimitsItem2 = TypedDict("CheckOutcome1PartialReportCoverageLimitsItem2", {"code": Required["Literal[\"implementation_limit\"]"], "facts": Required["CheckOutcome1PartialReportCoverageLimitsItem2Facts"], "location": NotRequired["CheckOutcome1PartialReportCoverageLimitsItem2Location"]}, total=False)

CheckOutcome1PartialReportCoverageUnresolvedItem = TypedDict("CheckOutcome1PartialReportCoverageUnresolvedItem", {"boundary": Required["str"], "reason": Required["Literal[\"unresolved_protected\"]"]}, total=False)

CheckOutcome1PartialReportCoverage = TypedDict("CheckOutcome1PartialReportCoverage", {"limits": Required["list[CheckOutcome1PartialReportCoverageLimitsItem0 | CheckOutcome1PartialReportCoverageLimitsItem1 | CheckOutcome1PartialReportCoverageLimitsItem2]"], "unresolved": Required["list[CheckOutcome1PartialReportCoverageUnresolvedItem]"]}, total=False)

CheckOutcome1PartialReportReasonsItemLocation0 = TypedDict("CheckOutcome1PartialReportReasonsItemLocation0", {"kind": Required["Literal[\"text\"]"], "document_id": Required["Literal[\"source\"]"], "revision": Required["str"], "start_byte": Required["int"], "end_byte": Required["int"], "precision": Required["Literal[\"exact\", \"approximate\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemLocation1 = TypedDict("CheckOutcome1PartialReportReasonsItemLocation1", {"kind": Required["Literal[\"structured\"]"], "document_id": Required["Literal[\"program\", \"parameter_declarations\", \"parameters\"]"], "revision": Required["str"], "pointer": Required["str"]}, total=False)

CheckOutcome1PartialReportReasonsItemFixesItemTarget = TypedDict("CheckOutcome1PartialReportReasonsItemFixesItemTarget", {"document_id": Required["Literal[\"source\"]"], "revision": Required["str"]}, total=False)

CheckOutcome1PartialReportReasonsItemFixesItemEditsItem = TypedDict("CheckOutcome1PartialReportReasonsItemFixesItemEditsItem", {"start_byte": Required["int"], "end_byte": Required["int"], "replacement": Required["Literal[\"*/\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFixesItem = TypedDict("CheckOutcome1PartialReportReasonsItemFixesItem", {"code": Required["Literal[\"close_block_comment\"]"], "applicability": Required["Literal[\"requires_review\"]"], "risk": Required["Literal[\"syntax_structure\"]"], "target": Required["CheckOutcome1PartialReportReasonsItemFixesItemTarget"], "edits": Required["list[CheckOutcome1PartialReportReasonsItemFixesItemEditsItem]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts0 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts0", {"parameter": Required["str"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts1 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts1", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "actual_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0PathItem0 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0PathItem1 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0", {"kind": Required["Literal[\"numeric\"]"], "path": Required["list[CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0PathItem0 | CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0PathItem1]"], "integer": Required["bool"], "minimum": NotRequired["int | float"], "maximum": NotRequired["int | float"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1PathItem0 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1PathItem1 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1", {"kind": Required["Literal[\"duration\"]"], "path": Required["list[CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1PathItem0 | CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1PathItem1]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2PathItem0 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2PathItem1 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2", {"kind": Required["Literal[\"array_length\"]"], "path": Required["list[CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2PathItem0 | CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2PathItem1]"], "length": Required["int"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2Admission = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2Admission", {"contract_schema_cid": Required["Literal[\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"]"], "kind": Required["Literal[\"parameter_declaration\"]"], "contract": Required["ValueContract"], "supplier": Required["Literal[\"caller\"]"], "constraints": Required["list[CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem0 | CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem1 | CheckOutcome1PartialReportReasonsItemFacts2AdmissionConstraintsItem2]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts2 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts2", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "admission": NotRequired["CheckOutcome1PartialReportReasonsItemFacts2Admission"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts3 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts3", {"parameter": Required["str"], "constraint": Required["Literal[\"numeric\", \"duration\", \"array_length\", \"array_size\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts4 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts4", {"expected_type": Required["Literal[\"number\", \"boolean\", \"string\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts5 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts5", {"parameter": Required["str"], "domain": Required["Literal[\"positive_safe_integer\", \"nonnegative_safe_integer\", \"unit_fraction\", \"finite_number\", \"duration\", \"positive_milliseconds\", \"signed_milliseconds\", \"timestamp\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts6 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts6", {"operation": Required["Literal[\"components\"]"], "issue": Required["Literal[\"invalid_kind\", \"invalid_output_rows\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts7 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts7", {"operation": Required["Literal[\"subgraph\"]"], "issue": Required["Literal[\"invalid_node_selector\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts8 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts8", {"document": Required["Literal[\"parameters\", \"parameter_declarations\"]"], "issue": Required["Literal[\"invalid_unicode\", \"unexpected_end\", \"unexpected_token\", \"invalid_string\", \"invalid_escape\", \"invalid_number\", \"number_out_of_range\", \"negative_zero\", \"expected_colon\", \"expected_array_separator\", \"expected_object_separator\", \"duplicate_key\", \"trailing_content\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts9 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts9", {"issue": Required["Literal[\"unexpected_end\", \"unexpected_token\", \"invalid_escape\", \"invalid_scalar\", \"empty_identifier\", \"unterminated_comment\", \"invalid_number\", \"invalid_parameter\", \"unknown_reference\", \"invalid_arguments\", \"expected_boolean\", \"invalid_bounds\", \"function_lowering_unresolved\", \"missing_field\", \"wrong_type\", \"unexpected_null\", \"invalid_structure\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts10 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts10", {"contract_cid": Required["Literal[\"sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9\"]"], "schema_cid": Required["Literal[\"sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265\"]"], "schema_pointer": Required["Literal[\"/schema\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts11 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts11", {"profile_cid": Required["Literal[\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts12 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts12", {"namespace": Required["str"], "connector": Required["str"], "resource": Required["str"], "view": NotRequired["str"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts13ReferenceItem = TypedDict("CheckOutcome1PartialReportReasonsItemFacts13ReferenceItem", {"value": Required["str"], "quoted": Required["bool"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts13 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts13", {"namespace": Required["str"], "reference": Required["list[CheckOutcome1PartialReportReasonsItemFacts13ReferenceItem]"]}, total=False)

CheckOutcome1PartialReportReasonsItemFacts14 = TypedDict("CheckOutcome1PartialReportReasonsItemFacts14", {"argument": Required["Literal[\"count\", \"offset\"]"], "constraint": Required["Literal[\"safe_integer\"]"], "expected_type": Required["Literal[\"number\", \"int64\"]"], "maximum": Required["Literal[9007199254740991]"], "minimum": Required["Literal[0, 1]"], "operation": Required["Literal[\"take\"]"], "parameter": Required["str"], "stage": Required["Literal[\"binding\"]"]}, total=False)

CheckOutcome1PartialReportReasonsItem = TypedDict("CheckOutcome1PartialReportReasonsItem", {"code": Required["str"], "location": NotRequired["CheckOutcome1PartialReportReasonsItemLocation0 | CheckOutcome1PartialReportReasonsItemLocation1"], "fixes": NotRequired["list[CheckOutcome1PartialReportReasonsItemFixesItem]"], "facts": NotRequired["CheckOutcome1PartialReportReasonsItemFacts0 | CheckOutcome1PartialReportReasonsItemFacts1 | CheckOutcome1PartialReportReasonsItemFacts2 | CheckOutcome1PartialReportReasonsItemFacts3 | CheckOutcome1PartialReportReasonsItemFacts4 | CheckOutcome1PartialReportReasonsItemFacts5 | CheckOutcome1PartialReportReasonsItemFacts6 | CheckOutcome1PartialReportReasonsItemFacts7 | CheckOutcome1PartialReportReasonsItemFacts8 | CheckOutcome1PartialReportReasonsItemFacts9 | CheckOutcome1PartialReportReasonsItemFacts10 | CheckOutcome1PartialReportReasonsItemFacts11 | CheckOutcome1PartialReportReasonsItemFacts12 | CheckOutcome1PartialReportReasonsItemFacts13 | CheckOutcome1PartialReportReasonsItemFacts14"]}, total=False)

CheckOutcome1PartialReportRequirementsItemLocation0 = TypedDict("CheckOutcome1PartialReportRequirementsItemLocation0", {"kind": Required["Literal[\"text\"]"], "document_id": Required["Literal[\"source\"]"], "revision": Required["str"], "start_byte": Required["int"], "end_byte": Required["int"], "precision": Required["Literal[\"exact\", \"approximate\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemLocation1 = TypedDict("CheckOutcome1PartialReportRequirementsItemLocation1", {"kind": Required["Literal[\"structured\"]"], "document_id": Required["Literal[\"program\", \"parameter_declarations\", \"parameters\"]"], "revision": Required["str"], "pointer": Required["str"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFixesItemTarget = TypedDict("CheckOutcome1PartialReportRequirementsItemFixesItemTarget", {"document_id": Required["Literal[\"source\"]"], "revision": Required["str"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFixesItemEditsItem = TypedDict("CheckOutcome1PartialReportRequirementsItemFixesItemEditsItem", {"start_byte": Required["int"], "end_byte": Required["int"], "replacement": Required["Literal[\"*/\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFixesItem = TypedDict("CheckOutcome1PartialReportRequirementsItemFixesItem", {"code": Required["Literal[\"close_block_comment\"]"], "applicability": Required["Literal[\"requires_review\"]"], "risk": Required["Literal[\"syntax_structure\"]"], "target": Required["CheckOutcome1PartialReportRequirementsItemFixesItemTarget"], "edits": Required["list[CheckOutcome1PartialReportRequirementsItemFixesItemEditsItem]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts0 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts0", {"parameter": Required["str"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts1 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts1", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "actual_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem0 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem1 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0", {"kind": Required["Literal[\"numeric\"]"], "path": Required["list[CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem0 | CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0PathItem1]"], "integer": Required["bool"], "minimum": NotRequired["int | float"], "maximum": NotRequired["int | float"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem0 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem1 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1", {"kind": Required["Literal[\"duration\"]"], "path": Required["list[CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem0 | CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1PathItem1]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem0 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem0", {"kind": Required["Literal[\"field\"]"], "name": Required["str"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem1 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem1", {"kind": Required["Literal[\"items\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2", {"kind": Required["Literal[\"array_length\"]"], "path": Required["list[CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem0 | CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2PathItem1]"], "length": Required["int"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2Admission = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2Admission", {"contract_schema_cid": Required["Literal[\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"]"], "kind": Required["Literal[\"parameter_declaration\"]"], "contract": Required["ValueContract"], "supplier": Required["Literal[\"caller\"]"], "constraints": Required["list[CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem0 | CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem1 | CheckOutcome1PartialReportRequirementsItemFacts2AdmissionConstraintsItem2]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts2 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts2", {"parameter": Required["str"], "expected_type": Required["Literal[\"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"date\", \"timestamp\", \"decimal\", \"json\", \"vector\", \"resource_ref\", \"content_ref\", \"int64\"]"], "admission": NotRequired["CheckOutcome1PartialReportRequirementsItemFacts2Admission"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts3 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts3", {"parameter": Required["str"], "constraint": Required["Literal[\"numeric\", \"duration\", \"array_length\", \"array_size\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts4 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts4", {"expected_type": Required["Literal[\"number\", \"boolean\", \"string\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts5 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts5", {"parameter": Required["str"], "domain": Required["Literal[\"positive_safe_integer\", \"nonnegative_safe_integer\", \"unit_fraction\", \"finite_number\", \"duration\", \"positive_milliseconds\", \"signed_milliseconds\", \"timestamp\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts6 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts6", {"operation": Required["Literal[\"components\"]"], "issue": Required["Literal[\"invalid_kind\", \"invalid_output_rows\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts7 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts7", {"operation": Required["Literal[\"subgraph\"]"], "issue": Required["Literal[\"invalid_node_selector\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts8 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts8", {"document": Required["Literal[\"parameters\", \"parameter_declarations\"]"], "issue": Required["Literal[\"invalid_unicode\", \"unexpected_end\", \"unexpected_token\", \"invalid_string\", \"invalid_escape\", \"invalid_number\", \"number_out_of_range\", \"negative_zero\", \"expected_colon\", \"expected_array_separator\", \"expected_object_separator\", \"duplicate_key\", \"trailing_content\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts9 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts9", {"issue": Required["Literal[\"unexpected_end\", \"unexpected_token\", \"invalid_escape\", \"invalid_scalar\", \"empty_identifier\", \"unterminated_comment\", \"invalid_number\", \"invalid_parameter\", \"unknown_reference\", \"invalid_arguments\", \"expected_boolean\", \"invalid_bounds\", \"function_lowering_unresolved\", \"missing_field\", \"wrong_type\", \"unexpected_null\", \"invalid_structure\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts10 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts10", {"contract_cid": Required["Literal[\"sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9\"]"], "schema_cid": Required["Literal[\"sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265\"]"], "schema_pointer": Required["Literal[\"/schema\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts11 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts11", {"profile_cid": Required["Literal[\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\"]"], "supplier": Required["Literal[\"checking_context_owner\"]"], "stage": Required["Literal[\"checking\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts12 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts12", {"namespace": Required["str"], "connector": Required["str"], "resource": Required["str"], "view": NotRequired["str"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts13ReferenceItem = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts13ReferenceItem", {"value": Required["str"], "quoted": Required["bool"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts13 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts13", {"namespace": Required["str"], "reference": Required["list[CheckOutcome1PartialReportRequirementsItemFacts13ReferenceItem]"]}, total=False)

CheckOutcome1PartialReportRequirementsItemFacts14 = TypedDict("CheckOutcome1PartialReportRequirementsItemFacts14", {"argument": Required["Literal[\"count\", \"offset\"]"], "constraint": Required["Literal[\"safe_integer\"]"], "expected_type": Required["Literal[\"number\", \"int64\"]"], "maximum": Required["Literal[9007199254740991]"], "minimum": Required["Literal[0, 1]"], "operation": Required["Literal[\"take\"]"], "parameter": Required["str"], "stage": Required["Literal[\"binding\"]"]}, total=False)

CheckOutcome1PartialReportRequirementsItem = TypedDict("CheckOutcome1PartialReportRequirementsItem", {"code": Required["Literal[\"parameter_value_required\", \"parameter_consumer_condition\", \"host_capacity_policy_required\", \"numeric_reduction_profile_required\"]"], "location": NotRequired["CheckOutcome1PartialReportRequirementsItemLocation0 | CheckOutcome1PartialReportRequirementsItemLocation1"], "fixes": NotRequired["list[CheckOutcome1PartialReportRequirementsItemFixesItem]"], "facts": Required["CheckOutcome1PartialReportRequirementsItemFacts0 | CheckOutcome1PartialReportRequirementsItemFacts1 | CheckOutcome1PartialReportRequirementsItemFacts2 | CheckOutcome1PartialReportRequirementsItemFacts3 | CheckOutcome1PartialReportRequirementsItemFacts4 | CheckOutcome1PartialReportRequirementsItemFacts5 | CheckOutcome1PartialReportRequirementsItemFacts6 | CheckOutcome1PartialReportRequirementsItemFacts7 | CheckOutcome1PartialReportRequirementsItemFacts8 | CheckOutcome1PartialReportRequirementsItemFacts9 | CheckOutcome1PartialReportRequirementsItemFacts10 | CheckOutcome1PartialReportRequirementsItemFacts11 | CheckOutcome1PartialReportRequirementsItemFacts12 | CheckOutcome1PartialReportRequirementsItemFacts13 | CheckOutcome1PartialReportRequirementsItemFacts14"]}, total=False)

CheckOutcome1PartialReportScope = TypedDict("CheckOutcome1PartialReportScope", {"kind": Required["Literal[\"template_only\", \"bound_input\"]"]}, total=False)

CheckOutcome1PartialReport = TypedDict("CheckOutcome1PartialReport", {"runnable": Required["CheckOutcome1PartialReportRunnable"], "context_ref": Required["str"], "omissions": NotRequired["CheckOutcome1PartialReportOmissions"], "inputs": Required["list[CheckOutcome1PartialReportInputsItem]"], "coverage": Required["CheckOutcome1PartialReportCoverage"], "reasons": Required["list[CheckOutcome1PartialReportReasonsItem]"], "requirements": Required["list[CheckOutcome1PartialReportRequirementsItem]"], "scope": Required["CheckOutcome1PartialReportScope"], "verdict": Required["Literal[\"invalid\", \"undetermined\"]"]}, total=False)

CheckOutcome1Problem = TypedDict("CheckOutcome1Problem", {"code": Required["str"]}, total=False)

CheckOutcome1 = TypedDict("CheckOutcome1", {"outcome": Required["Literal[\"failed\"]"], "partial_report": NotRequired["CheckOutcome1PartialReport"], "problem": Required["CheckOutcome1Problem"], "correlation_ref": Required["str"], "outcome_schema_cid": Required["str"], "reason_schema_cid": Required["Literal[\"sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5\"]"], "version": Required["Literal[\"actql-check-outcome/0.1\"]"]}, total=False)

CheckOutcome2Problem = TypedDict("CheckOutcome2Problem", {"code": Required["str"]}, total=False)

CheckOutcome2 = TypedDict("CheckOutcome2", {"correlation_ref": Required["str"], "outcome": Required["Literal[\"unavailable\"]"], "problem": Required["CheckOutcome2Problem"], "outcome_schema_cid": Required["str"], "reason_schema_cid": Required["Literal[\"sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5\"]"], "version": Required["Literal[\"actql-check-outcome/0.1\"]"]}, total=False)

CheckOutcome = CheckOutcome0 | CheckOutcome1 | CheckOutcome2

ValueContract0 = TypedDict("ValueContract0", {"type": Required["Literal[\"decimal\"]"], "nullable": Required["bool"], "precision": Required["int"], "scale": Required["int"]}, total=False)

ValueContract1 = TypedDict("ValueContract1", {"type": Required["Literal[\"string\"]"], "nullable": Required["bool"], "min_length": NotRequired["int"], "max_codepoints": NotRequired["int"], "max_utf8_bytes": NotRequired["int"], "enum": NotRequired["list[str]"]}, total=False)

ValueContract2 = TypedDict("ValueContract2", {"type": Required["Literal[\"number\", \"boolean\", \"timestamp\", \"date\", \"json\"]"], "nullable": Required["bool"]}, total=False)

ValueContract3 = TypedDict("ValueContract3", {"type": Required["Literal[\"array\"]"], "nullable": Required["bool"], "items": Required["ValueContract"], "max_items": NotRequired["int"]}, total=False)

ValueContract4 = TypedDict("ValueContract4", {"type": Required["Literal[\"object\"]"], "nullable": Required["bool"], "additional_properties": Required["Literal[False]"], "fields": Required["dict[str, ValueContract]"]}, total=False)

ValueContract5 = TypedDict("ValueContract5", {"type": Required["Literal[\"vector\"]"], "nullable": Required["bool"], "dimensions": Required["int"], "element_type": Required["Literal[\"f32\"]"]}, total=False)

ValueContract6 = TypedDict("ValueContract6", {"type": Required["Literal[\"resource_ref\"]"], "nullable": Required["bool"], "resource_kind": Required["str"]}, total=False)

ValueContract7 = TypedDict("ValueContract7", {"type": Required["Literal[\"content_ref\"]"], "nullable": Required["bool"], "media_type": NotRequired["str"]}, total=False)

ValueContract8 = TypedDict("ValueContract8", {"type": Required["Literal[\"int64\"]"], "nullable": Required["bool"]}, total=False)

ValueContract = ValueContract0 | ValueContract1 | ValueContract2 | ValueContract3 | ValueContract4 | ValueContract5 | ValueContract6 | ValueContract7 | ValueContract8

DeliveryAttempt = TypedDict("DeliveryAttempt", {"version": Required["Literal[\"actql-delivery-attempt/0.1\"]"], "attempt_id": Required["str"], "result_read_grant_cid": Required["str"], "run_definition_cid": Required["str"], "result_manifest_cid": Required["str"], "result_name": Required["str"], "result_artifact_cid": Required["str"], "serialization_contract_cid": Required["str"], "requested_at": Required["str"], "delivery_attempt_cid": Required["str"]}, total=False)

DeliveryRecord = TypedDict("DeliveryRecord", {"version": Required["Literal[\"actql-delivery-record/0.1\"]"], "delivery_attempt_cid": Required["str"], "prior_record_cid": NotRequired["str"], "sequence": Required["int"], "state": Required["Literal[\"streaming\", \"succeeded\", \"failed\", \"cancelled\"]"], "confirmed_byte_count": Required["int"], "exposure": Required["Literal[\"exact\", \"unknown_additional\"]"], "possible_unconfirmed_max_bytes": NotRequired["int"], "delivered_sha256": NotRequired["str"], "result_delivery_receipt_cid": NotRequired["str"], "failure_cid": NotRequired["str"], "observed_at": Required["str"], "cleanup_owner_cids": Required["list[str]"], "delivery_record_cid": Required["str"]}, total=False)

ResultDeliveryReceipt = TypedDict("ResultDeliveryReceipt", {"version": Required["Literal[\"actql-result-delivery-receipt/0.1\"]"], "run_definition_cid": Required["str"], "invocation_cid": Required["str"], "result_manifest_cid": Required["str"], "result_name": Required["str"], "result_artifact_cid": Required["str"], "serialization_contract_cid": Required["str"], "delivered_byte_count": Required["int"], "delivered_sha256": Required["str"], "authorization_context_cid": Required["str"], "egress_admission_cid": Required["str"], "result_delivery_receipt_cid": Required["str"]}, total=False)
