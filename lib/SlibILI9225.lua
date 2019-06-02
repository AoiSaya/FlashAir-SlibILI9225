-----------------------------------------------
-- SoraMame library of ILI9225@65K for W4.00.03
-- Copyright (c) 2018,2019 AoiSaya
-- All rights reserved.
-- 2019/06/02 rev.0.30 support Kanji font
-----------------------------------------------
--[[
Pin assign
	PIO	 SPI	TYPE1	TYPE2	TYPE3
CMD	0x01 DO 	SDI		SDI		SDI
D0	0x02 CLK	CLK		CLK		CLK
D1	0x04 CS 	RS		RS		RS
D2	0x08 DI 	CS		CS		CS
D3	0x10 RSV	RST		PIO		LED
--]]

local ILI9225 = {}

--[Low layer functions]--

function ILI9225:writeString(cmd,str,...)
	local spi = fa.spi
	spi("cs",0)
	spi("write",cmd)
	spi("cs",1)
	spi("write",str,...)
end

function ILI9225:writeWord(cmd,...)
	local spi = fa.spi
	spi("cs",0)
	spi("write",cmd)
	spi("cs",1)
	spi("bit",16)
	spi("write",...)
	spi("bit",8)
end

function ILI9225:writeCmd(cmd)
	local spi = fa.spi
	spi("cs",0)
	spi("write", cmd)
	spi("cs",1)
end

function ILI9225:pinCfg(cs2,cs,dc,ck,dt) -- 0:low, 1:high, 2:Hi-Z, 4:not change
	local	pinIo = self.pinIo
	local	pinDt = self.pinDt
	local	ba	  = bit32.band
	local	data, mask
	for i,d in ipairs({cs2,cs,dc,ck,dt}) do
		if d<4 then
			data =2^(5-i)
			mask =-data-1
			pinIo=ba(pinIo,mask)
			pinDt=ba(pinDt,mask)
			if d<2	then pinIo=pinIo+data end
			if d==1 then pinDt=pinDt+data end
		end
	end

	self.pinIo = pinIo
	self.pinDt = pinDt

	return pinIo,pinDt
end

function ILI9225:pinSet(cs2,cs,rs,ck,dt)
	local pinIo,pinDt = self:pinCfg(cs2,cs,dc,ck,dt)
	s,dt = fa.pio(pinIo,pinDt)

	return s,dt
end

--[[
function ILI9225:readWord(cmd,num)
	local i, s, dt, val
	local bx  = bit32.extract
	local bb  = bit32.band

	self:writeStart()
	self:writeWord(0x66,0x0001)

	for i=7,0,-1 do
		dt = bx(cmd,i)
		self.pinSet(4,4,0,0,dt)
		self.pinSet(4,4,0,1,dt)
	end
	val = 0
	for i= 0,15 do
		self.pinSet(4,4,1,0,2)
		s,dt = self.pinSet(4,4,1,1,2)
		val = val*2+bb(dt,0x01)
	end
	self.pinSet(4,4,1,0,2)
	self:writeWord(0x66,0x0000)

	return val
end
--]]

function ILI9225:writeRam(h,v,str,...)
	self:writeWord(0x20,h)
	self:writeWord(0x21,v)
	self:writeString(0x22,str,...)
end

function ILI9225:writeRamCmd(h,v)
	local spi = fa.spi
	self:writeWord(0x20,h)
	self:writeWord(0x21,v)
	self:writeCmd(0x22)
end

function ILI9225:writeRamData(str,...)
	fa.spi("write",str,...)
end

function ILI9225:setRamMode(BGR,MDT,DRC)
	-- BGR 0:BGR order,1:RGB order
	-- MDT 0:16bit,3:24bit
	-- DRC 0:incliment to up,1:incliment to right
	-- set GRAM writeWord direction and [12]BGR,[9:8]MDT,[5:4]ID=3,[3]AM
	local val = 0x0000
			+ BGR * 0x1000
			+ MDT * 0x100
			+ self.id * 0x10
			+ bit32.bxor(DRC,(self.swp and 1 or 0)) * 0x8
	self:writeWord(0x03,val)
