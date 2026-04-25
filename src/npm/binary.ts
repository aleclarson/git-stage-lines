import { accessSync, constants, existsSync } from 'node:fs'
import { delimiter, dirname, isAbsolute, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

import { GitStageLinesError } from './errors'
import type { FindBinaryOptions } from './types'

export type ResolvedBinary = {
  command: string
  argsPrefix: string[]
}

export function findBinary(options: FindBinaryOptions = {}): string {
  return resolveBinary(options).command
}

export function resolveBinary(options: FindBinaryOptions = {}): ResolvedBinary {
  const env = mergeEnv(options.env)

  if (options.binaryPath) {
    return { command: options.binaryPath, argsPrefix: [] }
  }

  const envBinary = env.GIT_STAGE_LINES_BINARY
  if (envBinary) {
    return { command: envBinary, argsPrefix: [] }
  }

  const bundledBinary = findBundledBinary()
  if (bundledBinary) {
    return { command: bundledBinary, argsPrefix: [] }
  }

  const pathBinary = findOnPath('git-stage-lines', env)
  if (pathBinary) {
    return { command: pathBinary, argsPrefix: [] }
  }

  const gitBinary = findOnPath('git', env)
  if (gitBinary) {
    return { command: gitBinary, argsPrefix: ['stage-lines'] }
  }

  throw new GitStageLinesError('Could not find git-stage-lines or git on PATH', {
    reason: 'binary_not_found',
  })
}

export function mergeEnv(
  env?: Record<string, string | undefined>,
): Record<string, string | undefined> {
  return { ...process.env, ...env }
}

function findBundledBinary(): string | undefined {
  const platformName = `${process.platform}-${process.arch}`
  const extension = process.platform === 'win32' ? '.exe' : ''
  const here = dirname(fileURLToPath(import.meta.url))
  const candidates = [
    join(here, 'bin', `git-stage-lines${extension}`),
    join(here, '..', 'bin', platformName, `git-stage-lines${extension}`),
  ]

  return candidates.find(isExecutableFile)
}

function findOnPath(command: string, env: Record<string, string | undefined>): string | undefined {
  if (command.includes('/') || command.includes('\\')) {
    return isExecutableFile(command) ? command : undefined
  }

  const pathValue = env.PATH ?? env.Path
  if (!pathValue) {
    return undefined
  }

  const extensions = process.platform === 'win32' ? windowsPathExtensions(env) : ['']
  for (const directory of pathValue.split(delimiter)) {
    if (!directory) continue

    for (const extension of extensions) {
      const candidate = resolve(directory, `${command}${extension}`)
      if (isExecutableFile(candidate)) {
        return candidate
      }
    }
  }

  return undefined
}

function windowsPathExtensions(env: Record<string, string | undefined>): string[] {
  const pathext = env.PATHEXT ?? '.EXE;.CMD;.BAT;.COM'
  return pathext.split(';').map((extension) => extension.toLowerCase())
}

function isExecutableFile(path: string): boolean {
  try {
    accessSync(path, constants.X_OK)
    return true
  } catch {
    return existsSync(path) && process.platform === 'win32' && isAbsolute(path)
  }
}
