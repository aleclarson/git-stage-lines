## Goal

Publish a JavaScript/TypeScript package named:

```text
git-stage-lines
```

The package provides ergonomic Node.js and Bun-compatible APIs for invoking the bundled native `git-stage-lines` binary.

The npm package is a thin adapter. It must not duplicate staging, diff, or patch-selection logic that belongs in the native binary.

---

## Current Toolchain

This repo is currently set up as a flat npm package, not a monorepo package under `packages/npm`.

Use the existing toolchain:

```text
Package manager: pnpm
Lockfile:        pnpm-lock.yaml, lockfileVersion 9
Module format:   ESM
Build tool:      tsdown
API snapshots:   tsnapi via tsnapi/rolldown
TypeScript:      TypeScript 6
Lint:            oxlint
Format:          oxfmt
Tests:           Vitest
Runtime deps:    none
```

Current package scripts:

```json
{
  "dev": "tsdown --sourcemap --watch",
  "build": "tsdown",
  "build:native": "node scripts/build-npm-binaries.mjs",
  "build:package": "pnpm build && pnpm build:native",
  "format": "oxfmt .",
  "lint": "oxlint src/npm test/npm",
  "typecheck": "tsc --noEmit && tsc -p test --noEmit",
  "test": "vitest",
  "prepack": "pnpm build:package"
}
```

Keep future work aligned with these scripts unless there is a concrete reason to change them.

---

## Package Shape

Current `package.json` shape:

```json
{
  "name": "git-stage-lines",
  "version": "0.0.0",
  "type": "module",
  "files": ["CHANGELOG.md", "dist", "docs", "examples"],
  "bin": {
    "git-stage-lines": "./dist/cli.mjs"
  },
  "exports": {
    "types": "./dist/index.d.mts",
    "default": "./dist/index.mjs"
  }
}
```

The initial npm package should keep a single root export:

```ts
import { stageLines } from 'git-stage-lines'
```

Do not add `./node`, `./bun`, or other subpath exports until the implementation needs separate public entry points. Runtime-specific internals can still live in separate source files.

Recommended source layout:

```text
src/
  npm/
    index.ts
    types.ts
    ranges.ts
    errors.ts
    binary.ts
    run.ts
    cli.ts
scripts/
  build-npm-binaries.mjs
test/
  npm/
    *.test.ts
docs/
examples/
```

If runtime-specific process code becomes necessary, prefer internal modules:

```text
src/
  npm/
    runtime/
      node.ts
      bun.ts
```

Keep the public surface exported from `src/npm/index.ts`.

---

## Build Configuration

The build is driven by `tsdown.config.ts`:

```ts
import { defineConfig } from 'tsdown'
import ApiSnapshot from 'tsnapi/rolldown'

export default defineConfig({
  entry: ['src/npm/index.ts', 'src/npm/cli.ts'],
  format: ['esm'],
  dts: true,
  plugins: [ApiSnapshot()],
})
```

Expected build output:

```text
dist/index.mjs
dist/index.d.mts
dist/cli.mjs
dist/bin/<platform>-<arch>/git-stage-lines
```

Do not introduce `tsup`, `unbuild`, Rollup config files, or a second build pipeline while `tsdown` covers the package needs.

The `tsnapi` plugin should remain in the build so exported API changes are visible during development and review.

---

## TypeScript Configuration

The root `tsconfig.json` is strict and source-focused:

```json
{
  "include": ["src/npm"],
  "compilerOptions": {
    "strict": true,
    "erasableSyntaxOnly": true,
    "noUncheckedSideEffectImports": true,
    "lib": ["esnext"],
    "target": "esnext",
    "module": "esnext",
    "moduleResolution": "bundler",
    "declaration": true,
    "emitDeclarationOnly": true,
    "skipLibCheck": true,
    "types": ["node"]
  }
}
```

Implications:

```text
- Source should use explicit imports for runtime APIs.
- Node types are enabled so `node:` module imports resolve in production source.
- Avoid relying on ambient Bun globals in production source.
- Keep TypeScript syntax erasable.
- Keep emitted declarations compatible with the ESM export map.
```

The test TypeScript config extends the root config and enables Node and Vitest globals:

