-- Test suite for jj-conflict-highlight.nvim.
--
-- Run from the repository root:
--   nvim --headless -l tests/test.lua
--
-- Exits with status 1 if any test fails.

local root = (arg and arg[0] or ''):match('^(.*)tests[/\\]test%.lua$')
if not root or root == '' then root = vim.fn.getcwd() .. '/' end

-- Neovim resolves modules from the runtimepath before package.path, so an
-- installed copy of this plugin would shadow the repository. Put the
-- repository first so the code under test is the one in this checkout.
vim.opt.runtimepath:prepend(root)

package.path = root .. 'lua/?.lua;' .. root .. 'tests/?.lua;' .. package.path

local inspect = require('lib.inspect')
local parse = require('jj_conflict_highlight.parse')
local plugin = require('jj_conflict_highlight')

local api = vim.api
local failures = 0

local function eq(actual, expected, msg)
  if vim.deep_equal(actual, expected) then return end
  failures = failures + 1
  print('FAIL: ' .. msg)
  print('  expected: ' .. inspect(expected))
  print('  actual:   ' .. inspect(actual))
end

-- Split a multiline string into lines, keeping empty lines.
local function lines_of(s)
  local lines = {}
  for line in (s .. '\n'):gmatch('(.-)\n') do
    lines[#lines + 1] = line
  end
  return lines
end

-- ---------------------------------------------------------------- parser --

do
  local conflicts = parse.detect_conflicts(lines_of([[
<<<<<<< Conflict 1 of 1
+++++++ Contents of side #1
apple
grapefruit
orange
------- Contents of base
apple
grape
orange
+++++++ Contents of side #2
tkel
>>>>>>> Conflict 1 of 1 ends
]]))
  eq(#conflicts, 1, 'jj_snapshot: one conflict found')
  eq(conflicts[1], {
    style = 'jj_snapshot',
    start_marker = 1,
    finish_marker = 12,
    snapshot_markers = { 2, 10 },
    snapshots = { { start = 3, finish = 5 }, { start = 11, finish = 11 } },
    base_marker = 6,
    base = { start = 7, finish = 9 },
  }, 'jj_snapshot: conflict parsed')
end

do
  local conflicts = parse.detect_conflicts(lines_of([[
<<<<<<< Conflict 1 of 1
%%%%%%% Contents of side #1
 apple
 grapefruit
-orange
+Orange
+++++++ Contents of side #2
APPLE
GRAPE
ORANGE
>>>>>>> Conflict 1 of 1 ends
]]))
  eq(#conflicts, 1, 'jj_diff: one conflict found')
  eq(conflicts[1], {
    style = 'jj_diff',
    start_marker = 1,
    finish_marker = 11,
    diff_markers = { 2 },
    diff = { { start = 3, finish = 6 } },
    snapshot_markers = { 7 },
    snapshots = { { start = 8, finish = 10 } },
  }, 'jj_diff: conflict parsed')
end

do
  local conflicts = parse.detect_conflicts(lines_of([[
<<<<<<< HEAD
ours
||||||| merged common ancestors
original
=======
theirs
>>>>>>> other-branch
]]))
  eq(#conflicts, 1, 'git with ancestor: one conflict found')
  eq(conflicts[1], {
    style = 'git',
    start_marker = 1,
    finish_marker = 7,
    ancestor_marker = 3,
    ancestor = { start = 4, finish = 4 },
    middle_marker = 5,
    current = { start = 2, finish = 2 },
    incoming = { start = 6, finish = 6 },
  }, 'git with ancestor: conflict parsed')
end

do
  local conflicts = parse.detect_conflicts(lines_of([[
<<<<<<< HEAD
ours
=======
theirs
>>>>>>> other-branch
]]))
  eq(conflicts[1], {
    style = 'git',
    start_marker = 1,
    finish_marker = 5,
    middle_marker = 3,
    current = { start = 2, finish = 2 },
    incoming = { start = 4, finish = 4 },
  }, 'git without ancestor: conflict parsed')
end

-- Regression test: content lines starting with `-` or `+` (markdown
-- bullets, diff lines) must not be mistaken for `-------`/`+++++++` markers.
do
  local conflicts = parse.detect_conflicts(lines_of([[
<<<<<<< Conflict 1 of 1
+++++++ Contents of side #1
- a bullet point
+ an added line
------- Contents of base
base line
+++++++ Contents of side #2
side two
>>>>>>> Conflict 1 of 1 ends
]]))
  eq(conflicts[1], {
    style = 'jj_snapshot',
    start_marker = 1,
    finish_marker = 9,
    snapshot_markers = { 2, 7 },
    snapshots = { { start = 3, finish = 4 }, { start = 8, finish = 8 } },
    base_marker = 5,
    base = { start = 6, finish = 6 },
  }, 'jj_snapshot with dash/plus content lines: conflict parsed')
end

-- Multiple conflicts of mixed styles in one buffer.
do
  local conflicts = parse.detect_conflicts(lines_of([[
teststring
<<<<<<< Conflict 1 of 1
+++++++ Contents of side #1
apple
+++++++ Contents of side #2
>>>>>>> Conflict 1 of 1 ends
endspaceer
<<<<<<< Conflict 1 of 1
%%%%%%% Contents of side #1
 apple
-orange
+Orange
+++++++ Contents of side #2
APPLE
>>>>>>> Conflict 1 of 1 ends
teststring
]]))
  eq(#conflicts, 2, 'multiple conflicts: two found')
  eq(conflicts[1].style, 'jj_snapshot', 'multiple conflicts: first is jj_snapshot')
  eq(conflicts[1].finish_marker, 6, 'multiple conflicts: first finish marker')
  eq(conflicts[2].style, 'jj_diff', 'multiple conflicts: second is jj_diff')
  eq(conflicts[2].start_marker, 8, 'multiple conflicts: second start marker')
  eq(conflicts[2].diff, { { start = 10, finish = 12 } }, 'multiple conflicts: second diff range')
end

-- Edge cases.
do
  eq(parse.detect_conflicts({ '<<<<<<<' }), {}, 'start marker as last line: no crash, no conflict')
  eq(parse.detect_conflicts({ '<<<<<<<', 'content' }), {}, 'unterminated conflict is ignored')
  eq(parse.detect_conflicts({ 'plain text' }), {}, 'no markers: no conflicts')
  eq(parse.detect_conflicts({}), {}, 'empty buffer: no conflicts')
  eq(parse.detect_conflicts({ '>>>>>>>' }), {}, 'stray finish marker: no conflicts')
end

-- ------------------------------------------------------------- highlights --

local HL_NAMES = {
  'JjConflictCurrent',
  'JjConflictIncoming',
  'JjConflictAncestor',
  'JjConflictDiff',
  'JjConflictSnapshot',
  'JjConflictBase',
}

local hl_ids = {}

-- Extmarks of the plugin namespace as { first, last, hl } line ranges
-- (1-based, both inclusive), sorted by position.
local function extmarks(bufnr)
  local ns = api.nvim_create_namespace('jj-conflict-highlight')
  local marks = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
    local hl = m[4].hl_group
    if type(hl) == 'number' then hl = hl_ids[hl] or ('unknown:' .. hl) end
    marks[#marks + 1] = { first = m[2] + 1, last = m[4].end_row, hl = hl }
  end
  table.sort(marks, function(a, b)
    if a.first ~= b.first then return a.first < b.first end
    return a.last < b.last
  end)
  return marks
end

local function make_buffer(lines)
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

plugin.setup()
for _, name in ipairs(HL_NAMES) do
  hl_ids[vim.fn.hlID(name)] = name
  local hl = api.nvim_get_hl(0, { name = name })
  eq(hl.bg ~= nil, true, 'setup defines background for ' .. name)
end

do
  local bufnr = make_buffer(lines_of([[
<<<<<<< Conflict 1 of 1
%%%%%%% Contents of side #1
 apple
 grapefruit
-orange
+Orange
+++++++ Contents of side #2
APPLE
GRAPE
ORANGE
>>>>>>> Conflict 1 of 1 ends
]]))
  plugin.highlight(bufnr)
  eq(extmarks(bufnr), {
    { first = 1, last = 1, hl = 'JjConflictAncestor' },
    { first = 2, last = 2, hl = 'JjConflictAncestor' },
    { first = 3, last = 6, hl = 'JjConflictCurrent' },
    { first = 7, last = 7, hl = 'JjConflictAncestor' },
    { first = 8, last = 10, hl = 'JjConflictDiff' },
    { first = 11, last = 11, hl = 'JjConflictAncestor' },
  }, 'jj_diff: extmarks applied')
  plugin.highlight(bufnr)
  eq(#extmarks(bufnr), 6, 'jj_diff: highlighting twice does not duplicate extmarks')
  plugin.clear(bufnr)
  eq(extmarks(bufnr), {}, 'clear removes all extmarks')
  plugin.highlight(bufnr)
  eq(#extmarks(bufnr), 6, 'highlight works again after clear')
  api.nvim_buf_delete(bufnr, { force = true })
end

do
  local bufnr = make_buffer(lines_of([[
<<<<<<< HEAD
ours
||||||| merged common ancestors
original
=======
theirs
>>>>>>> other-branch
]]))
  plugin.highlight(bufnr)
  eq(extmarks(bufnr), {
    { first = 1, last = 1, hl = 'JjConflictAncestor' },
    { first = 2, last = 2, hl = 'JjConflictCurrent' },
    { first = 3, last = 3, hl = 'JjConflictAncestor' },
    { first = 4, last = 4, hl = 'JjConflictAncestor' },
    { first = 5, last = 5, hl = 'JjConflictAncestor' },
    { first = 6, last = 6, hl = 'JjConflictIncoming' },
    { first = 7, last = 7, hl = 'JjConflictAncestor' },
  }, 'git style: extmarks applied')
  api.nvim_buf_delete(bufnr, { force = true })
end

do
  local bufnr = make_buffer({ 'no conflicts here' })
  plugin.highlight(bufnr)
  eq(extmarks(bufnr), {}, 'buffer without conflicts gets no extmarks')
  api.nvim_buf_delete(bufnr, { force = true })
end

-- The decoration provider refreshes highlights on redraw, but only for
-- buffers whose contents changed. Uses an internal API; skip when absent.
if api.nvim__redraw then
  local bufnr = api.nvim_get_current_buf()
  local lines = {
    'text before',
    '<<<<<<< conflict 1 of 1',
    '+++++++ side 1',
    'apple',
    '------- base',
    'grape',
    '+++++++ side 2',
    'APPLE',
    '>>>>>>> conflict 1 of 1 ends',
    'text after',
  }
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  api.nvim__redraw({ flush = true })
  eq(#extmarks(bufnr), 8, 'provider applies highlights on redraw')

  api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'inserted line' })
  api.nvim__redraw({ flush = true })
  eq(#extmarks(bufnr), 8, 'provider refreshes highlights after an edit')

  api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'resolved file' })
  api.nvim__redraw({ flush = true })
  eq(extmarks(bufnr), {}, 'provider clears highlights when conflicts are resolved')

  plugin.clear(bufnr)
  api.nvim__redraw({ flush = true })
  eq(extmarks(bufnr), {}, 'clear keeps highlights off across redraws')
end

-- ------------------------------------------------------------------ done --

if failures > 0 then
  print(('%d test(s) FAILED'):format(failures))
  os.exit(1)
end
print('all tests passed')
