// The existing generated shape checks refine DATA only. They do not certify
// a current authorization, nominal receipt or physical cleanup acknowledgement.
import {clientHostOperations, clientHostRequestKeys, validClientRequestOptionalFields,
  validRunRefShape, validSubmissionRefShape, validOwnerObservationsShape,
  validProfileContract, validAdmissionContract, validRunWaitContract,
  validHeldContract, validRequestLookupContract, validCheckOutcomeContract} from './client-host.generated.js';
import type {WireRunRefShape, WireSubmissionRefShape, WireOwnerObservationsShape,
  WireConnectionShape, WireProfileShape, WireAdmissionShape, WireRunStateShape,
  WireHeldShape, WireLookupFoundShape, WireLookupNotFoundShape, WireLookupUnknownShape,
  WireCheckOutcomeShape, ClientHostOperation} from './client-host.generated.js';
import {validDeliveryAttempt, validDeliveryRecord, validHostReleaseReceipt} from './publication.generated.js';
import type {WireDeliveryAttempt, WireDeliveryRecord, WireHostReleaseReceipt} from './publication.generated.js';

declare const input: unknown;
declare const connection: WireConnectionShape;

const operations: readonly ClientHostOperation[] = clientHostOperations;
const keys: string[] | undefined = clientHostRequestKeys(input, input);
const optionalFields: boolean = validClientRequestOptionalFields(input, input);
void operations; void keys; void optionalFields;
// @ts-expect-error Unchecked input has no admitted field access.
input.runDefinitionCid;
if (validRunRefShape(input)) {const value: WireRunRefShape = input; void value;}
if (validSubmissionRefShape(input)) {const value: WireSubmissionRefShape = input; void value;}
if (validOwnerObservationsShape(input)) {const value: WireOwnerObservationsShape = input; void value;}
if (validProfileContract(input, connection)) {const value: WireProfileShape = input; void value;}
if (validAdmissionContract(input, connection)) {const value: WireAdmissionShape = input; void value;}
if (validRunWaitContract(input, null)) {const value: WireRunStateShape = input; void value;}
if (validHeldContract(input, 'request')) {const value: WireHeldShape = input; void value;}
if (validRequestLookupContract(input, 'request')) {
  const value: WireLookupFoundShape | WireLookupNotFoundShape | WireLookupUnknownShape | WireHeldShape = input;
  void value;
}
if (validCheckOutcomeContract(input)) {const value: WireCheckOutcomeShape = input; void value;}
if (validDeliveryAttempt(input)) {const value: WireDeliveryAttempt = input; void value;}
if (validDeliveryRecord(input)) {const value: WireDeliveryRecord = input; void value;}
if (validHostReleaseReceipt(input)) {const value: WireHostReleaseReceipt = input; void value;}
// @ts-expect-error A structural Run reference does not have arbitrary fields.
if (validRunRefShape(input)) input.unissuedAuthority;
