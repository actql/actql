// Browser tooling is supplied by the installed consumer. Keep its fixture
// port independent of the product package and the test runner's installation.
type RoleOptions = {name?: string | RegExp; exact?: boolean};
type TextOptions = {exact?: boolean};
type WaitOptions = {state?: 'attached' | 'hidden'};
type FilterOptions = {has?: Locator; hasText?: string | RegExp};

interface Locator {
  locator(selector: string): Locator;
  getByRole(role: string, options?: RoleOptions): Locator;
  getByText(text: string | RegExp, options?: TextOptions): Locator;
  getByTestId(id: string): Locator;
  filter(options: FilterOptions): Locator;
  and(other: Locator): Locator;
  first(): Locator;
  waitFor(options?: WaitOptions): Promise<void>;
  click(): Promise<void>;
  fill(value: string): Promise<void>;
  selectOption(value: string): Promise<string[]>;
  setInputFiles(path: string): Promise<void>;
  getAttribute(name: string): Promise<string | null>;
  innerText(options?: {timeout: number}): Promise<string>;
  textContent(): Promise<string | null>;
  inputValue(): Promise<string>;
  allTextContents(): Promise<string[]>;
  boundingBox(): Promise<{x: number; y: number; width: number; height: number} | null>;
  count(): Promise<number>;
  evaluate<Result>(callback: (element: Element) => Result): Promise<Result>;
  evaluateAll<Result>(callback: (elements: Element[]) => Result): Promise<Result>;
}

interface BrowserRequest {
  url(): string;
}

interface BrowserResponse {
  url(): string;
  status(): number;
  json(): Promise<unknown>;
}

interface Route {
  request(): BrowserRequest;
  fetch(options: {maxRetries: number; maxRedirects: number}): Promise<BrowserResponse>;
  fulfill(options: {response: BrowserResponse}): Promise<void>;
  abort(): Promise<void>;
  continue(): Promise<void>;
}

interface Page {
  locator(selector: string): Locator;
  getByRole(role: string, options?: RoleOptions & {level?: number}): Locator;
  getByText(text: string | RegExp, options?: TextOptions): Locator;
  getByLabel(label: string, options?: TextOptions): Locator;
  setDefaultTimeout(milliseconds: number): void;
  setViewportSize(size: {width: number; height: number}): Promise<void>;
  on(event: 'pageerror', handler: (error: Error) => void): void;
  on(event: 'request', handler: (request: BrowserRequest) => void): void;
  route(url: string, handler: (route: Route) => Promise<void>): Promise<void>;
  goto(url: string, options: {waitUntil: 'networkidle'}): Promise<unknown>;
  screenshot(options: {path: string; fullPage?: boolean}): Promise<unknown>;
  waitForResponse(predicate: (response: BrowserResponse) => boolean): Promise<BrowserResponse>;
  evaluate<Result>(callback: () => Result): Promise<Result>;
  waitForFunction<Argument>(predicate: (argument: Argument) => unknown, arg?: Argument): Promise<unknown>;
  close(): Promise<void>;
}

export interface Browser {
  newPage(options: {viewport: {width: number; height: number}}): Promise<Page>;
  version(): string;
  close(): Promise<void>;
}

export interface BrowserModule {
  chromium: {launch(options: {headless: boolean; executablePath: string}): Promise<Browser>};
}
