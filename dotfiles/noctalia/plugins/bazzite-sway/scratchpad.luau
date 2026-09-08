--!nonstrict
-- The scratchpad count. 20-appearance.conf sets `default_border none`, so a
-- window sent to the scratchpad leaves no trace on screen -- this is the only
-- feedback that the binding did anything. Hidden when empty.

local function refresh()
  noctalia.runAsync("swaymsg -t get_tree -r", function(res)
    if not res or not res.ok then
      barWidget.setVisible(false)
      return
    end
    -- Count the __i3_scratch workspace's direct floating children by "pid".
    -- Counting `"app_id"` occurrences would be fragile against nesting.
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
  -- Polled because there is no i3-IPC event for "a window entered the
  -- scratchpad"; reconstructing the count from `window` events is more state
  -- than a count is worth.
  noctalia.setUpdateInterval(5000)
  refresh()
end
