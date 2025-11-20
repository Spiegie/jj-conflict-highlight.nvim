local inspect = require "lib.inspect"

local MARKERS = {
  start =    '^<<<<<<<+',      -- start of a side
  diff =     '^%%%%%%%%%%%%%%%+',      -- jj conflict header (e.g. "%%%%%% conflict ...")
  base =     '^-------+',      -- start of a side
  ancestor = '^|||||||+',      -- ancestor/base marker
  middle =   '^=======+',      -- divider between sides
  snapshot = '^++++++++',      -- snapshot
  finish =   '^>>>>>>>+',      -- end of conflict
}

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
        table.insert(position.diff, {start = regionstart, finish = i-1})
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















local jj_conflict = [[
teststring
teststring
<<<<<<< Conflict 1 of 1
+++++++ Contents of side #1
apple
grapefruit
orange
+++++++ Contents of side #2
>>>>>>> Conflict 1 of 1 ends
endspaceer
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
teststring
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
endspaceer
]]

local jj_conflict_bak = [[
teststring
]]

local function multiline_string_to_table(str)
  local lines = {}
  for s in str:gmatch("[^\r\n]+") do
    table.insert(lines, s)
  end
  return lines
end

local lines = multiline_string_to_table(jj_conflict)


print("-- INFO: start testing")

local conflicts =  detect_conflicts(lines)

-- print("debug startmarker: " .. conflicts.startMarker)
-- if conflicts.snapshotMarkers ~= nil then
--   print(#conflicts.snapshotMarkers)
--   if #conflicts.snapshotMarkers >= 1 then
--     print("debug snapshotmarker: " .. conflicts.snapshotMarkers[1])
--   end
--   if #conflicts.snapshotMarkers >= 2 then
--     print("debug snapshotmarker: " .. conflicts.snapshotMarkers[2])
--   end
-- end
-- if conflicts.baseMarkser ~= nil then
--   print("debug basemarker: " .. conflicts.baseMarker)
-- end


print("debug: inspecting")
print(inspect(conflicts))
