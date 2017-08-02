--[[
	Global Keys - Initialization
]]

local path = (...):gsub("%.init$", ""):match("%.?(.-)$") .. "."

if (jit.os ~= "Windows") then
	error("LOVE Global Keys only functions on Windows!")
end

local thread_source = [[
local path, commands, keys = ...

local ffi = require("ffi")
local win32 = require(path .. "win32")
local keymap = require(path .. "keymap")

local hook = win32.SetWindowsHookEx(win32.WH_KEYBOARD_LL,
	ffi.cast("HOOKPROC", function(code, wParam, lParam)
		if (code >= 0) then
			local status = tonumber(ffi.cast("unsigned int", wParam))
			local down = (status == 256)
			local kbdStruct = ffi.cast("KBDLLHOOKSTRUCT*", lParam)

			local code = kbdStruct.vkCode

			-- Find the keyname from the scancode
			local bit = require("bit")
			local c_str = ffi.new("char[?]", 256)
			local extended = bit.band(kbdStruct.flags, bit.tobit(0x01))
			local scanCode = kbdStruct.scanCode
			scanCode = (extended == 1) and bit.bor(scanCode, bit.tobit(0x100)) or scanCode

			if extended == 1 then
				-- If it's an extended key, set the extended bit
				scanCode = bit.bor(scanCode, bit.tobit(0x100))
			end

			local result = win32.GetKeyNameText(bit.lshift(scanCode, 16), c_str, ffi.sizeof(c_str));

			-- Let the keymap override it if possible
			local name 	= keymap[code] or ffi.string(c_str)

			keys:push({down, name, code})
		end

		return 0
	end),
	nil, 0
)

local msg = ffi.new("MSG[1]")
while (win32.GetMessage(msg, nil, 0, 0) > 0) do
	win32.TranslateMessage(msg)
	win32.DispatchMessage(msg)

	if (commands:pop() == "stop") then
		break
	end
end

win32.UnhookWindowsHookEx(hook)
]]

local gkeys = {
	__thread = nil,
	__running = false,
	__command_channel = nil,
	__keys_channel = nil
}

function gkeys.start()
	if (gkeys.__running) then
		return
	end
	gkeys.__thread = love.thread.newThread(thread_source)
	gkeys.__command_channel = love.thread.newChannel()
	gkeys.__keys_channel = love.thread.newChannel()

	gkeys.__thread:start(path, gkeys.__command_channel, gkeys.__keys_channel)

	gkeys.__running = true
end

function gkeys.stop()
	if (not gkeys.__running) then
		return
	end

	gkeys.__command_channel:send("stop")
	gkeys.__running = false
end

function gkeys.update()
	while (true) do
		local msg = gkeys.__keys_channel:pop()

		if (not msg) then
			break
		end

		if (msg[1]) then
			if (love.gkeypressed) then
				love.gkeypressed(msg[2], msg[3])
			end
		else
			if (love.gkeyreleased) then
				love.gkeyreleased(msg[2], msg[3])
			end
		end
	end
end

return gkeys
