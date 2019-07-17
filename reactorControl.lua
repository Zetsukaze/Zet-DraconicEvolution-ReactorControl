-- modifiable variables
local reactorSide = "bottom"
local fluxgateSide = "top"
local inputFluxGateId = "flux_gate_0"

local targetStrength = 5
local targetTemperature = 7950
local maxTemperature = 8000
local safeTemperature = 6000
local maxOutput = 5e6
local lowestFieldPercent = 3

local activateOnCharged = 1

-- please leave things untouched from here on
os.loadAPI("lib/f")

local version = "0.25"
-- toggleable via the monitor, use our algorithm to achieve our target field strength or let the user tweak it
local autoInputGate = 1
local autoOutputGate = 1
local curOutputGate = 500000
local curInputGate = 200000

-- monitor
local mon, monitor, monX, monY

-- peripherals
local reactor
local fluxgate
local inputfluxgate

-- reactor information
local ri

-- last performed action
local action = "None since reboot"
local emergencyCharge = false
local emergencyTemp = false

monitor = f.periphSearch("monitor")
inputfluxgate = peripheral.wrap(inputFluxGateId)
fluxgate = peripheral.wrap(fluxgateSide)
reactor = peripheral.wrap(reactorSide)
energycore = f.periphSearch("draconic_rf_storage")

if monitor == null then
	error("No valid monitor was found")
end

if fluxgate == null then
	error("No valid fluxgate was found")
end

if reactor == null then
	error("No valid reactor was found")
end

if inputfluxgate == null then
	error("No valid flux gate was found")
end

monX, monY = monitor.getSize()
mon = {}
mon.monitor,mon.X, mon.Y = monitor, monX, monY

--write settings to config file
function save_config()
  sw = fs.open("config.txt", "w")
  sw.writeLine(version)
  sw.writeLine(autoInputGate)
  sw.writeLine(autoOutputGate)
  sw.writeLine(curOutputGate)
  sw.writeLine(curInputGate)
  sw.close()
end

--read settings from file
function load_config()
  sr = fs.open("config.txt", "r")
  version = sr.readLine()
  autoInputGate = tonumber(sr.readLine())
  autoOutputGate = tonumber(sr.readLine())
  curOutputGate = tonumber(sr.readLine())
  curInputGate = tonumber(sr.readLine())
  sr.close()
end


-- 1st time? save our settings, if not, load our settings
if fs.exists("config.txt") == false then
  save_config()
else
  load_config()
end

function buttons()

  while true do
    -- button handler
    event, side, xPos, yPos = os.pullEvent("monitor_touch")

    -- output gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 8 then
      if xPos >= 2 and xPos <= 4 then
        curOutputGate = curOutputGate-1000
      elseif xPos >= 6 and xPos <= 9 then
        curOutputGate = curOutputGate-10000
      elseif xPos >= 10 and xPos <= 12 then
        curOutputGate = curOutputGate-100000
      elseif xPos >= 17 and xPos <= 19 then
        curOutputGate = curOutputGate+100000
      elseif xPos >= 21 and xPos <= 23 then
        curOutputGate = curOutputGate+10000
      elseif xPos >= 25 and xPos <= 27 then
        curOutputGate = curOutputGate+1000
      end
      curOutputGate =  math.min( maxOutput, curOutputGate )
      fluxgate.setSignalLowFlow(curOutputGate)
    end

    -- output gate toggle
    if yPos == 8 and ( xPos == 14 or xPos == 15) then
      if autoOutputGate == 1 then
        autoOutputGate = 0
      else
        autoOutputGate = 1
      end
      save_config()
    end

    -- input gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 10 and autoInputGate == 0 and xPos ~= 14 and xPos ~= 15 then
      if xPos >= 2 and xPos <= 4 then
        curInputGate = curInputGate-1000
      elseif xPos >= 6 and xPos <= 9 then
        curInputGate = curInputGate-10000
      elseif xPos >= 10 and xPos <= 12 then
        curInputGate = curInputGate-100000
      elseif xPos >= 17 and xPos <= 19 then
        curInputGate = curInputGate+100000
      elseif xPos >= 21 and xPos <= 23 then
        curInputGate = curInputGate+10000
      elseif xPos >= 25 and xPos <= 27 then
        curInputGate = curInputGate+1000
      end
      inputfluxgate.setSignalLowFlow(curInputGate)
      save_config()
    end

    -- input gate toggle
    if yPos == 10 and ( xPos == 14 or xPos == 15) then
      if autoInputGate == 1 then
        autoInputGate = 0
      else
        autoInputGate = 1
      end
      save_config()
    end

  end