end

function ILI9225:setWindow(h1,v1,h2,v2)
	if h1>h2 then h1,h2=h2,h1 end
	if v1>v2 then v1,v2=v2,v1 end
	self:writeWord(0x36,h2)
	self:writeWord(0x37,h1)
	self:writeWord(0x38,v2)
	self:writeWord(0x39,v1)
end

function ILI9225:resetWindow()
	self:writeWord(0x36,self.hSize-1)
	self:writeWord(0x37,0)
	self:writeWord(0x38,self.rOfs+self.vSize-1)
	self:writeWord(0x39,self.rOfs)
end

function ILI9225:pTrans(x,y)
	if self.swp then x,y = y,x end
	return self.hDrc*x+self.hOfs, self.vDrc*y+self.vOfs
end

function ILI9225:bTrans(x1,y1,x2,y2)
	local hD,vD,hO,vO = self.hDrc, self.vDrc, self.hOfs, self.vOfs
	if self.swp then x1,y1,x2,y2 = y1,x1,y2,x2 end
	return hD*x1+hO, vD*y1+vO, hD*x2+hO, vD*y2+vO
end

function ILI9225:clip(x1,y1,x2,y2)
	local xMax = self.xMax
	local yMax = self.yMax
	local a1,ret
	local xd,yd,x0,y0,xm,ym

	xd = x2-x1
	yd = y2-y1
	a1 = y1*x2-y2*x1
	y0 = (xd==0) and y1 or a1/xd
	ym = (xd==0) and y2 or xMax*yd/xd+y0
	x0 = (yd==0) and x1 or -a1/yd
	xm = (yd==0) and x2 or yMax*xd/yd+x0

	if x1>x2 then x1,y1,x2,y2=x2,y2,x1,y1 end
	if x1<0 then x1,y1=0,y0 end
	if x2>xMax then x2,y2=xMax,ym end

	if y1>y2 then x1,y1,x2,y2=x2,y2,x1,y1 end
	if y1<0 then x1,y1=x0,0 end
	if y2>yMax then x2,y2=xm,yMax end

	ret = x1<0 or y1<0 or x2>xMax or y2>yMax or x2<0 or y2<0 or x1>xMax or y1>yMax

	return ret,x1,y1,x2,y2
end

function ILI9225:setup()
	self:writeStart()
-- initial sequence
	self:writeWord(0x01,0x001C+self.gs*0x200) -- [9]GS=0,[8]SS=0
	self:writeWord(0x02,0x0100) -- set 1 line inversion0
	self:setRamMode(0,0,0)		-- BGR order,24bit color,incliment to up
	self:writeWord(0x07,0x0000) -- Display off
	self:writeWord(0x08,0x0808) -- set the back porch and front porch
	self:writeWord(0x0B,0x1100) -- set the clocks number per line
	self:writeWord(0x0C,0x0000) -- CPU interface
	self:writeWord(0x0F,0x0D01) -- Set Osc
	self:writeWord(0x20,0x0000) -- RAM Address
	self:writeWord(0x21,0x0000) -- RAM Address

-- Power-on sequence
	sleep(50)
	self:writeWord(0x10,0x0800) -- Set SAP,DSTB,STB
	self:writeWord(0x11,0x103B) -- Set APON,PON,AON,VCI1EN,VC
	sleep(50)
	self:writeWord(0x12,0x6121) -- Set BT,DC1,DC2,DC3
	self:writeWord(0x13,0x006F) -- Set GVDD
	self:writeWord(0x14,0x495F) -- Set VCOMH/VCOML voltage
	self:writeWord(0x15,0x0020) -- Set VCI recycling