```json
{
  "extends": "../tsconfig.json",
  "include": ["npm"],
  "compilerOptions": {
    "types": ["node", "vitest/globals"]
  }
}
```

---

## Formatting And Linting

Formatting uses `oxfmt` with `.oxfmtrc.json`:

```json
{
  "$schema": "./node_modules/oxfmt/configuration_schema.json",
  "ignorePatterns": [".agents/**"],
  "semi": false,
  "singleQuote": true
}
```

Linting uses:

```bash
pnpm lint
```

which currently runs:

```bash
oxlint src/npm test/npm
```

Keep source formatting consistent with the formatter:

```text
- no semicolons
- single quotes
- ESM imports and exports
```

---

## Testing

Tests use Vitest:

```ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    globals: true,
    isolate: false,
  },
})
```

Use focused tests for:

```text
- range normalization
- argument construction
- binary discovery
- JSON parsing
- error conversion
- process failure behavior
```

Prefer unit tests that mock process execution for adapter behavior. Add integration tests against a real binary only when the native CLI exists in the local test environment and the test can remain deterministic.

---

## Dependency Policy

Runtime dependencies should remain empty.

Current development dependencies:

```text
@types/bun
@types/node
oxfmt
oxlint
tsdown
tsnapi
typescript
vitest
```

Do not reintroduce utility libraries for small helpers. Implement range normalization, option validation, and error mapping directly unless the need clearly exceeds a few local functions.

---

## Public API

The package should expose a small, stable API from the root export.

Recommended exports:

```ts
export { checkStageLines, dryRunStageLines, findBinary, stageLines, stageLinesSync }

export type {
  FindBinaryOptions,
  StageLinesErrorResult,
  StageLinesNoopResult,
  StageLinesOptions,
  StageLinesResult,
  StageLinesSuccessResult,
}
```

`stageLinesSync` should be available when running in Node-compatible environments. If Bun-specific sync behavior is not reliable, document that the sync API is Node-oriented instead of creating a separate public Bun export.

---

## API Requirements

### `stageLines`

Primary async API.

```ts
stageLines(options: StageLinesOptions): Promise<StageLinesResult>
```

Example:

```ts
await stageLines({
  file: 'src/app.ts',
  ranges: '10-15,22',
  mode: 'both',
})
```

### `stageLinesSync`

Synchronous API for Node-compatible scripts and automation.

```ts
stageLinesSync(options: StageLinesOptions): StageLinesResult
```

### `checkStageLines`

Validate that the selected patch would apply, but do not stage.

```ts
checkStageLines(options: StageLinesOptions): Promise<StageLinesResult>
```

This maps to CLI behavior equivalent to:

```bash
git-stage-lines FILE RANGES --check --json
```

### `dryRunStageLines`

Return dry-run output without modifying the Git index.

```ts
dryRunStageLines(options: StageLinesOptions): Promise<StageLinesResult>
```

This maps to CLI behavior equivalent to:

```bash
git-stage-lines FILE RANGES --dry-run --json
```

### `findBinary`

Expose binary resolution for advanced users.

```ts
findBinary(options?: FindBinaryOptions): string
```

---

## Type Requirements

### `StageLinesOptions`

```ts
export type StageLinesOptions = {
  file: string
  ranges: string | Array<number | [number, number]>

  mode?: 'new' | 'old' | 'both'

  cwd?: string
  binaryPath?: string

  dryRun?: boolean
  check?: boolean
  allowEmpty?: boolean
  verbose?: boolean

  env?: Record<string, string | undefined>
  signal?: AbortSignal
}
```

### `StageLinesResult`

```ts
export type StageLinesResult =
  | StageLinesSuccessResult
  | StageLinesNoopResult
  | StageLinesErrorResult
```

### `StageLinesSuccessResult`

```ts
export type StageLinesSuccessResult = {
  status: 'staged'
  file: string
  ranges: string[]
  mode: 'new' | 'old' | 'both'
  selected_changes: number
  skipped_changes: number
  patch_applied: true
}
```

### `StageLinesNoopResult`

```ts
export type StageLinesNoopResult = {
  status: 'noop'
  file: string
  ranges: string[]
  mode: 'new' | 'old' | 'both'
  selected_changes: 0
  skipped_changes: number
  patch_applied: false
  reason: 'no_matching_changes' | 'empty_patch'
}
```

