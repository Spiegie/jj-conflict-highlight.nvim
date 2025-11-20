-- lua/jj-conflict.lua
-- Minimal Neovim plugin to highlight Jujutsu-style conflicts in the current buffer only.

local api = vim.api
local M = {}

local bit = require('bit')

---@class Range
---@field start integer
---@field finish integer

---@class ConflictGitStyle
---@field start_marker integer
---@field ancestor? Range
---@field ancestor_marker? integer
---@field current Range
---@field middle_marker integer
---@field incoming Range
---@field finish_marker integer

---@class ConflictJjStyle
---@field start_marker integer
---@field diff_marker? integer
---@field diff? Range
---@field base_marker integer
---@field base Range
---@field snapshot_markers integer[]
---@field snapshots Range[]
---@field finish_marker integer

local NAMESPACE = api.nvim_create_namespace('jj-conflict-highlight')
local PRIORITY = vim.highlight.priorities.user

local sep = package.config:sub(1,1)

-- Default regex markers (covers common Jujutsu variants and Git-like markers)
local MARKERS = {
  start = '^<<<<<<<+',         -- start of a side
  diff = '^%%%%%%%%%%%%%%+',           -- jj conflict header (e.g. "%%%%%% conflict ...")
  base = '^-------+',          -- start of a side
  ancestor = '^|||||||+',      -- ancestor/base marker
  middle = '^=======+',        -- divider between sides
  snapshot = '^++++++++',      -- snapshot
  finish = '^>>>>>>>+',        -- end of conflict
}

-- Highlight group names used internally
local CURRENT_HL = 'JjConflictCurrent'
local INCOMING_HL = 'JjConflictIncoming'
local ANCESTOR_HL = 'JjConflictAncestor'
local DIFF_HL = 'JjConflictDiff'
local SNAPSHOT_HL = 'JjConflictSnapshot'
local BASE_HL = 'JjConflictBase'
local CURRENT_LABEL_HL = 'JjConflictCurrentLabel'
local INCOMING_LABEL_HL = 'JjConflictIncomingLabel'
local ANCESTOR_LABEL_HL = 'JjConflictAncestorLabel'
local SNAPSHOT_LABEL_HL = 'JjConflictSnapshotLabel'
local BASE_LABEL_HL = 'JjConflictBaseLabel'

local DEFAULT_HLS = {
  current = 'DiffText',
  incoming = 'DiffAdd',
  ancestor = 'DiffChange',
  snapshot = 'DiffSnapshot',
  base = 'DiffBase',
}

local DEFAULT_CURRENT_BG_COLOR = 4218238  -- #405d7e
local DEFAULT_INCOMING_BG_COLOR = 3229523 -- #314753
local DEFAULT_ANCESTOR_BG_COLOR = 6824314 -- #68217A
local DEFAULT_SNAPSHOT_BG_COLOR = 6824314 -- #68217A
local DEFAULT_BASE_BG_COLOR = 6824314 -- #68217A

-- Small util to read the full buffer lines
local function get_buf_lines(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  return api.nvim_buf_get_lines(bufnr, 0, -1, false)
end


local function detect_conflicts(lines)
  local positions = {}
  local position = {}
  local has_start = false
  local regionstart = 0
  local regiontype = ""
  local conflict_style = ""

  for i, line in ipairs(lines) do
    -- detect start by <<<<<<< marker

    if line:match(MARKERS.start) then
      has_start = true
      position.start_marker = i
      -- We found a conflict block. 
      -- look ahead, if lines[i+1] is diff or snapshot marker
      if lines[i+1]:match(MARKERS.diff) then
        position.snapshot_markers = {}
        position.snapshots = {}
        position.diff = {}
        conflict_style = "jj_diff"
      elseif lines[i+1]:match(MARKERS.snapshot) then
        position.snapshot_markers = {}
        position.snapshots = {}
        position.base = {}
        conflict_style = "jj_snapshot"
      else

        conflict_style = "git_style"
      end
    end
    if has_start and line:match(MARKERS.snapshot) and ( conflict_style == "jj_snapshot" or conflict_style == "jj_diff" ) then
      table.insert(position.snapshot_markers, i)
      if regionstart ~= 0 and regiontype == "base" and regionstart ~= i then
        position.base = {start = regionstart, finish = i-1}
      end
      if regionstart ~= 0 and regiontype == "diff" and regionstart ~= i then
        position.diff = {start = regionstart, finish = i-1}
      end
      if regionstart ~= 0 and regiontype == "snapshot" and regionstart ~= i then
        table.insert(position.snapshots, {start = regionstart, finish = i-1})
      end
      regionstart = i+1
      regiontype = "snapshot"
    end
    if has_start and line:match(MARKERS.base) and conflict_style == "jj_snapshot" then
      position.base_marker = i
      if regionstart ~= 0 and regiontype == "snapshot" and regionstart ~= i then
        table.insert(position.snapshots, {start = regionstart, finish = i-1})
      end
      regionstart = i+1
      regiontype = "base"
    end
    if has_start and line:match(MARKERS.diff) and conflict_style == "jj_diff" then
      position.diff_marker = i
      regionstart = i+1
      regiontype = "diff"
    end
    if has_start and line:match(MARKERS.finish) then
      position.finish_marker = i
      if regionstart ~= 0 and regiontype == "snapshot" and regionstart ~= i then
        table.insert(position.snapshots, {start = regionstart, finish = i-1})
      end
      position.conflict_style = conflict_style
      table.insert(positions, position)
      has_start = false
      position = {}
      regionstart = 0
    end
  end
  return positions
end


-- Helper to set extmark for a range with highlight.
local function hl_range(bufnr, hl, range_start, range_end)
  if not range_start or not range_end then return end
  return api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_start, 0, {
    hl_group = hl,
    hl_eol = true,
    hl_mode = 'combine',
    end_row = range_end,
    priority = PRIORITY,
  })
