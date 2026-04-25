import { chmodSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import {
  checkStageLines,
  dryRunStageLines,
  findBinary,
  GitStageLinesError,
  stageLines,
  stageLinesSync,
} from '../../src/npm/index'
import { normalizeRanges } from '../../src/npm/ranges'

const tempDirs: string[] = []

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { force: true, recursive: true })
  }
})

test('normalizes string and structured ranges', () => {
  expect(normalizeRanges(' 10-15, 22 , 40-45 ')).toBe('10-15,22,40-45')
  expect(normalizeRanges([[10, 15], 22, [40, 45]])).toBe('10-15,22,40-45')
})

test('rejects invalid ranges before spawning', () => {
  expect(() => normalizeRanges('')).toThrow(TypeError)
  expect(() => normalizeRanges('1,,2')).toThrow(TypeError)
  expect(() => normalizeRanges('0')).toThrow(TypeError)
  expect(() => normalizeRanges('5-3')).toThrow(TypeError)
  expect(() => normalizeRanges([])).toThrow(TypeError)
})

test('stageLines invokes the binary with normalized arguments', async () => {
  const dir = makeTempDir()
  const argsFile = join(dir, 'args.json')
  const binary = writeFakeBinary(
    dir,
    `
      const fs = require('node:fs')
      fs.writeFileSync(process.env.ARGS_FILE, JSON.stringify({
        argv: process.argv.slice(2),
        cwd: process.cwd(),
        env: process.env.TEST_ENV,
      }))
      process.stdout.write(JSON.stringify({
        status: 'staged',
        file: process.argv[2],
        ranges: [process.argv[3]],
        mode: process.argv[process.argv.indexOf('--mode') + 1],
        selected_changes: 1,
        skipped_changes: 2,
        patch_applied: true,
        would_apply: true,
      }))
    `,
  )

  const result = await stageLines({
    binaryPath: binary,
    cwd: realpathSync(dir),
    env: { ARGS_FILE: argsFile, TEST_ENV: 'adapter-test' },
    file: 'src/app.ts',
    ranges: [[10, 15], 22],
    mode: 'both',
    allowEmpty: true,
  })

  expect(result.status).toBe('staged')
  expect(readJson(argsFile)).toEqual({
    argv: ['src/app.ts', '10-15,22', '--mode', 'both', '--allow-empty', '--json'],
    cwd: realpathSync(dir),
    env: 'adapter-test',
  })
})

test('stageLinesSync parses successful JSON', () => {
  const dir = makeTempDir()
  const binary = writeFakeBinary(
    dir,
    `
      process.stdout.write(JSON.stringify({
        status: 'checked',
        file: process.argv[2],
        ranges: [process.argv[3]],
        mode: 'new',
        selected_changes: 1,
        skipped_changes: 0,
        patch_applied: false,
        would_apply: true,
      }))
    `,
  )

  const result = stageLinesSync({
    binaryPath: binary,
    file: 'src/app.ts',
    ranges: '4',
    check: true,
  })

  expect(result.status).toBe('checked')
})

test('check and dry-run helpers set their CLI flags', async () => {
  const dir = makeTempDir()
  const argsFile = join(dir, 'args.json')
  const binary = writeFakeBinary(
    dir,
    `
      const fs = require('node:fs')
      const calls = fs.existsSync(process.env.ARGS_FILE)
        ? JSON.parse(fs.readFileSync(process.env.ARGS_FILE, 'utf8'))
        : []
      calls.push(process.argv.slice(2))
      fs.writeFileSync(process.env.ARGS_FILE, JSON.stringify(calls))
      const dryRun = process.argv.includes('--dry-run')
      process.stdout.write(JSON.stringify({
        status: dryRun ? 'dry-run' : 'checked',
        file: process.argv[2],
        ranges: [process.argv[3]],
        mode: 'new',
        selected_changes: 1,
        skipped_changes: 0,
        patch_applied: false,
        would_apply: true,
        ...(dryRun ? { patch: 'patch text' } : {}),
      }))
    `,
  )

  await checkStageLines({
    binaryPath: binary,
    env: { ARGS_FILE: argsFile },
    file: 'src/app.ts',
    ranges: '4',
  })
  await dryRunStageLines({
    binaryPath: binary,
    env: { ARGS_FILE: argsFile },
    file: 'src/app.ts',
    ranges: '4',
  })

  expect(readJson(argsFile)).toEqual([
    ['src/app.ts', '4', '--mode', 'new', '--check', '--json'],
    ['src/app.ts', '4', '--mode', 'new', '--dry-run', '--json'],
  ])
})

test('returns CLI JSON errors instead of throwing', async () => {
  const dir = makeTempDir()
  const binary = writeFakeBinary(
    dir,
    `
      process.stdout.write(JSON.stringify({
        status: 'error',
        reason: 'range_does_not_overlap_any_change',
        message: 'no match',
        file: process.argv[2],
        ranges: [process.argv[3]],
      }))
      process.exit(2)
    `,
  )

  const result = await stageLines({
    binaryPath: binary,
    file: 'src/app.ts',
    ranges: '99',
  })

  expect(result).toMatchObject({
    status: 'error',
    reason: 'range_does_not_overlap_any_change',
    exit_code: 2,
  })
})

test('throws structured errors for malformed JSON', async () => {
  const dir = makeTempDir()
  const binary = writeFakeBinary(
    dir,
    `
      process.stdout.write('not json')
    `,
  )

  await expect(
    stageLines({
      binaryPath: binary,
      file: 'src/app.ts',
      ranges: '4',
    }),
  ).rejects.toMatchObject({
    name: 'GitStageLinesError',
    reason: 'malformed_json',
  })
})

test('throws structured errors when the binary cannot execute', async () => {
  await expect(
    stageLines({
      binaryPath: '/definitely/missing/git-stage-lines',
      file: 'src/app.ts',
      ranges: '4',
    }),
  ).rejects.toBeInstanceOf(GitStageLinesError)
})

test('classifies missing git subcommand fallback as binary_not_found', async () => {
  const dir = makeTempDir()
  const git = join(dir, 'git')
  writeFileSync(git, '#!/bin/sh\necho "git: \'stage-lines\' is not a git command." >&2\nexit 1\n')
  chmodSync(git, 0o755)

  await expect(
    stageLines({
      env: { PATH: dir },
      file: 'src/app.ts',
      ranges: '4',
    }),
  ).rejects.toMatchObject({
    reason: 'binary_not_found',
  })
})

test('findBinary honors GIT_STAGE_LINES_BINARY and PATH', () => {
  const dir = makeTempDir()
  const binary = writeFakeBinary(dir, `process.stdout.write('{}')`)
  expect(findBinary({ env: { GIT_STAGE_LINES_BINARY: binary } })).toBe(binary)

  const pathBinary = join(
    dir,
    process.platform === 'win32' ? 'git-stage-lines.cmd' : 'git-stage-lines',
  )
  writeFileSync(pathBinary, '#!/usr/bin/env sh\nexit 0\n')
  chmodSync(pathBinary, 0o755)
  expect(findBinary({ env: { PATH: dir } })).toBe(pathBinary)
})

function makeTempDir(): string {
  const dir = mkdtempSync(join(tmpdir(), 'git-stage-lines-npm-'))
  tempDirs.push(dir)
  return dir
}

function writeFakeBinary(dir: string, body: string): string {
  const binary = join(dir, 'fake-git-stage-lines.cjs')
  writeFileSync(binary, `#!/usr/bin/env node\n${body}\n`)
  chmodSync(binary, 0o755)
  return binary
}

function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, 'utf8'))
}
