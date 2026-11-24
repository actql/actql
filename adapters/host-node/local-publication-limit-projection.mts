import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';
import resultServiceRecipe from './host-result-service-recipe.cjs';

type Limits = Readonly<Record<(typeof resultOutputLimitFields)[number], number | undefined>>;
type PreparationOwner = Readonly<{kind: 'preparation'; value: unknown}>;
type InstalledRunOwner = Readonly<{kind: 'installed_run'; value: unknown}>;
type LimitsBinding = (original: unknown, prepared: unknown, storeBytes: number) => unknown;
type PreparedLimits = Readonly<{clientProgramPreparedLocalPublicationLimits: LimitsBinding}>;
type InstalledLimits = Readonly<{clientProgramInstalledManagedPublicationLimits: LimitsBinding}>;

const {hostResultStorePolicy} = resultServiceRecipe;

// Contract and evidence issuance bounds only. Captured Named Result snapshots
// consume the same original logical output policy as durable publication,
// including its relation wrapper; these metadata bounds do not cap row data.
// Project the common checked policy; no adapter-specific row/field formula.
export function checkedLocalOutputLimits(moon: PreparedLimits, preparedProgram: unknown,
  publicationOriginal: PreparationOwner): Limits;
export function checkedLocalOutputLimits(moon: InstalledLimits, preparedProgram: unknown,
  publicationOriginal: InstalledRunOwner): Limits;
export function checkedLocalOutputLimits(moon: PreparedLimits | InstalledLimits, preparedProgram: unknown,
  publicationOriginal: PreparationOwner | InstalledRunOwner | undefined): Limits {
  let values;
  if (publicationOriginal?.kind === 'preparation') {
    values = (moon as PreparedLimits).clientProgramPreparedLocalPublicationLimits(publicationOriginal.value,
      preparedProgram, hostResultStorePolicy.maxObjectBytes);
  } else if (publicationOriginal?.kind === 'installed_run') {
    values = (moon as InstalledLimits).clientProgramInstalledManagedPublicationLimits(publicationOriginal.value,
      preparedProgram, hostResultStorePolicy.maxObjectBytes);
  } else {
    throw new TypeError('InvalidCheckedLocalPublicationOriginal');
  }
  return checkedPublicationLimitValues(values);
}

export function checkedPublicationLimitValues(values: unknown): Limits {
  const names = resultOutputLimitFields;
  if (!Array.isArray(values) || values.length !== names.length ||
      values.some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new TypeError('InvalidCheckedLocalPublicationLimits');
  }
  return Object.freeze(Object.fromEntries(names.map((name,index) => [name,values[index]]))) as Limits;
}