end

function drawButtons(y)

  -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
  -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000

  f.draw_text(mon, 2, y, " < ", colors.white, colors.gray)
  f.draw_text(mon, 6, y, " <<", colors.white, colors.gray)
  f.draw_text(mon, 10, y, "<<<", colors.white, colors.gray)

  f.draw_text(mon, 17, y, ">>>", colors.white, colors.gray)
  f.draw_text(mon, 21, y, ">> ", colors.white, colors.gray)
  f.draw_text(mon, 25, y, " > ", colors.white, colors.gray)
end



function update()
  while true do

    f.clear(mon)

    ri = reactor.getReactorInfo()

    -- print out all the infos from .getReactorInfo() to term

    if ri == nil then
      error("reactor has an invalid setup")
    end

    if ri.status == "running" then
      ri.status = "online"
    elseif ri.status == "warming_up" then
      ri.status = "charging"
    elseif ri.status == "cold" then
      ri.status = "offline"
    end

    for k, v in pairs (ri) do
      print(k.. ": ".. (v and "true" or "false"))
    end
    print("Output Gate: ", fluxgate.getSignalLowFlow())
    print("Input Gate: ", inputfluxgate.getSignalLowFlow())

    -- monitor output

    local statusColor
    statusColor = colors.red

    if ri.status == "online" or ri.status == "charged" then
      statusColor = colors.green
    elseif ri.status == "offline" then
      statusColor = colors.gray
    elseif ri.status == "charging" then
      statusColor = colors.orange
    end

    f.draw_text_lr(mon, 2, 2, 1, "Reactor Status", string.upper(ri.status), colors.white, statusColor, colors.black)

    f.draw_text_lr(mon, 2, 4, 1, "Generation", f.format_int(ri.generationRate) .. " rf/t", colors.white, colors.lime, colors.black)

    local tempColor = colors.red
    if ri.temperature <= 5000 then tempColor = colors.green end
    if ri.temperature >= 5000 and ri.temperature <= 6500 then tempColor = colors.orange end
    f.draw_text_lr(mon, 2, 6, 1, "Temperature", f.format_int(ri.temperature) .. "C", colors.white, tempColor, colors.black)

    f.draw_text_lr(mon, 2, 7, 1, "Output Gate", f.format_int(fluxgate.getSignalLowFlow()) .. " rf/t", colors.white, colors.blue, colors.black)

    -- buttons
    if autoOutputGate == 1 then
      f.draw_text(mon, 14, 8, "AU", colors.white, colors.gray)
    else
      f.draw_text(mon, 14, 8, "MA", colors.white, colors.gray)
      drawButtons(8)
    end

    f.draw_text_lr(mon, 2, 9, 1, "Input Gate", f.format_int(inputfluxgate.getSignalLowFlow()) .. " rf/t", colors.white, colors.blue, colors.black)

    if autoInputGate == 1 then
      f.draw_text(mon, 14, 10, "AU", colors.white, colors.gray)
    else
      f.draw_text(mon, 14, 10, "MA", colors.white, colors.gray)
      drawButtons(10)
    end

    local satPercent
    satPercent = math.ceil(ri.energySaturation / ri.maxEnergySaturation * 10000)*.01

    f.draw_text_lr(mon, 2, 11, 1, "Energy Saturation", satPercent .. "%", colors.white, colors.white, colors.black)
    f.progress_bar(mon, 2, 12, mon.X-2, satPercent, 100, colors.blue, colors.gray)

    local fieldPercent, fieldColor
    fieldPercent = math.ceil(ri.fieldStrength / ri.maxFieldStrength * 10000)*.01

    fieldColor = colors.red
    if fieldPercent >= 50 then fieldColor = colors.green end
    if fieldPercent < 50 and fieldPercent > 30 then fieldColor = colors.orange end

    if autoInputGate == 1 then
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength T:" .. targetStrength, fieldPercent .. "%", colors.white, fieldColor, colors.black)
    else
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength", fieldPercent .. "%", colors.white, fieldColor, colors.black)
    end
    f.progress_bar(mon, 2, 15, mon.X-2, fieldPercent, 100, fieldColor, colors.gray)

    local fuelPercent, fuelColor

    fuelPercent = 100 - math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000)*.01

    fuelColor = colors.red

    if fuelPercent >= 70 then fuelColor = colors.green end
    if fuelPercent < 70 and fuelPercent > 30 then fuelColor = colors.orange end

    f.draw_text_lr(mon, 2, 17, 1, "Fuel ", fuelPercent .. "%", colors.white, fuelColor, colors.black)
    f.progress_bar(mon, 2, 18, mon.X-2, fuelPercent, 100, fuelColor, colors.gray)

    f.draw_text_lr(mon, 2, 19, 1, "Action ", action, colors.gray, colors.gray, colors.black)

    -- actual reactor interaction
    --
    if emergencyCharge == true then
      fluxval = ri.fieldDrainRate / (1 - (targetStrength/100) )
      inputfluxgate.setSignalLowFlow(math.max( 900000, fluxval ))
      if ri.temperature < 7000 and fieldPercent > 20 and activateOnCharged == 1 then
        emergencyCharge = false
        reactor.activateReactor()
      else
        reactor.chargeReactor()
      end
    end

    -- are we charging? open the floodgates
    if ri.status == "charging" then
      inputfluxgate.setSignalLowFlow(900000)
      emergencyCharge = false
    end

    -- are we stopping from a shutdown and our temp is better? activate
    if emergencyTemp == true and ri.status == "stopping" then
      if fieldPercent < 10 then
        fluxval = ri.fieldDrainRate / (1 - (targetStrength/100) )
        inputfluxgate.setSignalLowFlow(fluxval)
      else
        inputfluxgate.setSignalLowFlow(curInputGate)
      end
      if ri.temperature < safeTemperature then
        reactor.activateReactor()
        emergencyTemp = false
      end
    end

    -- are we charged? lets activate
    if ri.status == "charging" and ri.temperature >= 2000 and activateOnCharged == 1 then
      reactor.activateReactor()
    end

    -- auto output flux gate
    if ri.status == "online" then
      if autoOutputGate == 1 then
        fluxval = math.max(0, math.min((targetTemperature - ri.temperature) * 200, (fieldPercent - targetStrength + 1) * 1e6) + ri.generationRate)
        print("Target Output: ".. fluxval)
        fluxgate.setSignalLowFlow( math.min( maxOutput, fluxval ) )
      else
        fluxgate.setSignalLowFlow( math.min( maxOutput, curOutputGate ) )
      end
    end

    -- are we on? regulate the input flux gate to our target field strength
    -- or set it to our saved setting since we are on manual
    if ri.status == "online" then
      if autoInputGate == 1 then
        fluxval = ri.fieldDrainRate / (1 - (targetStrength/100) )
        print("Target Input: ".. fluxval)
        inputfluxgate.setSignalLowFlow(fluxval)
      else
        inputfluxgate.setSignalLowFlow(curInputGate)
      end
    end

    -- safeguards
    --

    -- out of fuel, kill it
    if fuelPercent <= 10 then
      reactor.stopReactor()
      action = "Fuel below 10%, refuel"
    end

    -- field strength is too dangerous, kill it and try charge it before it blows
    if fieldPercent <= lowestFieldPercent and ri.status == "online" then
      action = "Field Str < " ..lowestFieldPercent.."%"
      reactor.stopReactor()
      reactor.chargeReactor()
      emergencyCharge = true
    end

    -- temperature too high, kill it and activate it when it's cool
    if ri.temperature > maxTemperature then
      reactor.stopReactor()
      action = "Temp > " .. maxTemperature
      emergencyTemp = true
    end

    -- check energy reserves
    if energycore then
      local energy = energycore.getEnergyStored()
      if energy == 0 then
        reactor.stopReactor()
        action = "0 reserve energy"
      elseif (energy/energycore.getMaxEnergyStored()) < 0.5 then
        reactor.stopReactor()
        action = "Reserve energy < 50%"
      end
    end

    sleep(0.1)
  end
end

parallel.waitForAny(buttons, update)