-- Set GRAM area
	self:writeWord(0x30,0x0000)
	self:writeWord(0x31,0x00DB)
	self:writeWord(0x32,0x0000)
	self:writeWord(0x33,0x0000)
	self:writeWord(0x34,0x00DB)
	self:writeWord(0x35,0x0000)
	self:writeWord(0x36,0x00AF)
	self:writeWord(0x37,0x0000)
	self:writeWord(0x38,0x00DB)
	self:writeWord(0x39,0x0000)

-- Set GAMMA curve
	self:writeWord(0x50,0x0000)
	self:writeWord(0x51,0x0808)
	self:writeWord(0x52,0x080A)
	self:writeWord(0x53,0x000A)
	self:writeWord(0x54,0x0A08)
	self:writeWord(0x55,0x0808)
	self:writeWord(0x56,0x0000)
	self:writeWord(0x57,0x0A00)
	self:writeWord(0x58,0x0710)
	self:writeWord(0x59,0x0710)
	sleep(50)
	self:writeEnd()
end

--[For user functions]--

-- type: 1:D3=RST=H/L, 2:D3=Hi-Z(no hard reset)
-- rotate: 0:upper pin1, 1:upper pin5, 2:lower pin1, 3:lower pin11

function ILI9225:init(type,rotate,xSize,ySize,rOffset,dOffset)
	local id,gs,swp,hDrc,vDrc,hSize,vSize

	rOffset = rOffset or 0
	dOffset = dOffset or 0

	self.type = type
	self.csmd = 0
	self.pinIo= 0x00
	self.pinDt= 0x00
	self:pinCfg(1,1,1,0,0)

	if type==4 or type==21 or type==22 or type==23 then
		self.csmd = 1
		self:pinCfg(1,2,1,0,0)
	end
	if type==2	then
		self.csmd = 0
		self:pinCfg(2,1,1,0,0)
	end

	self:ledOff()

	if rotate==0 then id,gs,swp,hDrc,vDrc = 0,0,false,-1, 1 end
	if rotate==1 then id,gs,swp,hDrc,vDrc = 0,1,true,  1,-1 end
	if rotate==2 then id,gs,swp,hDrc,vDrc = 3,0,false, 1,-1 end
	if rotate==3 then id,gs,swp,hDrc,vDrc = 3,1,true, -1, 1 end

	hSize = swp and ySize or xSize
	vSize = swp and xSize or ySize

	self.id	 = id
	self.gs	 = gs
	self.swp = swp
	self.hSize = hSize
	self.vSize = vSize
	self.hDrc = hDrc
	self.vDrc = vDrc
	self.hOfs = (hDrc>0) and rOffset or rOffset+hSize-1
	self.vOfs = (vDrc>0) and dOffset or dOffset+vSize-1
	self.mRot = mRot
	self.xMax = xSize-1
	self.yMax = ySize-1
	self.rOfs = rOffset
	self.dOfs = dOffset

	self.x	  = 0
	self.y	  = 0
	self.x0	  = 0
	self.y0	  = 0
	self.xspc = 0
	self.yspc = 0
	self.yh   = 0
	self.fc	  = "\255\255"
	self.bc	  = "\000\000"
	self.font = {}
	self.mag  = 1
	self.enable= 0
	self.spiPeriod = 1000
	self.spiMode   = 0
	self.spiBit    = 8
	self.xFlip1= 0
	self.yFlip1= 0
	self.xFlip2= 0
	self.yFlip2= 0

-- reset sequence
	if type==1 then
		self:pinSet(1,0,0,0,0)
		sleep(1)
		self:pinSet(0,0,0,0,0)
		sleep(10)
		self:pinSet(1,0,0,0,0)
		sleep(5)
		self:pinSet(1,1,1,0,0)
	end
	self:writeStart()
	self:writeWord(0x28,0xCE) -- Software reset
	self:writeEnd()
	sleep(50)
	self:setup()

	self:writeStart()
	self:cls()
	collectgarbage()
