-- Highlight Jujutsu (and git style) conflict markers in the current buffer.
--
-- Conflicts are parsed by jj_conflict_highlight.parse and highlighted with
-- extmarks in a dedicated namespace. A decoration provider refreshes the
-- highlights whenever the buffer is redrawn, but only re-parses a buffer
-- after its contents actually changed.

local api = vim.api

local parse = require('jj_conflict_highlight.parse')

local M = {}

local NAMESPACE = api.nvim_create_namespace('jj-conflict-highlight')
local AUGROUP = 'jj-conflict-highlight'
local PRIORITY = vim.highlight.priorities.user

-- Highlight groups defined by the plugin. Each group derives its background
-- from a "source" group (a built-in diff group by default) so the highlights
-- blend in with the active colorscheme.
local GROUPS = {
  { name = 'JjConflictCurrent', source = 'current' },
  { name = 'JjConflictIncoming', source = 'incoming' },
  { name = 'JjConflictAncestor', source = 'ancestor' },
  { name = 'JjConflictDiff', source = 'incoming' },
  { name = 'JjConflictSnapshot', source = 'snapshot' },
  { name = 'JjConflictBase', source = 'base' },
}

-- Source groups used when the user has not overridden them via
-- setup({ highlights = ... }). DiffSnapshot and DiffBase are not built-in,
-- so those fall back to FALLBACK_BG unless defined by the colorscheme.
local DEFAULT_SOURCES = {
  current = 'DiffText',
  incoming = 'DiffAdd',
  ancestor = 'DiffChange',
  snapshot = 'DiffSnapshot',
  base = 'DiffBase',
}

-- Backgrounds used when the source group defines no background either.
local FALLBACK_BG = {
  current = 0x405d7e,
  incoming = 0x314753,
  ancestor = 0x68217a,
  snapshot = 0x68217a,
  base = 0x68217a,
}

-- changedtick of each buffer at the time it was last parsed
local parsed_tick = {}

-- highlight sources passed to setup(), kept for re-applying after a
-- colorscheme switch
local user_highlights = nil

-- Background color of highlight group `name`, or nil if it has none.
local function get_hl_bg(name)
  if not name then return nil end
  if api.nvim_get_hl then
    local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
    if ok and hl and hl.bg then return hl.bg end
  else
    local ok, hl = pcall(api.nvim_get_hl_by_name, name, true)
    if ok and hl and hl.background then return hl.background end
  end
  return nil
end

-- Define the plugin highlight groups, deriving backgrounds from the
-- configured source groups where possible.
local function set_highlights(hls)
  hls = hls or {}
  for _, group in ipairs(GROUPS) do
    local source = hls[group.source] or DEFAULT_SOURCES[group.source]
    local bg = get_hl_bg(source) or FALLBACK_BG[group.source]
    api.nvim_set_hl(0, group.name, { bg = bg, bold = true, default = true })
  end
end

-- Highlight the 1-based line range [start, finish], both inclusive.
local function hl_range(bufnr, hl_group, start, finish)
  api.nvim_buf_set_extmark(bufnr, NAMESPACE, start - 1, 0, {
    hl_group = hl_group,
    hl_eol = true,
    hl_mode = 'combine',
    end_row = finish,
    priority = PRIORITY,
  })
end

local function highlight_conflict(bufnr, pos)
  -- marker lines
  local markers = { pos.start_marker, pos.finish_marker }
  vim.list_extend(markers, pos.snapshot_markers or {})
  vim.list_extend(markers, pos.diff_markers or {})
  if pos.base_marker then markers[#markers + 1] = pos.base_marker end
  if pos.ancestor_marker then markers[#markers + 1] = pos.ancestor_marker end
  if pos.middle_marker then markers[#markers + 1] = pos.middle_marker end
  for _, lnum in ipairs(markers) do
    hl_range(bufnr, 'JjConflictAncestor', lnum, lnum)
  end

  -- content regions
  for _, range in ipairs(pos.snapshots or {}) do
    hl_range(bufnr, 'JjConflictDiff', range.start, range.finish)
  end
  for _, range in ipairs(pos.diff or {}) do
    hl_range(bufnr, 'JjConflictCurrent', range.start, range.finish)
  end
  if pos.base then hl_range(bufnr, 'JjConflictCurrent', pos.base.start, pos.base.finish) end
  if pos.current then
    hl_range(bufnr, 'JjConflictCurrent', pos.current.start, pos.current.finish)
  end
  if pos.ancestor then
    hl_range(bufnr, 'JjConflictAncestor', pos.ancestor.start, pos.ancestor.finish)
  end
  if pos.incoming then
    hl_range(bufnr, 'JjConflictIncoming', pos.incoming.start, pos.incoming.finish)
  end
end

---Parse the buffer and (re)apply all conflict highlights.
---
---Always refreshes, regardless of the changedtick cache.
---@param bufnr integer? defaults to the current buffer
function M.highlight(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if not api.nvim_buf_is_loaded(bufnr) then return end
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local conflicts = parse.detect_conflicts(lines)
  api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  for _, pos in ipairs(conflicts) do
    highlight_conflict(bufnr, pos)
  end
  parsed_tick[bufnr] = api.nvim_buf_get_changedtick(bufnr)
end

-- Refresh a buffer only when its contents changed since the last parse.
local function refresh_if_changed(bufnr)
  if not api.nvim_buf_is_loaded(bufnr) then return end
  if parsed_tick[bufnr] == api.nvim_buf_get_changedtick(bufnr) then return end
  M.highlight(bufnr)
end

---Remove all conflict highlights from a buffer.
---
---The highlights stay off until the buffer contents change again or
---|jj-conflict-highlight.highlight()| is called.
---@param bufnr integer? defaults to the current buffer
function M.clear(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  pcall(api.nvim_buf_clear_namespace, bufnr, NAMESPACE, 0, -1)
  if api.nvim_buf_is_loaded(bufnr) then parsed_tick[bufnr] = api.nvim_buf_get_changedtick(bufnr) end
end

---Set up the plugin.
---
---Highlights are refreshed automatically for the current buffer whenever it
---is redrawn; only buffers whose contents changed are re-parsed.
---
---@param opts table? configuration table
---@field opts.highlights table? maps a role to the highlight group to derive its background from. Roles: current, incoming, ancestor, snapshot, base
function M.setup(opts)
  opts = opts or {}
  user_highlights = opts.highlights
  set_highlights(user_highlights)

  api.nvim_set_decoration_provider(NAMESPACE, {
    on_win = function(_, _, bufnr)
      -- only operate on the current buffer
      if bufnr == api.nvim_get_current_buf() then refresh_if_changed(bufnr) end
    end,
  })

  local group = api.nvim_create_augroup(AUGROUP, { clear = true })
  -- switching colorscheme clears highlight groups, so re-derive them
  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function() set_highlights(user_highlights) end,
  })
  -- forget the parse cache of buffers that are being unloaded
  api.nvim_create_autocmd('BufUnload', {
    group = group,
    callback = function(args) parsed_tick[args.buf] = nil end,
  })
end

return M
