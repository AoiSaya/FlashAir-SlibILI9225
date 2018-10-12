-----------------------------------------------
-- draw mandelbrot @ILI9225 for W4.00.03
-- Copyright (c) 2018, Saya
-- All rights reserved.
-- 2018/10/13 rev.0.01
-----------------------------------------------

local function script_path()
	local  str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

local function isBreak()
	return (fa.sharedmemory("read", 0x00, 0x01, "") == "!")
end

fa.sharedmemory("write", 0x00, 0x01, "-")

-- main
local myDir  = script_path()
local libDir = myDir.."lib/"
local lcd = require(libDir .. "SlibILI9225")

local rot	= 1
local mx,my = 220,176
lcd:init(1,rot,mx, my,0)
lcd:writeStart()
lcd:cls()
lcd:dspOn()

local x1,y1,x2,y2 = -2.10,-1.2,0.9,1.2
local xDot = 220
local yDot = 176
local n    = 100
local t, x, y, r, g, r2, g2

t=os.clock()
for i=0,xDot-1 do
	x = i*(x2-x1)/xDot+x1
	for j=0, yDot-1 do
		y = j*(y2-y1)/yDot+y1
		r,g = 0,0
		r2,g2 = r*r,g*g
		for k=1, n do
			r,g = r2-g2+x,2*r*g+y
			r2,g2 = r*r,g*g
			if r2+g2>4 then
				lcd:pset(i,j,0xF000+0x0044*(k-1))
				break
			end
		end
		if isBreak() then return end
	end
end
t = os.clock()-t
print(t)

return t
