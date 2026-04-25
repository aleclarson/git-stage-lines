import { spawn, spawnSync, type ChildProcess, type SpawnOptions } from 'node:child_process'

import { resolveBinary, mergeEnv } from './binary'
import { GitStageLinesError } from './errors'
import { normalizeRanges } from './ranges'
import type {
  FindBinaryOptions,
  StageLinesErrorResult,
  StageLinesMode,
  StageLinesOptions,
  StageLinesResult,
} from './types'

type PreparedCommand = {
  command: string
  args: string[]
  cwd?: string
  env: Record<string, string | undefined>
}

export async function stageLines(options: StageLinesOptions): Promise<StageLinesResult> {
  return runStageLines(options)
}

export function stageLinesSync(options: StageLinesOptions): StageLinesResult {
  const prepared = prepareCommand(options)

  if (options.signal?.aborted) {
    throw new GitStageLinesError('Process was aborted before git-stage-lines could run', {
      reason: 'aborted',
    })
  }

  const result = spawnSync(prepared.command, prepared.args, {
    cwd: prepared.cwd,
    env: prepared.env,
    encoding: 'utf8',
    shell: false,
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  if (result.error) {
    throw spawnError(result.error)
  }

  if (result.signal) {
    throw new GitStageLinesError(`git-stage-lines terminated with signal ${result.signal}`, {
      reason: 'terminated',
      stderr: result.stderr,
    })
  }

  return parseOutput(result.stdout, result.stderr, result.status ?? 0)
}

export function checkStageLines(options: StageLinesOptions): Promise<StageLinesResult> {
  return runStageLines({ ...options, check: true, dryRun: false })
}

export function dryRunStageLines(options: StageLinesOptions): Promise<StageLinesResult> {
  return runStageLines({ ...options, dryRun: true, check: false })
}

export { findBinary } from './binary'
export type { FindBinaryOptions }

async function runStageLines(options: StageLinesOptions): Promise<StageLinesResult> {
  const prepared = prepareCommand(options)

  return new Promise((resolve, reject) => {
    const spawnOptions: SpawnOptions = {
      cwd: prepared.cwd,
      env: prepared.env,
      shell: false,
      stdio: ['ignore', 'pipe', 'pipe'],
    }

    if (options.signal) {
      Object.assign(spawnOptions, { signal: options.signal })
    }

    const child: ChildProcess = spawn(prepared.command, prepared.args, spawnOptions)
    let stdout = ''
    let stderr = ''
    let settled = false

    child.stdout?.setEncoding('utf8')
    child.stderr?.setEncoding('utf8')

    child.stdout?.on('data', (chunk: unknown) => {
      stdout += String(chunk)
    })

    child.stderr?.on('data', (chunk: unknown) => {
      stderr += String(chunk)
    })

    child.on('error', (error: Error & { code?: string }) => {
      if (settled) return
      settled = true
      reject(spawnError(error))
    })

    child.on('close', (code: number | null, signal: string | null) => {
      if (settled) return
      settled = true

      if (signal) {
        reject(
          new GitStageLinesError(`git-stage-lines terminated with signal ${signal}`, {
            reason: signal === 'SIGTERM' && options.signal?.aborted ? 'aborted' : 'terminated',
            stderr,
          }),
        )
        return
      }

      try {
        resolve(parseOutput(stdout, stderr, code ?? 0))
      } catch (error) {
        reject(error)
      }
    })
  })
}

function prepareCommand(options: StageLinesOptions): PreparedCommand {
  validateOptions(options)

  const normalizedRanges = normalizeRanges(options.ranges)
  const mode: StageLinesMode = options.mode ?? 'new'
  const env = mergeEnv(options.env)
  const resolved = resolveBinary(options)
  const args = [
    ...resolved.argsPrefix,
    options.file,
    normalizedRanges,
    '--mode',
    mode,
    ...flag(options.allowEmpty, '--allow-empty'),
    ...flag(options.verbose, '--verbose'),
    ...numberOption(options.context, '--context'),
    ...flag(options.dryRun, '--dry-run'),
    ...flag(options.check, '--check'),
    '--json',
  ]

  return {
    command: resolved.command,
    args,
    cwd: options.cwd,
    env,
  }
}

function validateOptions(options: StageLinesOptions): void {
  if (!options || typeof options !== 'object') {
    throw new TypeError('options must be an object')
  }

  if (typeof options.file !== 'string' || options.file.trim().length === 0) {
    throw new TypeError('file must be a non-empty string')
  }

  if (options.mode !== undefined && !['new', 'old', 'both'].includes(options.mode)) {
    throw new TypeError('mode must be new, old, or both')
  }

  if (options.context !== undefined) {
    if (!Number.isInteger(options.context) || options.context < 0 || options.context > 1000) {
      throw new TypeError('context must be an integer between 0 and 1000')
    }
  }

  if (options.dryRun && options.check) {
    throw new TypeError('dryRun and check are mutually exclusive')
  }
}

function flag(enabled: boolean | undefined, name: string): string[] {
  return enabled ? [name] : []
}

function numberOption(value: number | undefined, name: string): string[] {
  return value === undefined ? [] : [name, String(value)]
}

function parseOutput(stdout: string, stderr: string, exitCode: number): StageLinesResult {
  const text = stdout.trim()
  if (text.length === 0) {
    const missingSubcommand = stderr.includes('not a git command')
    throw new GitStageLinesError(
      missingSubcommand ? 'Could not execute git-stage-lines' : 'git-stage-lines did not emit JSON',
      {
        reason: missingSubcommand ? 'binary_not_found' : 'missing_json',
        exitCode,
        stderr,
      },
    )
  }

  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch (cause) {
    throw new GitStageLinesError('git-stage-lines emitted malformed JSON', {
      reason: 'malformed_json',
      exitCode,
      stderr,
      cause,
    })
  }

  if (!isResultObject(parsed)) {
    throw new GitStageLinesError('git-stage-lines emitted an unexpected JSON shape', {
      reason: 'invalid_json',
      exitCode,
      stderr,
    })
  }

  if (parsed.status === 'error') {
    const result = withErrorDiagnostics(parsed, exitCode, stderr)
    return result
  }

  if (exitCode !== 0) {
    throw new GitStageLinesError(`git-stage-lines exited with code ${exitCode}`, {
      reason: 'process_failed',
      exitCode,
      stderr,
    })
  }

  return parsed
}

function isResultObject(value: unknown): value is StageLinesResult {
  if (!value || typeof value !== 'object') return false
  const status = (value as { status?: unknown }).status
  return (
    status === 'staged' ||
    status === 'checked' ||
    status === 'dry-run' ||
    status === 'noop' ||
    status === 'error'
  )
}

function withErrorDiagnostics(
  result: StageLinesErrorResult,
  exitCode: number,
  stderr: string,
): StageLinesErrorResult {
  return {
    ...result,
    exit_code: result.exit_code ?? exitCode,
    stderr: result.stderr ?? (stderr.length === 0 ? undefined : stderr),
  }
}

function spawnError(error: Error & { code?: string }): GitStageLinesError {
  if (error.name === 'AbortError' || error.code === 'ABORT_ERR') {
    return new GitStageLinesError('git-stage-lines was aborted', {
      reason: 'aborted',
      cause: error,
    })
  }

  if (error.code === 'ENOENT') {
    return new GitStageLinesError('Could not execute git-stage-lines', {
      reason: 'binary_not_found',
      cause: error,
    })
  }

  return new GitStageLinesError('Failed to execute git-stage-lines', {
    reason: 'spawn_failed',
    cause: error,
  })
}
