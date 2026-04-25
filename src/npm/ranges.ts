import type { StageLinesRange } from './types'

export function normalizeRanges(ranges: string | StageLinesRange[]): string {
  if (typeof ranges === 'string') {
    return normalizeRangeString(ranges)
  }

  if (!Array.isArray(ranges) || ranges.length === 0) {
    throw new TypeError('ranges must not be empty')
  }

  return ranges.map(normalizeStructuredRange).join(',')
}

function normalizeRangeString(input: string): string {
  const trimmed = input.trim()
  if (trimmed.length === 0) {
    throw new TypeError('ranges must not be empty')
  }

  return trimmed
    .split(',')
    .map((part) => normalizeRangeToken(part.trim()))
    .join(',')
}

function normalizeRangeToken(part: string): string {
  if (part.length === 0) {
    throw new TypeError('range entries must not be empty')
  }

  const pieces = part.split('-')
  if (pieces.length === 1) {
    return String(parseLine(pieces[0]))
  }

  if (pieces.length !== 2) {
    throw new TypeError('ranges must use LINE or START-END forms')
  }

  const start = parseLine(pieces[0])
  const end = parseLine(pieces[1])
  if (start > end) {
    throw new TypeError('range start must be less than or equal to range end')
  }

  return start === end ? String(start) : `${start}-${end}`
}

function normalizeStructuredRange(range: StageLinesRange): string {
  if (typeof range === 'number') {
    return String(validateLine(range))
  }

  if (!Array.isArray(range) || range.length !== 2) {
    throw new TypeError('structured ranges must be line numbers or [start, end] tuples')
  }

  const start = validateLine(range[0])
  const end = validateLine(range[1])
  if (start > end) {
    throw new TypeError('range start must be less than or equal to range end')
  }

  return start === end ? String(start) : `${start}-${end}`
}

function parseLine(raw: string): number {
  if (!/^[0-9]+$/.test(raw)) {
    throw new TypeError('range lines must be positive integers')
  }

  return validateLine(Number(raw))
}

function validateLine(value: number): number {
  if (!Number.isInteger(value) || value <= 0 || !Number.isSafeInteger(value)) {
    throw new TypeError('range lines must be positive integers')
  }

  return value
}
