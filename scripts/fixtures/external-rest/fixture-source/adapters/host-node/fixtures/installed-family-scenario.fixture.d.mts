// The corresponding JS is a frozen support fixture from shared-fixture-source.json.
type ProviderRequest = Readonly<{method: string; target: string}>;
type ProviderResponse = Readonly<{statusCode: number; body: string}>;
type AccountScenario = Readonly<{id: string}>;
type Family<Scenario> = Readonly<{
  root: string;
  scenario: Scenario;
  paths: Readonly<{project: string; home: string; state: string; credentialJournal: string;
    accountPath: string; originalReference: string}>;
  keys: Readonly<{credentialAuthority: Readonly<{privateKeyPath: string; publicKeyPath: string; publicKeyPem: string}>}>;
  resourceHttps: Readonly<{origin: string; caPath: string; caPem: string}>;
  accountConfigurationWire: string;
  providerTokenPath: string;
  https: Readonly<{close(): Promise<void>}>;
  writeProjectInput(name: string, bytes: string): Promise<string>;
}>;
export declare function createInstalledFamilyScenario<Scenario extends AccountScenario>(
  test: undefined,
  options: Readonly<{scratchParent: string; scenario: Scenario; accountConfigurationWire: string;
    maxRequestBytes: number; provider: Readonly<{handle(request: ProviderRequest): ProviderResponse | Promise<ProviderResponse>}>}>,
): Promise<Family<Scenario>>;
