--!nonstrict
-- Failed systemd units, both managers. Invisible until something breaks.
--
-- Its limit: the one unit whose failure this cannot report is noctalia.service,
-- because there is no bar left to draw it on. That is what verify.sh is for.

local system, user = 0, 0

local function render()
  local total = system + user
  if total == 0 then
    barWidget.setVisible(false)
    return
  end
  barWidget.setGlyph("alert-triangle")
  barWidget.setText(tostring(total))
  barWidget.setGlyphColor("error")
  barWidget.setTooltip({
    { "system units", tostring(system) },
    { "user units",   tostring(user) },
  })
  barWidget.setVisible(true)
end

local function count(cmd: string, assign: (number) -> ())
  noctalia.runAsync(cmd, function(res)
    local n = 0
    if res and res.ok and res.stdout then
      for line in string.gmatch(res.stdout, "[^\n]+") do
        if string.match(line, "%S") then n += 1 end
      end
    end
    assign(n)
    render()
  end)
end

function update()
  noctalia.setUpdateInterval(30000)
  count("systemctl --failed --no-legend --plain --no-pager", function(n) system = n end)
  count("systemctl --user --failed --no-legend --plain --no-pager", function(n) user = n end)
end