end

-- Draw a label overlay on the given line
local function draw_section_label(bufnr, hl_group, label, lnum)
  if not lnum then return end
  -- compute remaining space; if we can't get window width, just use a reasonable pad
  local ok, width = pcall(api.nvim_win_get_width, 0)
  local remaining_space = (ok and (width - vim.fn.strdisplaywidth(label))) or 20
  if remaining_space < 1 then remaining_space = 1 end
  local virt = label .. string.rep(' ', remaining_space)
  return api.nvim_buf_set_extmark(bufnr, NAMESPACE, lnum, 0, {
    hl_group = hl_group,
    virt_text = { { virt, hl_group } },
    virt_text_pos = 'overlay',
    priority = PRIORITY,
  })
end

-- Apply highlights for all detected positions in the current buffer
local function highlight_conflicts(bufnr, positions, lines)
  bufnr = bufnr or api.nvim_get_current_buf()
  -- clear previous
  api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)

  for _, pos in ipairs(positions) do
--    local current_start = pos.current.range_start
--    local current_end = pos.current.range_end
--    local incoming_start = pos.incoming.range_start
--    local incoming_end = pos.incoming.range_end
--
--    -- create extmarks
--    local curr_id = hl_range(bufnr, CURRENT_HL, current_start, current_end + 1)
--    local inc_id = hl_range(bufnr, INCOMING_HL, incoming_start, incoming_end + 1)
--
--    if not vim.tbl_isempty(pos.ancestor or {}) then
--      local ancestor_start = pos.ancestor.range_start
--      local ancestor_end = pos.ancestor.range_end
--      local id = hl_range(bufnr, ANCESTOR_HL, ancestor_start + 1, ancestor_end + 1)
--    end
    -- highlight markers
    -- snapshotmarker
    if pos.snapshot_markers ~= nil then
      for _, snapshot_marker in ipairs(pos.snapshot_markers) do
        local snapshot_marker_id = hl_range(bufnr, ANCESTOR_HL, snapshot_marker-1, snapshot_marker)
      end
    end
    -- basemarker
    if pos["base_marker"] ~= nil then
      local base_marker_id = hl_range(bufnr, ANCESTOR_HL, pos.base_marker-1, pos.base_marker)
    end
    -- diffmarker
    if pos["diff_marker"] ~= nil then
      local diff_marker_id = hl_range(bufnr, ANCESTOR_HL, pos.diff_marker-1, pos.diff_marker)
    end
    -- startmarker
    local start_marker_id = hl_range(bufnr, ANCESTOR_HL, pos.start_marker-1, pos.start_marker)
    -- finishmarker
    local finish_marker_id = hl_range(bufnr, ANCESTOR_HL, pos.finish_marker-1, pos.finish_marker)

    -- highlight regions
    -- snapshot
    if pos.snapshots ~= nil then
      for _, snapshot_region in ipairs(pos.snapshots) do
        local snapshot_region_id = hl_range(bufnr, DIFF_HL, snapshot_region.start-1, snapshot_region.finish)
      end
    end
    -- base
    if pos["base"] ~= nil then
      if pos.base["start"] ~= nil and pos.base["finish"] ~= nil then
        local base_region_id = hl_range(bufnr, CURRENT_HL, pos.base.start-1, pos.base.finish)
      end
    end
    -- diff
    if pos["diff"] ~= nil then
      if pos.diff["start"] ~= nil and pos.diff["finish"] ~= nil then
        local diff_region_id = hl_range(bufnr, CURRENT_HL, pos.diff.start-1, pos.diff.finish)
      end
    end
  end
