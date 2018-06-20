
local _, Me = ...

local THROTTLE_BPS   = 1000
local THROTTLE_BURST = 3000
local TIMER_PERIOD   = 0.1
local MSG_OVERHEAD = 25

Me.bandwidth       = 0
Me.bandwidth_time  = GetTime()
Me.out_chat_buffer = {}

Me.send_queue_started = false

local function UpdateBandwidth()
	local time = GetTime()
	if time == Me.bandwidth_time then return end -- already updated this frame.
	
	local bps, burst = THROTTLE_BPS, THROTTLE_BURST
	if InCombatLockdown() then
		bps = bps / 2
		burst = burst / 2
	end
	
	Me.bandwidth = math.min( Me.bandwidth + bps * (time-Me.bandwidth_time), burst )
	Me.bandwidth_time = time
end

local function TryDispatchMessage( msg )
	local size = (#msg.msg + MSG_OVERHEAD)
	if size > Me.bandwidth then return false end
	
	local kind = msg.kind
	
	Me.bandwidth = Me.bandwidth - size
	
	if kind == "BNET" then
		Me.hooks.BNSendWhisper( msg.target, msg.msg )
	elseif kind == "CLUB" then
		Me.hooks[C_Club].SendMessage( msg.arg3, msg.target, msg.msg )
	else
		if kind == "SAY" or kind == "EMOTE" or kind == "YELL" then
			Me.StartLatencyRecording()
		end
		Me.hooks.SendChatMessage( msg.msg, kind, msg.arg3, msg.target )
	end
	return true
end

local ScheduleSendQueue

local function RunSendQueue()
	while #Me.out_chat_buffer > 0 do
		if TryDispatchMessage( Me.out_chat_buffer[1] ) then
			table.remove( Me.out_chat_buffer, 1 )
			
			if Me.db.global.slowpost then
				ScheduleSendQueue()
				return
			end
		else
			ScheduleSendQueue()
			return
		end
	end
	Me.OnThrottlerStop()
	Me.send_queue_started = false
end

ScheduleSendQueue = function()
	Me.OnThrottlerStart()
	C_Timer.After( TIMER_PERIOD, function()
		UpdateBandwidth()
		RunSendQueue()
	end)
end

local function StartSendQueue()
	if Me.send_queue_started then return end
	Me.send_queue_started = true
	RunSendQueue()
end

function Me.CommitChat( message, kind, arg3, target )
	UpdateBandwidth()
	
	message = tostring(message)
	local size = #message + MSG_OVERHEAD
	
	table.insert( Me.out_chat_buffer, {
		msg    = message;
		kind   = kind;
		arg3   = arg3;
		target = target;
	})
	
	StartSendQueue()
end