end

function ILI9225:duplicate()
	local new = {}
	for k,v in pairs(self) do
		new[k] = v
	end
	collectgarbage()

	return new
end

function ILI9225:writeStart()
	local en = self.enable
	local type = self.type
	local cs, cs2

	cs = (en==1 or en==3) and ((self.csmd==1) and 2 or 1) or 4
	cs2= (en==2 or en==3) and 1 or 4
	self:pinSet(cs2,cs,4,4,4)

	fa.spi("mode",0)
	fa.spi("init",1)
	fa.spi("bit",8)
	en = (type==22) and 2 or ((type==23) and (enable or 3) or 1)
	cs = (en==1 or en==3) and 0 or 4
	cs2= (en==2 or en==3) and 0 or 4
	self:pinSet(cs2,cs,4,4,4)

	self.enable = en
end

function ILI9225:writeEnd()
	local en = self.enable
	local cs,cs2

	if en>0 then
		self:writeCmd(0x00) -- NOP
		cs = (en==1 or en==3) and ((self.csmd==1) and 2 or 1) or 4
		cs2= (en==2 or en==3) and 1 or 4
		self:pinSet(cs2,cs,4,4,4)

		self.enable = 0
	end
end

function ILI9225:cls()
	self:resetWindow()
	self:writeRam(0,self.hSize*self.rOfs*2,"",self.hSize*self.vSize*2)
	collectgarbage()
end

function ILI9225:dspOn()
	self:writeWord(0x07,0x1017)
end

function ILI9225:dspOff()
	self:writeWord(0x07,0x1014)
end

function ILI9225:pset(x,y,color)
	color = color or self.fc
	if (x<0 or x>self.xMax) then return end
	if (y<0 or y>self.yMax) then return end
	local h,v = self:pTrans(x,y)
	self:writeWord(0x20,h)
	self:writeWord(0x21,v)
	self:writeWord(0x22,color)
end

function ILI9225:line(x1,y1,x2,y2,color)
	color = color or self.fc
	local swap
	local h1,h2,hn,ha,hb,hd,hv,hr,hs,h
	local v1,v2,vn,vd,v
	local xMax = self.xMax
	local yMax = self.yMax
	local bx = bit32.extract
	local mf = math.floor
	local col = string.char(bx(color,8,8),bx(color,0,8))
	local dat, ret

	if	x1<0 or y1<0 or x2>xMax or y2>yMax or x2<0 or y2<0 or x1>xMax or y1>yMax then
		if self.clip then ret,x1,y1,x2,y2 = self:clip(x1,y1,x2,y2) else ret = true end
		if ret then return end
	end

	x1 = mf(x1+0.5)
	x2 = mf(x2+0.5)
	y1 = mf(y1+0.5)
	y2 = mf(y2+0.5)
	h1,v1,h2,v2 = self:bTrans(x1,y1,x2,y2)
	hn = math.abs(h2-h1)+1
	vn = math.abs(v2-v1)+1
	if hn>vn then
		swap = false
		if self.swp then self:setRamMode(0,0,1) end
		dat = string.rep(col,self.hSize)
	else
		swap = true
		if not self.swp then self:setRamMode(0,0,1) end
		dat = string.rep(col,self.vSize)
		h1,v1,h2,v2 = v1,h1,v2,h2
		hn,vn = vn,hn
	end
	hd = (self.id==0) and -1 or 1
	if h1*hd>h2*hd then h1,v1,h2,v2 = h2,v2,h1,v1 end
	vd = (v1<v2) and 1 or -1
	hv = hd*vd*hn/vn
	ha = h1
	hr = h1+0.5
	hs = hd*2
	for i=v1,v2,vd do
		hb = mf((i-v1+vd)*hv+hr)
		h = swap and i or ha
		v = swap and ha or i
		self:writeRam(h,v,dat,(hb-ha)*hs)
		ha = hb
	end
	self:setRamMode(0,0,0)
	dat = nil
	collectgarbage()
