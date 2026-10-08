-- Pure Lua conflict marker parser.
--
-- This module has no Neovim dependencies so it can be unit tested with any
-- Lua interpreter (see tests/test.lua). It recognises three conflict styles:
--
--   git         <<<<<<< / ||||||| / ======= / >>>>>>>
--   jj_snapshot <<<<<<< / +++++++ / ------- / >>>>>>>  (jj default markers)
--   jj_diff     <<<<<<< / %%%%%%% / +++++++ / >>>>>>>  (jj diff markers)
--
-- All line numbers are 1-based, matching ipairs() over buffer lines.

local M = {}

-- jj and git both use exactly seven marker characters. Each pattern matches
-- seven or more of `char` at the start of a line: six escaped literals plus
-- a final one quantified with `+`. The `%` escapes are required because `-`,
-- `+` and `%` are magic in Lua patterns: a bare `-` or `+` is a quantifier,
-- so `^-------+` would accidentally match any line starting with a single `-`.
local function marker_pattern(char)
  local escaped = '%' .. char
  return '^' .. escaped:rep(6) .. escaped .. '+'
end

---Marker line patterns, keyed by role.
---@type table<string, string>
M.MARKERS = {
  start = marker_pattern('<'),
  diff = marker_pattern('%'),
  base = marker_pattern('-'),
  ancestor = marker_pattern('|'),
  middle = marker_pattern('='),
  snapshot = marker_pattern('+'),
  finish = marker_pattern('>'),
}

---@class jj_conflict_highlight.Range
---@field start integer 1-based first line (inclusive)
---@field finish integer 1-based last line (inclusive)

---@class jj_conflict_highlight.Conflict
---@field style 'git'|'jj_snapshot'|'jj_diff'
---@field start_marker integer line of `<<<<<<<`
---@field finish_marker integer line of `>>>>>>>`
---@field snapshot_markers? integer[] lines of `+++++++` markers (jj styles)
---@field snapshots? jj_conflict_highlight.Range[] contents of each snapshot side
---@field base_marker? integer line of `------- Contents of base` (jj_snapshot)
---@field base? jj_conflict_highlight.Range contents of the base
---@field diff_markers? integer[] lines of `%%%%%%%` markers (jj_diff)
---@field diff? jj_conflict_highlight.Range[] diff hunks (base to side #1)
---@field ancestor_marker? integer line of `|||||||` (git)
---@field ancestor? jj_conflict_highlight.Range common ancestor contents
---@field middle_marker? integer line of `=======` (git)
---@field current? jj_conflict_highlight.Range current side contents
---@field incoming? jj_conflict_highlight.Range incoming side contents

---Detect conflict blocks in a list of buffer lines.
---
---A conflict starts at a `<<<<<<<` marker and ends at the matching `>>>>>>>`
---marker. The style is decided by the line following the start marker: a
---`%%%%%%%` line starts a jj diff-style conflict, a `+++++++` line a jj
---snapshot-style conflict, anything else a git-style conflict. Conflicts
---that are never terminated are ignored.
---@param lines string[] buffer lines
---@return jj_conflict_highlight.Conflict[]
function M.detect_conflicts(lines)
  local conflicts = {}
  ---@type jj_conflict_highlight.Conflict?
  local cur = nil
  ---@type integer?, string?
  local region_start, region_kind = nil, nil

  -- Close the open region at `marker_line`, recording its range if it is
  -- not empty.
  local function close_region(marker_line)
    if region_kind and region_start and region_start <= marker_line - 1 then
      local range = { start = region_start, finish = marker_line - 1 }
      if region_kind == 'snapshot' then
        table.insert(cur.snapshots, range)
      elseif region_kind == 'base' then
        cur.base = range
      elseif region_kind == 'diff' then
        table.insert(cur.diff, range)
      elseif region_kind == 'current' then
        cur.current = range
      elseif region_kind == 'ancestor' then
        cur.ancestor = range
      elseif region_kind == 'incoming' then
        cur.incoming = range
      end
    end
    region_start, region_kind = nil, nil
  end

  for i, line in ipairs(lines) do
    if not cur then
      if line:match(M.MARKERS.start) then
        cur = { start_marker = i }
        -- lines[i + 1] may not exist when the start marker is the last line
        local next_line = lines[i + 1] or ''
        if next_line:match(M.MARKERS.diff) then
          cur.style = 'jj_diff'
          cur.diff_markers = {}
          cur.diff = {}
          cur.snapshot_markers = {}
          cur.snapshots = {}
        elseif next_line:match(M.MARKERS.snapshot) then
          cur.style = 'jj_snapshot'
          cur.snapshot_markers = {}
          cur.snapshots = {}
        else
          cur.style = 'git'
          region_start, region_kind = i + 1, 'current'
        end
      end
    elseif line:match(M.MARKERS.finish) then
      close_region(i)
      cur.finish_marker = i
      conflicts[#conflicts + 1] = cur
      cur = nil
    elseif cur.style == 'git' then
      if line:match(M.MARKERS.ancestor) then
        close_region(i)
        cur.ancestor_marker = i
        region_start, region_kind = i + 1, 'ancestor'
      elseif line:match(M.MARKERS.middle) then
        close_region(i)
        cur.middle_marker = i
        region_start, region_kind = i + 1, 'incoming'
      end
    elseif line:match(M.MARKERS.snapshot) then
      cur.snapshot_markers[#cur.snapshot_markers + 1] = i
      close_region(i)
      region_start, region_kind = i + 1, 'snapshot'
    elseif cur.style == 'jj_snapshot' and line:match(M.MARKERS.base) then
      close_region(i)
      cur.base_marker = i
      region_start, region_kind = i + 1, 'base'
    elseif cur.style == 'jj_diff' and line:match(M.MARKERS.diff) then
      close_region(i)
      cur.diff_markers[#cur.diff_markers + 1] = i
      region_start, region_kind = i + 1, 'diff'
    end
  end

  return conflicts
end

return M
