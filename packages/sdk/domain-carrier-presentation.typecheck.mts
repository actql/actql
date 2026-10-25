import type {KnownCheckReasonCode} from './check-reason-catalog.generated.js';
import type {WireCheckOutcomeShape} from '../client-wire/client-host.generated.js';

type Completed = Extract<WireCheckOutcomeShape, {outcome: 'completed'}>;
type Reason = Completed['report']['reasons'][number];
const domainCode: KnownCheckReasonCode = 'expression_domain_mismatch';
const carrierCode: KnownCheckReasonCode = 'carrier_mismatch';
const domain: Reason = {code: domainCode, facts: {domain: 'key_comparable_operands'}};
const numeric: Reason = {code: domainCode, facts: {domain: 'matching_numeric_domains'}};
const carrier: Reason = {code: carrierCode, facts: {expected_carrier: 'vectors', actual_carrier: 'relation'}};
// @ts-expect-error Unsupported carrier names are not part of the closed wire facts.
const unsupported: Reason = {code: carrierCode, facts: {expected_carrier: 'future_carrier', actual_carrier: 'relation'}};
void [domain, numeric, carrier, unsupported];
