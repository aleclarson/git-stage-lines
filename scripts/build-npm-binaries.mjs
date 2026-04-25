#!/usr/bin/env node
import { chmodSync, copyFileSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const root = fileURLToPath(new URL('..', import.meta.url))
const distBin = join(root, 'dist', 'bin')
const cacheRoot = join(root, '.zig-cache', 'npm-binaries')

const targets = [
  { packageName: 'darwin-arm64', zigTarget: 'aarch64-macos' },
  { packageName: 'darwin-x64', zigTarget: 'x86_64-macos' },
  { packageName: 'linux-arm64', zigTarget: 'aarch64-linux-musl' },
  { packageName: 'linux-x64', zigTarget: 'x86_64-linux-musl' },
  { packageName: 'win32-arm64', zigTarget: 'aarch64-windows', exe: 'git-stage-lines.exe' },
  { packageName: 'win32-x64', zigTarget: 'x86_64-windows', exe: 'git-stage-lines.exe' },
]

const requestedTargets = new Set(process.argv.slice(2))
const selectedTargets =
  requestedTargets.size === 0
    ? targets
    : targets.filter((target) => requestedTargets.has(target.packageName))

if (selectedTargets.length !== targets.length && selectedTargets.length !== requestedTargets.size) {
  const knownTargets = targets.map((target) => target.packageName).join(', ')
  throw new Error(`Unknown npm binary target. Known targets: ${knownTargets}`)
}

rmSync(distBin, { force: true, recursive: true })

for (const target of selectedTargets) {
  const exeName = target.exe ?? 'git-stage-lines'
  const prefix = join(cacheRoot, target.packageName)

  rmSync(prefix, { force: true, recursive: true })
  run('zig', [
    'build',
    '-Doptimize=ReleaseSafe',
    `-Dtarget=${target.zigTarget}`,
    '--prefix',
    prefix,
  ])

  const builtBinary = join(prefix, 'bin', exeName)
  const packageBinary = join(distBin, target.packageName, exeName)
  mkdirSync(dirname(packageBinary), { recursive: true })
  copyFileSync(builtBinary, packageBinary)
  chmodSync(packageBinary, 0o755)
  console.log(`built ${target.packageName}`)
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    shell: false,
    stdio: 'inherit',
  })

  if (result.error) {
    throw result.error
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1)
  }
}