end

-- Configure highlight group colors (derives background from user groups where possible)
local function set_highlights(user_hls)
  user_hls = user_hls or DEFAULT_HLS
  local function get_hl(name)
    if not name then return {} end
    local ok, tbl = pcall(vim.api.nvim_get_hl_by_name, name, true)
    return ok and tbl or {}
  end

  local current_color = get_hl(user_hls.current)
  local incoming_color = get_hl(user_hls.incoming)
  local ancestor_color = get_hl(user_hls.ancestor)
  local snapshot_color = get_hl(user_hls.snapshot)
  local base_color = get_hl(user_hls.base)

  local current_bg = current_color.background or DEFAULT_CURRENT_BG_COLOR
  local incoming_bg = incoming_color.background or DEFAULT_INCOMING_BG_COLOR
  local ancestor_bg = ancestor_color.background or DEFAULT_ANCESTOR_BG_COLOR
  local snapshot_bg = snapshot_color.background or DEFAULT_SNAPSHOT_BG_COLOR
  local base_bg = base_color.background or DEFAULT_BASE_BG_COLOR

  local function shade_color(col, amount)
    amount = amount or 60
    local r = bit.rshift(bit.band(col, 0xFF0000), 16)
    local g = bit.rshift(bit.band(col, 0x00FF00), 8)
    local b = bit.band(col, 0x0000FF)
    local function s(c)
      local v = math.floor(c * (100 - amount) / 100)
      if v < 0 then v = 0 end
      return v
    end
    return (s(r) * 0x10000) + (s(g) * 0x100) + s(b)
  end

  local current_label_bg = shade_color(current_bg, 60)
  local incoming_label_bg = shade_color(incoming_bg, 60)
  local ancestor_label_bg = shade_color(ancestor_bg, 60)
  local snapshot_label_bg = shade_color(snapshot_bg, 60)
  local base_label_bg = shade_color(base_bg, 60)

  api.nvim_set_hl(0, CURRENT_HL, { background = current_bg, bold = true, default = true })
  api.nvim_set_hl(0, INCOMING_HL, { background = incoming_bg, bold = true, default = true })
  api.nvim_set_hl(0, ANCESTOR_HL, { background = ancestor_bg, bold = true, default = true })
  api.nvim_set_hl(0, DIFF_HL, { background = incoming_bg, bold = true, default = true })
  api.nvim_set_hl(0, SNAPSHOT_HL, { background = snapshot_bg, bold = true, default = true })
  api.nvim_set_hl(0, BASE_HL, { background = base_bg, bold = true, default = true })
  api.nvim_set_hl(0, CURRENT_LABEL_HL, { background = current_label_bg, default = true })
  api.nvim_set_hl(0, INCOMING_LABEL_HL, { background = incoming_label_bg, default = true })
  api.nvim_set_hl(0, ANCESTOR_LABEL_HL, { background = ancestor_label_bg, default = true })
  api.nvim_set_hl(0, SNAPSHOT_LABEL_HL, { background = snapshot_label_bg, default = true })
  api.nvim_set_hl(0, BASE_LABEL_HL, { background = base_label_bg, default = true })
end

-- Parse current buffer and highlight
local function parse_and_highlight(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(bufnr) then return end
  local lines = get_buf_lines(bufnr)
  local positions = detect_conflicts(lines)
  if #positions > 0 then
    highlight_conflicts(bufnr, positions, lines)
  else
    api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  end
end

-- Public setup. Minimal options: highlights table
function M.setup(opts)
  opts = opts or {}
  set_highlights(opts.highlights)

  -- decoration provider: highlight whenever window displays buffer
  api.nvim_set_decoration_provider(NAMESPACE, {
    on_win = function(_, _, bufnr, _, _)
      -- only operate on current buffer (user requested current open buffer only)
      if bufnr == api.nvim_get_current_buf() then
        parse_and_highlight(bufnr)
      end
    end,
    on_buf = function(_, bufnr, _)
      -- show only for valid buffers: keep default behaviour
      return api.nvim_buf_is_loaded(bufnr)
    end,
  })

  -- Also attach to BufRead / TextChanged to update highlights
  api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'TextChanged', 'TextChangedI' }, {
    callback = function(args)
      if args.buf == api.nvim_get_current_buf() then parse_and_highlight(args.buf) end
    end,
  })
end

function M.clear()
  local bufnr = api.nvim_get_current_buf()
  api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
end

return M

