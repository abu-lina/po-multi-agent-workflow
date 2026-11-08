import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'

const __dirname = dirname(fileURLToPath(import.meta.url))
const LANE = resolve(__dirname, '../../scripts/lane')

function runLane(args: string[]) {
  const r = spawnSync('bash', [LANE, ...args], { encoding: 'utf8' })
  return { stderr: r.stderr?.trim() ?? '', stdout: r.stdout?.trim() ?? '', status: r.status ?? 1 }
}

const INVALID_AGENTS = ['gpt', 'gemini', 'bot', 'agent', 'COPILOT', 'DEVIN', 'CLAUDE']
const AGENT_ERROR = 'agent must be claude, copilot, devin, or opencode'

describe('lane start: rejects invalid agent', () => {
  for (const bad of INVALID_AGENTS) {
    test(`agent "${bad}"`, () => {
      const { stderr, status } = runLane(['start', '123', 'my-slug', bad])
      expect(stderr).toBe(AGENT_ERROR)
      expect(status).toBe(1)
    })
  }
})

test('lane start: opencode is a valid agent', () => {
  const { stderr } = runLane(['start', '123', 'my-slug', 'opencode'])
  expect(stderr).not.toContain('agent must be')
})

describe('foreman: command is removed', () => {
  for (const agent of ['claude', 'copilot', 'devin', ...INVALID_AGENTS]) {
    test(`foreman ${agent} exits 2 (unknown command)`, () => {
      const { status } = runLane(['foreman', agent])
      expect(status).toBe(2)
    })
  }
})

// Worktree root is 2 dirs up from tests/scripts/; it lives inside .worktrees/ so the
// guard fires even when vitest is invoked from a different working directory.
const WORKTREE_DIR = resolve(__dirname, '../..')

test('lane done: errors when run from a worktree', () => {
  const r = spawnSync('bash', [LANE, 'done', '999'], { encoding: 'utf8', cwd: WORKTREE_DIR })
  expect(r.stderr?.trim()).toBe('run lane_done from the main checkout')
  expect(r.status).toBe(1)
})

test('lane start: errors when run from a worktree', () => {
  const r = spawnSync('bash', [LANE, 'start', '999', 'slug'], { encoding: 'utf8', cwd: WORKTREE_DIR })
  expect(r.stderr?.trim()).toBe('run lane from the main checkout, not a worktree')
  expect(r.status).toBe(1)
})
