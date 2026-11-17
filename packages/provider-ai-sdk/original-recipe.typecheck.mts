import {
  createInstalledOpenAIChatRegistration,
  createInstalledUndiciOpenAIChatRegistration,
  type OpenAIOriginalMaterials,
  type OriginalReadRecipeData,
  type OriginalReadInstallationData,
  type OpenAIChatRegistrationOptions,
  type OpenAIChatRecipeRegistrationOptions,
  type PhysicalAcquisitionLimits,
  type ModelProviderRegistration,
} from '@actql/provider-ai-sdk';

declare const materials: Omit<OpenAIOriginalMaterials,
  'originalReadInstallation' | 'originalReadRecipe'>;
declare const recipe: OriginalReadRecipeData;
declare const installed: OriginalReadInstallationData;
declare const registration: OpenAIChatRegistrationOptions;
declare const recipeRegistration: OpenAIChatRecipeRegistrationOptions;
declare const physicalAcquisitionLimits: PhysicalAcquisitionLimits;

const recipeMaterials: OpenAIOriginalMaterials = {...materials, originalReadRecipe: recipe};
const boundMaterials: OpenAIOriginalMaterials = {...materials, originalReadInstallation: installed};
void recipeMaterials;
void boundMaterials;

// @ts-expect-error Bound and per-Graph selections are mutually exclusive.
const mixed: OpenAIOriginalMaterials = {...materials,
  originalReadRecipe: recipe, originalReadInstallation: installed};
// @ts-expect-error A prebound declaration is not an unbound recipe.
const prebound: OriginalReadRecipeData = installed;
void mixed;
void prebound;

createInstalledOpenAIChatRegistration(registration);
createInstalledOpenAIChatRegistration(recipeRegistration);
// @ts-expect-error A spread must not bypass mutually exclusive opaque modes.
createInstalledOpenAIChatRegistration({...recipeRegistration, originalReadInstallation: {}});
// @ts-expect-error The original opaque mode cannot carry a recipe as well.
createInstalledOpenAIChatRegistration({...registration, originalReadRecipe: {}});
const {fetch: unused, ...undiciRecipe} = recipeRegistration;
void unused;
createInstalledUndiciOpenAIChatRegistration({...undiciRecipe, physicalAcquisitionLimits});

const {originalReadInstallation: old, rawCaptureSelection: raw, ...options} = registration;
void old;
void raw;
createInstalledOpenAIChatRegistration({...options, originalMaterials: recipeMaterials});
createInstalledOpenAIChatRegistration({...options, originalMaterials: boundMaterials});

// @ts-expect-error Material and opaque-profile selections cannot be combined.
createInstalledOpenAIChatRegistration({...registration, originalMaterials: recipeMaterials});

// @ts-expect-error The existing Host callback consumes a provider array.
const invalidCallback: ModelProviderRegistration = () => ({});
void invalidCallback;
const {installation: missing, ...incomplete} = recipeMaterials;
void missing;
// @ts-expect-error A read recipe cannot replace the physical installation DATA.
createInstalledOpenAIChatRegistration({...options, originalMaterials: incomplete});