end

function ILI9225:box(x1,y1,x2,y2,color)
	color = color or self.fc
	self:line(x1,y1,x2,y1,color)
	self:line(x2,y1,x2,y2,color)
	self:line(x2,y2,x1,y2,color)
	self:line(x1,y2,x1,y1,color)
end

function ILI9225:boxFill(x1,y1,x2,y2,color)
	color = color or self.fc
	local xMax = self.xMax
	local yMax = self.yMax
	local bx = bit32.extract
	local mf = math.floor
	local len,dat,col,vd,hd

	if x1>x2 then x1,x2 = x2,x1 end
	if y1>y2 then y1,y2 = y2,y1 end
	if x2<0 or y2<0 or x1>xMax or y1>yMax then return end
	if x1<0 then x1=0 end
	if y1<0 then y1=0 end
	if x2>xMax then x2=xMax end
	if y2>yMax then y2=yMax end

	col = string.char(bx(color,8,8),bx(color,0,8))
	x1 = mf(x1+0.5)
	x2 = mf(x2+0.5)
	y1 = mf(y1+0.5)
	y2 = mf(y2+0.5)
	h1,v1,h2,v2 = self:bTrans(x1,y1,x2,y2)
	hn = math.abs(h2-h1)+1
	vn = math.abs(v2-v1)+1
	if hn>vn then
		if self.swp then self:setRamMode(0,0,1);h1=h2 end
		dat = string.rep(col,hn)
		vd = (v1>v2) and -1 or 1
		for i=v1,v2,vd do
			self:writeRam(h1,i,dat)
		end
	else
		if not self.swp then self:setRamMode(0,0,1);v1=v2 end
		dat = string.rep(col,vn)
		hd = (h1>h2) and -1 or 1
		for i=h1,h2,hd do
			self:writeRam(i,v1,dat)
		end
	end

	self:setRamMode(0,0,0)
	dat = nil
	collectgarbage()
end

function ILI9225:circle(x,y,xr,yr,color)
	color = color or self.fc
	local c
	local x1,y1,x2,y2
	local sin = math.sin
	local cos = math.cos
	local pi  = math.pi

	x1 = x + xr
	y1 = y
	for i=1,64 do
		c = 2*pi*i/64
		x2 = x + xr*cos(c)
		y2 = y + yr*sin(c)
		self:line(x1,y1,x2,y2,color)
		x1 = x2
		y1 = y2
	end
	collectgarbage()
end

function ILI9225:circleFill(x,y,xr,yr,color)
	color = color or self.fc
	local h1,v1,h2,v2
	local x1,x2,y1,y2,xs,r2,xn
	local xMax = self.xMax
	local yMax = self.yMax
	local bx  = bit32.extract
	local mf  = math.floor
	local sqrt= math.sqrt
	local col = string.char(bx(color,8,8),bx(color,0,8))
	local dat = string.rep(col,(xMax+1))

	x = mf(x+0.5)
	y = mf(y+0.5)
	r2 = yr*yr

	if y>=0 and y<=yMax then
		xs = mf(xr)
		x1 = x-xs
		x2 = x+xs
		if x1<0 then x1=0 end
		if x2>xMax then x2=xMax end
		xn= (x2-x1+1)*2
		h1,v1 = self:pTrans(x1,y)
		self:writeRam(h1,v1,dat,xn)
	end

	for i=1,yr do
		xs = mf(sqrt(r2-i*i)*xr/yr)
		x1 = x-xs
		x2 = x+xs
		y1 = y-i
		y2 = y+i
		if x1<0 then x1=0 end
		if x2>xMax then x2=xMax end
		xn= (x2-x1+1)*2
		h1,v1,h2,v2 = self:bTrans(x1,y1,x2,y2)
		if y1>=0 then self:writeRam(h1,v1,dat,xn) end
		if self.swp then v2=v1 else h2=h1 end
		if y2<=yMax then self:writeRam(h2,v2,dat,xn) end
	end

	dat = nil
	collectgarbage()
