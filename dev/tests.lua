-- unlock chatbox for long macros
/run ChatFrame1EditBox:SetMaxLetters(0) ChatFrame1EditBox:SetMaxBytes(0)

-- super spam test
/run 
  print("---NEW TEST---")
	SendChatMessage( (1) .. string.rep("-", 252), "EMOTE" )
  for i = 2,20 do
	SendChatMessage( (i) .. string.rep("/", 252), "EMOTE" )
  end
  
  print( "---SENDING COMPLETE---" )
  
-- slightly spaced out spam test
/run 
  print("---NEW TEST---")
  local t = 1
  local function f()
    SendChatMessage( t .. string.rep("+", 250), "EMOTE" )
    SendChatMessage( "x2" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x3" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x4" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x5" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x6" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x7" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x8" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x9" .. string.rep("/", 250), "EMOTE" )
    SendChatMessage( "x10" .. string.rep("/", 250), "EMOTE" )
    t = t + 1
    if t <= 10 then
      C_Timer.After( 0.25, f )
    end
  end
  f()
  
/run
	local test_data = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	local failures = 0
	if not mytestframe then
		mytestframe = CreateFrame("Frame")
	end
	mytestframe:Show()
	mytestframe:RegisterEvent( "CHAT_MSG_SAY" )
	mytestframe:RegisterEvent( "CHAT_MSG_SYSTEM" )
	mytestframe:SetScript( "OnEvent", function( self, event, msg )
		if event == "CHAT_MSG_SAY" then
			local index = msg:match( "test message (%d+)" )
			index = tonumber(index)
			if index then
				test_data[index] = test_data[index] + 1
			end
		elseif event == "CHAT_MSG_SYSTEM" and msg == ERR_CHAT_THROTTLED then
			failures=failures + 1
		end
	end)

	local iterations = 0

	local function f()

		for i = 1, 5 do
			SendChatMessage( "test message " .. i .. " " .. string.rep( "/", 30 ), "SAY" )
		end
		iterations = iterations + 1
		print( "ITERATION " .. iterations )
		if iterations >= 25 then
			--[[ print results after waiting for the last messages ]]

			print( "Waiting before results..." )
			C_Timer.After( 5.000, function()
				mytestframe:Hide() --[[ehe]]
				print( "RESULTS..." )
				for i = 1, 10 do
					print( "i = " .. test_data[i] )
				end
				print( "fails = " .. failures )
			end)
		else
			C_Timer.After( 10.000, f )
		end
	end
	f()
  
  
/run
	local test_data = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	if not mytestframe then
		mytestframe = CreateFrame("Frame")
	end
	mytestframe:Show()
	mytestframe:RegisterEvent( "CHAT_MSG_SAY" )
	mytestframe:SetScript( "OnEvent", function( self, event, msg )
		if event ~= "CHAT_MSG_SAY" then return end
		local index = msg:match( "test message (%d+)" )
		index = tonumber(index)
		if index then
			test_data[index] = test_data[index] + 1
		end
	end)

	local iterations = 0
	local nexty = 1

	local function f()
		SendChatMessage( "test message " .. nexty .. " " .. string.rep( "/", 30 ), "SAY" )
		nexty = nexty + 1
		if nexty == 11 then
			nexty=  1
			iterations = iterations + 1

			print( "ITERATION " .. iterations )
			if iterations >= 100 then
				--[[ print results after waiting for the last messages ]]

				print( "Waiting before results..." )
				C_Timer.After( 5.000, function()
					mytestframe:Hide() --[[ehe]]
					print( "RESULTS..." )
					for i = 1, 10 do
						print( "i = " .. test_data[i] )
					end
				end)
				return
			else
				
			end
		end
		C_Timer.After( 0.01, f )
	end
	f()
  
-- mega long spam test
/run print("---NEW TEST---")
  for i = 1,64 do
	SendChatMessage( tostring(i) , "SAY" )
	
  end
  
  
	--[[SendAddonMessage( "TE", i .. string.rep("/", 250), "WHISPER", "Tammya" )]]