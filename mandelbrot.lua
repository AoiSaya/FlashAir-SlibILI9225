-----------------------------------------------
-- draw mandelbrot @ILI9225 for W4.00.03
-- Copyright (c) 2018, Saya
-- All rights reserved.
-- 2018/10/14 rev.0.02
-----------------------------------------------

local function script_path()
	local  str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

local function isBreak()
	sleep(1)
	return (fa.sharedmemory("read", 0x00, 0x01, "") == "!")
end

fa.sharedmemory("write", 0x00, 0x01, "-")

-- main
local myDir  = script_path()
local libDir = myDir.."lib/"
local lcd = require(libDir .. "SlibILI9225")

local rot	= 1 	   -- LCD direction
local mx,my = 220,176  -- LCD size
lcd:init(1,rot,mx, my,0)
lcd:writeStart()
lcd:cls()
lcd:dspOn()

local x0,y0 = -0.6,0 -- central coordinates
local mag	= 3/4.4  -- magnification
local n 	= 100	 -- repeat upper limit
local wx1,wy1,wx2,wy2 = 0,0,mx-1,my-1  -- drawing area

local xDot	= wx2-wx1+1
local yDot	= wy2-wy1+1
local x1,y1 = x0-(mag*xDot)/100.0, y0-(mag*yDot)/100.0
local x2,y2 = x0+(mag*xDot)/100.0, y0+(mag*yDot)/100.0
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
	end
	if isBreak() then return -1 end
end
t = os.clock()-t
print(t)

return t
