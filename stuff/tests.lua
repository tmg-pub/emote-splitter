-- unlock chatbox for long macros
/run ChatFrame1EditBox:SetMaxLetters(0) ChatFrame1EditBox:SetMaxBytes(0)

-- Find all editbox frames in the UI
/run
  print("Scanning for all editbox frames...")
  local count = 0
  for i = 1, 50 do
    for j = 1, 50 do
      local name = "ChatFrame" .. i .. "EditBox" 
      local frame = _G[name]
      if frame then
        count = count + 1
        local letters = frame:GetMaxLetters()
        local bytes = frame:GetMaxBytes()
        print(string.format("%s: Letters=%d, Bytes=%d", name, letters, bytes))
      end
    end
  end
  
  -- Also check for whisper-specific frames
  local whisper_frames = {
    "WhisperFrame",
    "WhisperFrameEditBox",
    "FloatingChatFrame",
    "FloatingChatFrameEditBox",
    "TabEditBox",
    "ChatTabEditBox"
  }
  
  for _, name in ipairs(whisper_frames) do
    local frame = _G[name]
    if frame then
      print("Found: " .. name)
      if frame.GetMaxLetters then
        print("  MaxLetters: " .. frame:GetMaxLetters())
      end
    end
  end
  
  print("Total editboxes found: " .. count)

-- super spam test
/run
  local eb = ChatFrame1EditBox
  print("|cffff9900[EDITBOX DIAGNOSTIC]|r")
  print("MaxLetters: " .. tostring(eb:GetMaxLetters()))
  print("MaxBytes: " .. tostring(eb:GetMaxBytes()))
  if eb.SetVisibleTextByteLimit then
    print("SetVisibleTextByteLimit exists: YES")
  else
    print("SetVisibleTextByteLimit exists: NO")
  end
  if eb.SetVisibleTextCharLimit then
    print("SetVisibleTextCharLimit exists: YES")
  else
    print("SetVisibleTextCharLimit exists: NO")
  end
  -- Try setting directly and verify
  eb:SetMaxLetters(0)
  eb:SetMaxBytes(0)
  print("After setting to 0:")
  print("  MaxLetters: " .. eb:GetMaxLetters())
  print("  MaxBytes: " .. eb:GetMaxBytes())

-- ============================================================================
-- TEST: Manually paste and measure what actually gets in the editbox
-- ============================================================================
/run
  print("|cffff9900[PASTE TEST]|r")
  print("After pasting a 300+ character message, run this macro:")
  print("/run local text = ChatFrame1EditBox:GetText(); print('Actual text length in editbox: ' .. text:len())")

-- ============================================================================
-- TEST: Check if it's a whisper-specific issue
-- ============================================================================
/run
  print("|cffff9900[WHISPER-SPECIFIC TEST]|r")
  print("1. Open /say chat and paste 300 chars - does it work?")
  print("2. Open /whisper chat and paste 300 chars - does it work?")
  print("3. This will tell us if it's channel-specific")

-- ============================================================================
-- TEST: Direct message sending test with logging
-- ============================================================================
/run
  if not MessageSendTest then
    MessageSendTest = true
    
    print("|cffff9900[MESSAGE SEND TEST]|r")
    print("Attempting to send a 300+ character whisper programmatically...")
    
    local test_message = string.rep("A", 300)  -- 300 A's
    print("Test message length: " .. test_message:len())
    
    -- This will go through Gopher/EmoteSplitter
    -- SendChatMessage(test_message, "WHISPER", nil, "TestPlayer")  -- Don't actually send
    print("Would send " .. test_message:len() .. " character message")
    print("Run this instead to actually test:")
    print("/whisper TestPlayer " .. string.sub(test_message, 1, 100) .. "...")
  end

