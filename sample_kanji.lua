-----------------------------------------------
-- Sample of Kanji for SlibILI9225.lua for W4.00.03
-- Copyright (c) 2019, AoiSaya
-- All rights reserved.
-- 2019/06/02 rev.0.03
-----------------------------------------------
function chkBreak(n)
	sleep(n or 0)
	if fa.sharedmemory("read", 0x00, 0x01, "") == "!" then
		error("Break!",2)
	end
end
fa.sharedmemory("write", 0x00, 0x01, "-")

local script_path = function()
	local  str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

-- main
local myDir  = script_path()
local libDir = myDir.."lib/"
local fontDir= myDir.."font/"
local lcd  = require(libDir .. "SlibILI9225")
local jfont= require(libDir .. "SlibJfont")
local f24x24 = jfont:open("jiskan24-2003-1.sef")
local f12x24 = jfont:open("12x24rk.sef")
local fw, xn

local mx,my = 220,176

lcd:init(2, 3, mx, my)
lcd:dspOn()

lcd:cls()
lcd:setFont(jfont)
jfont:setFont(f12x24,f24x24)

lcd:locate(11,8,2,1,4);
lcd:println(jfont:utf82euc("令和元年"))
lcd:println(jfont:utf82euc("陸月弐日"))
lcd:println(jfont:utf82euc("(日曜日)"))

jfont:close()

return
