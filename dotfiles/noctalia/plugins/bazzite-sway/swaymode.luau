--!nonstrict
-- Sway's binding-mode indicator.
--
-- `swaymsg -t subscribe` is the only way to hear about a mode change: a
-- long-lived process emitting one JSON object per event, which is what
-- runStream is for. Nothing here polls.
--
-- No glyph: when this widget is visible, the word IS the information.

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
  -- Event-driven, so this only has to run once to start the subscription. The
  -- interval is the host's floor, not a poll.
  noctalia.setUpdateInterval(3600000)
end

show("default")

noctalia.runStream("swaymsg -t subscribe -m '[\"mode\"]'", function(line)
  local mode = string.match(line, '"change"%s*:%s*"([^"]*)"')
  if mode then show(mode) end
end)