### `StageLinesErrorResult`

```ts
export type StageLinesErrorResult = {
  status: 'error'
  reason: string
  message: string
  file?: string
  ranges?: string[]
  exit_code?: number
  stderr?: string
}
```

---

## Range Input

Accept raw CLI-style ranges:

```ts
ranges: '10-15,22,40-45'
```

Accept structured ranges:

```ts
ranges: [[10, 15], 22, [40, 45]]
```

Structured input should normalize to:

```text
10-15,22,40-45
```

Invalid ranges should fail before invoking the binary.

Validation should reject:

```text
- non-integer values
- zero or negative line numbers
- ranges where start > end
- empty range strings
- empty structured range arrays
```

---

## CLI Mapping

The adapter should always invoke the native binary with `--json`.

Example:

```ts
stageLines({
  file: 'src/app.ts',
  ranges: [[10, 15], 22],
  mode: 'both',
  cwd: repoPath,
  allowEmpty: true,
})
```

Should invoke equivalent behavior to:

```bash
git-stage-lines src/app.ts 10-15,22 --mode both --allow-empty --json
```

Use argument arrays. Never interpolate a shell command string.

---

## Binary Resolution

Resolve the binary in this order:

```text
1. options.binaryPath
2. GIT_STAGE_LINES_BINARY environment variable
3. bundled platform-specific binary
4. git-stage-lines on PATH
5. git stage-lines via Git subcommand resolution, only if direct binary resolution fails
```

The package should support external binary overrides from development, CI, package managers, and custom agent environments.

---

## Process Requirements

Async execution should support:

```text
- cwd
- env overrides
- AbortSignal
- stdout JSON parsing
- stderr capture
- nonzero exit diagnostics
```

Sync execution should support:

```text
- cwd
- env overrides
- stdout JSON parsing
- stderr capture
- nonzero exit diagnostics
```

The implementation should preserve process-level details when it throws and preserve CLI-level JSON details when the binary returns a structured error result.

---

## Error Handling

Distinguish:

```text
- invalid adapter input
- binary not found
- process spawn failure
- process termination
- signal or abort cancellation
- malformed JSON from stdout
- CLI-reported staging error
- Git command failure surfaced by the CLI
```

Recommended custom error class:

```ts
export class GitStageLinesError extends Error {
  reason: string
  exitCode?: number
  result?: StageLinesErrorResult
  stderr?: string
}
```

Recommended behavior:

```text
CLI returned JSON error: return StageLinesErrorResult
Binary could not execute: throw GitStageLinesError
Malformed JSON:           throw GitStageLinesError
Invalid JS input:         throw TypeError or GitStageLinesError
```

---

## Agent-Facing Requirements

The package should be safe for agents.

It should:

```text
- never invoke a shell
- never prompt interactively
- always pass --json
- provide deterministic result objects
- preserve nonzero exit details
- support cwd explicitly
- support dry-run and check modes
- avoid hidden fallback behavior that changes staging semantics
```

Recommended agent usage:

```ts
const result = await stageLines({
  cwd: repoPath,
  file: 'src/app.ts',
  ranges: [[10, 15]],
  mode: 'both',
})

if (result.status === 'error') {
  // Inspect result.reason.
}
```

---

## Publishing

Publishing should run:

```bash
pnpm build:package
```

through `prepack`.

Before publishing, verify:

```bash
pnpm format
pnpm lint
pnpm typecheck
pnpm test
pnpm build:package
npm pack --dry-run
```

The published package should include only:

```text
dist
docs
examples
LICENSE
README.md
CHANGELOG.md
package.json
```

The `dist` package contents should include the JavaScript entry points and generated native binaries under `dist/bin/<platform>-<arch>/`.

---

## Implementation Order

1. Add `src/npm/types.ts` with public option, result, and error types.
2. Add `src/npm/ranges.ts` for range validation and normalization.
3. Add `src/npm/binary.ts` for binary discovery.
4. Add `src/npm/run.ts` for process execution and JSON parsing.
5. Export the public API from `src/npm/index.ts`.
6. Add Vitest coverage for validation, argument mapping, binary resolution, and error handling.
7. Run `pnpm typecheck`, `pnpm test`, and `pnpm build`.

Keep each commit atomic and use Conventional Commits.
