--!nonstrict
-- How many windows are hidden in the scratchpad, which nothing else on screen shows.

local function refresh()
  noctalia.runAsync("swaymsg -t get_tree -r", function(res)
    if not res or not res.ok then
      barWidget.setVisible(false)
      return
    end
    -- Count by "pid", because counting app_id would also catch nested children.
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
  -- Polled, because sway sends no event for a window entering the scratchpad.
  noctalia.setUpdateInterval(5000)
  refresh()
end
