--!nonstrict
-- cpu, memory and temperature as one glyph that brightens when the machine is struggling.

-- These must match [system.monitor] in 50-services.toml by hand, and verify.sh compares them.
local TEMP_WARN, TEMP_CRIT = 75, 85
local CPU_WARN,  CPU_CRIT  = 80, 95
local MEM_WARN,  MEM_CRIT  = 85, 95

-- Sensor names to look for, best first.
local ZONE_TYPES  = { x86_pkg_temp = true, k10temp = true, cpu_thermal = true, soc_thermal = true }
local HWMON_NAMES = { coretemp = true, k10temp = true, zenpower = true }

local prevIdle, prevTotal = nil, nil

local function trim(s: string?): string
  if not s then return "" end
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Needs two samples to compare, so the first tick returns nothing.
local function cpuPct(): number?
  local stat = noctalia.readFile("/proc/stat")
  if not stat then return nil end
  local line = string.match(stat, "^cpu%s+([^\n]+)")
  if not line then return nil end

  local total, idle = 0, 0
  local i = 0
  for field in string.gmatch(line, "%d+") do
    local v = tonumber(field) or 0
    total += v
    i += 1
    -- Fields 4 and 5 are idle and iowait.
    if i == 4 or i == 5 then idle += v end
  end

  local pct: number? = nil
  if prevTotal and total > prevTotal then
    local dt = total - prevTotal
    local di = idle - prevIdle
    pct = math.floor(((dt - di) / dt) * 100 + 0.5)
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
  end
  prevIdle, prevTotal = idle, total
  return pct
end

-- MemAvailable, not MemFree, because free ignores the page cache and always looks full.
local function mem(): (number?, string?)
  local info = noctalia.readFile("/proc/meminfo")
  if not info then return nil, nil end
  local totalKb = tonumber(string.match(info, "MemTotal:%s+(%d+)"))
  local availKb = tonumber(string.match(info, "MemAvailable:%s+(%d+)"))
  if not totalKb or not availKb or totalKb == 0 then return nil, nil end
  local usedKb = totalKb - availKb
  local pct = math.floor((usedKb * 100 / totalKb) + 0.5)
  local human = string.format("%.1fG / %.1fG", usedKb / 1048576, totalKb / 1048576)
  return pct, human
end

-- Found by name, never by index: the kernel renumbers the zones and zone 0 is the wrong sensor.
local function tempC(): number?
  local zones = noctalia.listDir("/sys/class/thermal")
  if zones then
    for _, name in zones do
      if string.match(name, "^thermal_zone%d+$") then
        local kind = trim(noctalia.readFile(`/sys/class/thermal/{name}/type`))
        -- Some kernels spell these with a hyphen.
        kind = string.gsub(kind, "-", "_")
        if ZONE_TYPES[kind] then
          local milli = tonumber(trim(noctalia.readFile(`/sys/class/thermal/{name}/temp`)))
          if milli then return math.floor(milli / 1000 + 0.5) end
        end
      end
    end
  end
  -- Fall back to hwmon, also matched by name.
  local hwmons = noctalia.listDir("/sys/class/hwmon")
  if hwmons then
    for _, name in hwmons do
      if string.match(name, "^hwmon%d+$") then
        local kind = trim(noctalia.readFile(`/sys/class/hwmon/{name}/name`))
        if HWMON_NAMES[kind] then
          local milli = tonumber(trim(noctalia.readFile(`/sys/class/hwmon/{name}/temp1_input`)))
          if milli then return math.floor(milli / 1000 + 0.5) end
        end
      end
    end
  end
  return nil
end

local function loadTriple(): string
  local la = noctalia.readFile("/proc/loadavg")
  if not la then return "?" end
  local a, b, c = string.match(la, "^(%S+)%s+(%S+)%s+(%S+)")
  if not a then return "?" end
  return `{a} {b} {c}`
end

-- These three palette roles are progressively brighter greys.
local function severity(cpu: number?, memPct: number?, temp: number?): string
  local function over(v: number?, warn: number, crit: number): number
    if not v then return 0 end
    if v >= crit then return 2 elseif v >= warn then return 1 end
    return 0
  end
  local level = math.max(
    over(temp, TEMP_WARN, TEMP_CRIT),
    over(cpu, CPU_WARN, CPU_CRIT),
    over(memPct, MEM_WARN, MEM_CRIT)
  )
  if level == 2 then return "error" elseif level == 1 then return "primary" end
  return "secondary"
end

function update()
  noctalia.setUpdateInterval(10000)

  local cpu = cpuPct()
  local memPct, memHuman = mem()
  local temp = tempC()

  barWidget.setGlyph("cpu")
  barWidget.setGlyphColor(severity(cpu, memPct, temp))

  -- The host aligns these rows, so they need no padding.
  barWidget.setTooltip({
    { "cpu",  cpu and `{cpu}%` or "--" },
    { "load", loadTriple() },
    { "ram",  memPct and `{memPct}%  {memHuman}` or "--" },
    { "temp", temp and `{temp}C` or "no cpu sensor" },
  })
end
