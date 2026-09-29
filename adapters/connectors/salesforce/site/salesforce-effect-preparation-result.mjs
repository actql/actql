import {checked} from '../../../host-common/runtime-result.mjs';
import {checkedEffectPreparation} from
  '../../../host-common/effect-preparation-result.mjs';

// A Catalog can finish with unavailable Resources. Do not turn an outage,
// rate limit or incomplete observation into a definitive write refusal.
// The JSON comes from the exact opaque MoonBit observation used by the check;
// caller-supplied metadata is not accepted here.
export function checkedSalesforceCatalogPreparation(result, moon, observation) {
  if (result?.$tag !== 0) return checked(result);
  const {listed_resources: resources} = JSON.parse(
    moon.salesforceCatalogObservationJson(observation));
  const observed = Array.isArray(resources) && resources.length > 0 &&
    resources.every(resource => resource.outcome === 'described');
  return observed ? checkedEffectPreparation(result) : checked(result);
}
