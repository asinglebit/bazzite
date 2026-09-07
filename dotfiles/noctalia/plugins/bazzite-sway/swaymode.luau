--!nonstrict
-- Sway's binding-mode indicator, the successor to waybar's `sway/mode`.
--
-- ext_workspace_manager_v1 is absent on SwayFX, so noctalia talks i3 IPC over
-- $SWAYSOCK for everything sway-shaped -- and `swaymsg -t subscribe` is the only
-- way to hear about a mode change. It is a long-lived process emitting one JSON
-- object per event, which is what runStream is for; nothing here polls.
--
-- Hidden in the default mode, so it costs nothing at rest. That is why there is
-- no glyph: when this widget is visible, the word IS the information.

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
  -- Event-driven; this only has to run once to start the subscription. The
  -- interval is the floor the host allows rather than a poll.
  noctalia.setUpdateInterval(3600000)
end

show("default")

noctalia.runStream("swaymsg -t subscribe -m '[\"mode\"]'", function(line)
  -- {"change":"resize","pango_markup":false}
  local mode = string.match(line, '"change"%s*:%s*"([^"]*)"')
  if mode then show(mode) end
end)
