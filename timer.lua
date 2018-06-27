
local _, Me = ...

Me.timers = {}
Me.last_triggered = {}

function Me.Timer_NotOnCD( slot, period )
	local time_to_next = (Me.last_triggered[slot] or (-period)) + period - GetTime()
	if time_to_next <= 0 then
		return true
	end
end

-- slot = string ID
-- mode = how this timer works or reacts to additional start calls
--          "push" = cancel existing and wait for the new period to expire
--          "ignore" = ignore the new call
--          "duplicate" = leave previous timer running and make new one
--          "cooldown" = this triggers instantly with a cooldown, 
--                       additional calls during the cooldown period are 
--                       merged into a single call at the end of the
--                       cooldown period. This may trigger inside
--                       this call.
function Me.Timer_Start( slot, mode, period, func )
	if mode == "cooldown" and not Me.timers[slot] then
		local time_to_next = (Me.last_triggered[slot] or (-period)) + period - GetTime()
		if time_to_next <= 0 then
			Me.last_triggered[slot] = GetTime()
			func()
			return
		end
		
		-- cooldown remains, ignore or schedule it
		mode = "ignore"
		period = time_to_next
	end
	
	if Me.timers[slot] then
		if mode == "push" then
			Me.timers[slot].cancel = true
		elseif mode == "duplicate" then
			
		else -- ignore/cooldown/default
			return
		end
	end
	
	local this_timer = {
		cancel = false;
	}
	
	Me.timers[slot] = this_timer
	C_Timer.After( period, function()
		if this_timer.cancel then return end
		Me.timers[slot] = nil
		Me.last_triggered[slot] = GetTime()
		func()
	end)
end

function Me.Timer_Cancel( slot )
	if Me.timers[slot] then
		Me.timers[slot].cancel = true
		Me.timers[slot] = nil
	end
end