-- super spam test
/run
  if not TextLengthMonitor then
    TextLengthMonitor = CreateFrame("Frame")
    TextLengthMonitor.last_text_len = {}
    
    print("|cff00ff00[TEXT MONITOR] Started|r")
    print("|cff00ff00Watching editbox text length and limits in real-time|r")
    
    TextLengthMonitor:SetScript("OnUpdate", function(self, elapsed)
      self.time = (self.time or 0) + elapsed
      if self.time < 0.1 then return end
      self.time = 0
      
      for i = 1, NUM_CHAT_WINDOWS do
        local editbox = _G["ChatFrame" .. i .. "EditBox"]
        if editbox and editbox:IsVisible() and editbox:HasFocus() then
          local text = editbox:GetText()
          local text_len = text:len()
          local max_letters = editbox:GetMaxLetters()
          local max_bytes = editbox:GetMaxBytes()
          
          local key = "frame" .. i
          if self.last_text_len[key] ~= text_len then
            print(string.format("|cff00ffff[TEXT] ChatFrame%d: %d chars, Limits: Letters=%d, Bytes=%d|r", 
              i, text_len, max_letters, max_bytes))
            self.last_text_len[key] = text_len
          end
        end
      end
    end)
  end

-- ============================================================================
-- TEST: Simple whisper send test with detailed logging
-- ============================================================================
/run
  print("|cffff9900[WHISPER TEST]|r")
  print("Step 1: Type /whisper <player>")
  print("Step 2: Paste this text (300+ chars):")
  print("Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.")
  print("Step 3: Hit ENTER")
  print("Step 4: Immediately type /whisper <same player>")
  print("Step 5: Try to paste the same text again")
  print("Step 6: Check if text is truncated at 255 chars")
  print("")
  print("|cffff9900Check the [TEXT] messages above to see text length|r")

-- ============================================================================
-- TEST: Hook the editbox OnTextChanged event to see what's happening
-- ============================================================================
/run
  if not EditboxChangeMonitor then
    EditboxChangeMonitor = true
    
    print("|cff00ff00[EDITBOX CHANGE MONITOR] Installed|r")
    
    for i = 1, NUM_CHAT_WINDOWS do
      local editbox = _G["ChatFrame" .. i .. "EditBox"]
      if editbox then
        if editbox.hook_applied then
          goto skip_hook
        end
        editbox.hook_applied = true
        
        editbox:HookScript("OnTextChanged", function(self, userInput)
          if userInput then
            local text_len = self:GetText():len()
            print(string.format("|cff00ff00[ONTEXT] %s: %d chars|r", self:GetName(), text_len))
          end
        end)
        
        ::skip_hook::
      end
    end
  end

-- ============================================================================
-- TEST: Direct paste test - paste 300 chars and check what actually gets in
-- ============================================================================
/run
  print("|cffff9900[PASTE TEST]|r")
  print("After you paste, run this to check actual text in editbox:")
  print("/run local eb = ChatFrame1EditBox; print('Text length: ' .. eb:GetText():len())")

-- TEST: Reproduce chat mode switching issue
-- Steps: 1) Enable debug logging (/emotesplitter debug)
--        2) Open chat (/say hello)
--        3) Switch to another mode by typing /whisper username or /yell
--        4) Check if debug messages appear showing limits were reset
--        5) Try typing a very long message - if limits are still locked, you'll see truncation
/run
  print("=== Chat Mode Switch Test ===")
  print("1. Type in chat: /say test")
  print("2. Then type: /whisper player")
  print("3. Watch for [EmoteSplitter DEBUG] messages if limit resets occur")
  print("4. Try pasting a long message to see if it gets truncated")

-- ============================================================================
-- TEST: Find what resets editbox limits after sending a whisper
-- ============================================================================
/run
  if not EditboxLimitTester then
    EditboxLimitTester = {}
    
    print("|cff00ff00[LIMIT TESTER] Starting comprehensive editbox monitoring|r")
    print("|cff00ff00[LIMIT TESTER] This will hook Blizzard functions to catch limit resets|r")
    
    -- Monitor frame that checks limits frequently
    local monitor = CreateFrame("Frame")
    monitor.last_limits = {}
    monitor:SetScript("OnUpdate", function(self, elapsed)
      self.time = (self.time or 0) + elapsed
      if self.time < 0.05 then return end
      self.time = 0
      
      for i = 1, NUM_CHAT_WINDOWS do
        local editbox = _G["ChatFrame" .. i .. "EditBox"]
        if editbox then
          local letters = editbox:GetMaxLetters()
          local bytes = editbox:GetMaxBytes()
          local key = "frame" .. i
          
          -- Track changes
          if self.last_limits[key] then
            if self.last_limits[key].letters ~= letters or self.last_limits[key].bytes ~= bytes then
              print(string.format("|cffff6b6b[LIMIT CHANGED] ChatFrame%d: (%d->%d letters, %d->%d bytes) Visible=%s, Focus=%s|r", 
                i, 
                self.last_limits[key].letters, letters,
                self.last_limits[key].bytes, bytes,
                tostring(editbox:IsVisible()),
                tostring(editbox:HasFocus())
              ))
              -- Print stack trace to see where this came from
              print("|cffff6b6b[STACK TRACE]:|r")
              for j = 2, 10 do
                local info = debug.getinfo(j)
                if not info then break end
                print(string.format("  [%d] %s:%d in %s", j-1, info.short_src, info.currentline, info.name or "?"))
              end
            end
          end
          
          self.last_limits[key] = { letters = letters, bytes = bytes }
        end
      end
    end)
    
    EditboxLimitTester.monitor = monitor
    print("|cff00ff00[LIMIT TESTER] Monitor created|r")
  end

