--!nonstrict
-- The scratchpad count, the successor to waybar's `sway/scratchpad`.
--
-- Why this is worth a widget at all: 20-appearance.conf sets
-- `default_border none`, so a window sent to the scratchpad leaves NO trace on
-- screen. This count is the only feedback that $mod+Shift+minus did anything.
--
-- Hidden when empty, matching `show-empty: false`.

local function refresh()
  noctalia.runAsync("swaymsg -t get_tree -r", function(res)
    if not res or not res.ok then
      barWidget.setVisible(false)
      return
    end
    -- The scratchpad is the __i3_scratch workspace's floating_nodes. Counting
    -- occurrences of `"app_id"` inside it would be fragile against nesting, so
    -- count the workspace's own direct floating children by name instead: every
    -- scratchpad window has a "name" and a "pid" at that level.
    local scratch = string.match(res.stdout or "", '"name"%s*:%s*"__i3_scratch".-"floating_nodes"%s*:%s*%[(.*)')
    local count = 0
    if scratch then
      for _ in string.gmatch(scratch, '"pid"%s*:%s*%d+') do count += 1 end
    end
    if count > 0 then
      barWidget.setGlyph("layout-cards")
      barWidget.setText(tostring(count))
      barWidget.setVisible(true)
    else
      barWidget.setVisible(false)
    end
  end)
end

function update()
  -- There is no i3-IPC event for "a window entered the scratchpad" -- `window`
  -- events fire on move, but reconstructing the count from them is more state
  -- than a count is worth. Five seconds is well under the time it takes to
  -- wonder whether the keybinding worked.
  noctalia.setUpdateInterval(5000)
  refresh()
end