end

function ILI9225:put(x,y,bitmap)
	local bx,by= 0,0
	local xMax = self.xMax
	local yMax = self.yMax
	local bw   = bitmap.width
	local bh   = bitmap.height
	local bb   = bitmap.bit/8
	local flat = bitmap.flat
	local br   = bw*bb
	local bi,bn
	local h1,v2,hs,vs

	if( x>xMax or y>yMax or x+bw<0 or y+bh<0 ) then return end
	if( x<0 ) then x,bw,bx=0,bw+x,-x end
	if( y<0 ) then y,bh=0,bh+y end
	if( x+bw>xMax+1 ) then bw=xMax+1-x end
	if( y+bh>yMax+1 ) then bh,by=yMax+1-y,y+bh-yMax-1 end
	h1,v2 = self:pTrans(x,y+bh-1)
	hs = (self.id==0) and 1 or -1
	vs = hs
	if self.swp then vs=0 else hs=0 end

	if bb==3 then
		self:setRamMode(0,3,0)
	end
	if bx==0 then
		if( flat==0 )then
			bn = bw*bb
			for i=0,bh-1 do
				self:writeRam(h1-i*hs,v2-i*vs,bitmap.data[by+i+1],bn)
			end
		else
			for i=0,bh-1 do
				bs = (by+i)*br+1
				bn = bs+bw*bb-1
				self:writeRam(h1-i*hs,v2-i*vs,bitmap.data:sub(bs,bn))
			end
		end
	else
		bs = bx*bb+1
		bn = (bx+bw)*bb
		if( flat==0 )then
			for i=0,bh-1 do
				self:writeRam(h1-i*hs,v2-i*vs,bitmap.data[by+i+1]:sub(bs,bn))
				collectgarbage()
			end
		else
			bs = bs+by*br
			bn = bn+by*br
			for i=0,bh-1 do
				self:writeRam(h1-i*hs,v2-i*vs,bitmap.data:sub(bs,bn))
				bs = bs+br
				bn = bn+br
				collectgarbage()
			end
		end
	end
	self:setRamMode(0,0,0)
	collectgarbage()
end

function ILI9225:put2(x,y,bitmap)
	local x2 = x+bitmap.width-1
	local y2 = y+bitmap.height-1
	local h1,v1,h2,v2 = self:bTrans(x,y,x2,y2)
	self:setWindow(h1,v1,h2,v2)
	self:writeRam(h1,v2,bitmap.data)
	self:resetWindow()
	collectgarbage()
end

function ILI9225:locate(x,y,mag,xspc,yspc)
	local bx = bit32.extract
	local mf = math.floor

	if x then
		self.x	= mf(x+0.5)
		self.x0 = self.x
	end
	if y then
		self.y	= mf(y+0.5)
		self.y0 = self.y
	end
	if mag then
		self.mag= mf(mag)
	end
	if mag then
		self.mag= mf(mag)
	end
	if xspc then
		self.xspc= mf(xspc)
	end
	if yspc then
		self.yspc= mf(yspc)
	end
end

function ILI9225:color(fgcolor,bgcolor)
	local bx = bit32.extract

	if fgcolor then
		self.fc = string.char(bx(fgcolor,8,8),bx(fgcolor,0,8))
	end
	if bgcolor then
		self.bc = string.char(bx(bgcolor,8,8),bx(bgcolor,0,8))
	end
end

function ILI9225:setFont(font)
	if font then
		self.font = font
	end
end