-- Hook key functions that might reset limits
/run
  if not FunctionHooksApplied then
    FunctionHooksApplied = true
    
    -- Track when messages are sent
    local orig_send = C_ChatInfo.SendChatMessage
    if orig_send then
      C_ChatInfo.SendChatMessage = function(msg, chatType, ...)
        print("|cff00ffff[SEND START] Sending " .. chatType .. " message|r")
        for i = 1, NUM_CHAT_WINDOWS do
          local eb = _G["ChatFrame" .. i .. "EditBox"]
          if eb then
            print(string.format("  ChatFrame%d: Letters=%d, Bytes=%d", i, eb:GetMaxLetters(), eb:GetMaxBytes()))
          end
        end
        local result = orig_send(msg, chatType, ...)
        print("|cff00ffff[SEND END] Message sent|r")
        for i = 1, NUM_CHAT_WINDOWS do
          local eb = _G["ChatFrame" .. i .. "EditBox"]
          if eb then
            print(string.format("  ChatFrame%d: Letters=%d, Bytes=%d", i, eb:GetMaxLetters(), eb:GetMaxBytes()))
          end
        end
        return result
      end
    end
    
    -- Hook ChatFrameUtil functions
    if ChatFrameUtil then
      if ChatFrameUtil.UpdateEditBox then
        hooksecurefunc(ChatFrameUtil, "UpdateEditBox", function(editbox)
          print(string.format("|cffff6b6b[HOOK] ChatFrameUtil.UpdateEditBox called on %s|r", editbox:GetName() or "unknown"))
          if editbox then
            print(string.format("  MaxLetters=%d, MaxBytes=%d", editbox:GetMaxLetters(), editbox:GetMaxBytes()))
          end
        end)
      end
      
      if ChatFrameUtil.SetChannel then
        hooksecurefunc(ChatFrameUtil, "SetChannel", function(editbox, ...)
          print(string.format("|cffff6b6b[HOOK] ChatFrameUtil.SetChannel called|r"))
          if editbox then
            print(string.format("  MaxLetters=%d, MaxBytes=%d", editbox:GetMaxLetters(), editbox:GetMaxBytes()))
          end
        end)
      end
      
      if ChatFrameUtil.OpenChat then
        hooksecurefunc(ChatFrameUtil, "OpenChat", function(...)
          print("|cffff6b6b[HOOK] ChatFrameUtil.OpenChat called|r")
        end)
      end
    end
    
    print("|cff00ff00[FUNCTION HOOKS] Applied to key chat functions|r")
  end

-- Manual test: Send a whisper and watch for limit resets
/run
  print("|cffff9900[TEST INSTRUCTIONS]:|r")
  print("1. Run this macro")
  print("2. Type a very long whisper (> 255 chars) to any player")
  print("3. Hit enter to send it")
  print("4. Watch the chat output for when limits change")
  print("5. Try typing another long whisper")
  print("")
  print("|cffff9900[EXPECTED OUTPUT]:|r")
  print("- [SEND START] before message sends")
  print("- [SEND END] after message sends")
  print("- [LIMIT CHANGED] if limits reset between sends")
  print("- [HOOK] messages from hooked Blizzard functions")

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