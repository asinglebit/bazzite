--!nonstrict
-- Shows sway's binding mode, as a word rather than a glyph, and nothing here polls.

local function show(mode: string)
  if mode == "" or mode == "default" then
    barWidget.setVisible(false)
  else
    barWidget.setText(mode)
    barWidget.setColor("primary")
    barWidget.setVisible(true)
  end
end

function update()
  -- Runs once to start the subscription; the interval is just the host's minimum.
  noctalia.setUpdateInterval(3600000)
end

show("default")

noctalia.runStream("swaymsg -t subscribe -m '[\"mode\"]'", function(line)
  local mode = string.match(line, '"change"%s*:%s*"([^"]*)"')
  if mode then show(mode) end
end)