function ILI9225:print(str)
	local n,c,bk,bj,is,slen
	local h1,v1,h2,v2,b,h,w
	local s = ""
	local p = {}
	local font = self.font
	local fh1,fh2,fh
	local xs = self.xspc
	local mg = self.mag
	local bx = bit32.extract
	local mf = math.floor
	local s0 = string.rep(self.bc,mg)
	local s1 = string.rep(self.fc,mg)
	local ti = table.insert
	local rows = 1

	if font.fontList then -- jfont using
		fh1 = font.font1.height
		fh2 = font.font2.height
		fh = (fh1>fh2) and fh1 or fh2
	else -- ANK only
		fh = font.height
	end
	yh = fh + self.yspc
	self.yh = yh

	self:setRamMode(0,0,1)

	h1,v1,h2,v2 = self:bTrans(self.x,self.y,self.xMax,self.y+mg*fh-1)
	self:setWindow(h1,v1,h2,v2)
	if self.id==0 then self:writeRamCmd(h1,v2) else	self:writeRamCmd(h2,v1) end

	bk = 0
	is = 1
	n  = 0
	slen = #str
	while is<=slen do
		if font.fontList then -- jfont using
			b,h,w,is = font:getFont(str, is)
		else -- ANK only
			c = str:sub(is,is)
			b,h,w,is = font[c],font.height,font.width,is+1
		end

		if self.x+mg*(w+xs)-1>self.xMax then
			if bk>0 then
				s = table.concat(p)
				self:writeRamData(s:rep(mg))
				bk,p,s=0,{},""
				collectgarbage()
			end
			self.x,self.y = self.x0,self.y+mg*yh
			if self.y+mg*yh-1>self.yMax then
				self.y = self.y0
				break
			end
			rows = rows+1
			h1,v1,h2,v2 = self:bTrans(self.x,self.y,self.xMax,self.y+mg*fh-1)
			self:setWindow(h1,v1,h2,v2)
			if self.id==0 then self:writeRamCmd(h1,v2) else	self:writeRamCmd(h2,v1) end
		end
		for j=1,w+xs do
			if j>w then
				bj,bk=0,bk+h
			else
				bj,bk=b[j],bk+h
			end
			for k=h-1,0,-1 do ti(p,bx(bj,k)>0 and s1 or s0) end
			if bk>800 or mg>1 then
				s = table.concat(p)
				self:writeRamData(s:rep(mg))
				bk,p,s=0,{},""
				collectgarbage()
			end
		end
		self.x = self.x+mg*(w+xs)
		n = is-1
	end
	if bk>0 then
		s = table.concat(p)
		self:writeRamData(s:rep(mg))
	end

	bk,p,s=0,{},""
	collectgarbage()
	self:resetWindow()
	self:setRamMode(0,0,0)

	return self.x,self.y,n,rows
end

function ILI9225:println(str)
	local x,y,n,rows = self:print(str)
	local yh = self.yh

	self.x,self.y = self.x0,self.y+self.mag*yh
	if self.y+self.mag*yh-1>self.yMax then
		self.y = self.y0
	end

	return self.x,self.y,n,rows
end

function ILI9225:pio(ctrl, data)
	local dat,s,ret

	if self.type>1 then
		s,ret = self:pinSet((1-ctrl)*2+data,4,4,4,4)
		if s==1 then
			ret = bit32.btest(ret,0x10) and 1 or 0
		end
	end

	return ret
end

function ILI9225:ledOn()
	if self.type==3 then
		sleep(30)
		self:pio(1,1)
	end
end

function ILI9225:ledOff()
	if self.type==3 then
		self:pio(1,0)
	end
end

function ILI9225:spiInit(period,mode,bit,cstype)
	if self.type~=4 then
		return
	end
	self.spiPeriod = period
	self.spiMode   = mode
	self.spiBit    = bit
	self.spiCstype = cstype or 0
	local cs = (cstype==2) and 2 or 1-cstype
	self:pinSet(cs,4,4,4,4)
end

function ILI9225:spiWrite(data,num)
	return self.spiSub(0,data,num)
end

function ILI9225:spiRead(data,num)
	return self.spiSub(1,data,num)
end

collectgarbage()
return ILI9225
