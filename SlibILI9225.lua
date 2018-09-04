-----------------------------------------------
-- SoraMame library of ILI9225@65K for W4.00.03
-- Copyright (c) 2018, Saya
-- All rights reserved.
-- 2018/09/04 rev.0.18 print faster
-----------------------------------------------
--[[
Pin assign
	PI	 SPI	init	mRst=1	mRst=0
CMD	0x01 DO 	L		SDI		SDI
D0	0x02 CLK	L		CLK		CLK
D1	0x04 CS 	H		RS		RS
D2	0x08 DI 	I		CS		CS
D3	0x10 RSV	L		Hi-Z	RST
--]]

local ILI9225 = {
mRst  = 0;
id	  = 0;
gs	  = 0;
swp   = false;
xMax  = 176-1;
yMax  = 220-1;
hSize = 176;
vSize = 220;
hDrc  = 1;
vDrc  = 1;
hOfs  = 0;
vOfs  = 0;
rOfs  = 0;
ctrl  = 0x1F;
x	  = 0;
y	  = 0;
x0	  = 0;
ch	  = 0xFF; -- color ch*256+cl, BBBBB_GGGGGG_RRRRR(64K color)
cl	  = 0xFF;
gh	  = 0x00; -- bg color gh*256+gl
gl	  = 0x00;
font  = {};
mag   = 1;
enable= false;
}

-- mRst:reset mode, 0:D3=Hi-Z(no hard reset), 1:D3=RST=H/L
-- mRot:rotate mode, 0:upper pin1, 1:upper pin5, 2:lower pin1, 3:lower pin11

function ILI9225:init(mRst,mRot,xSize,ySize,offset)
	local id,gs,swp,hDrc,vDrc
	if mRst==0 then self.ctrl=0x0F end
	if mRst==1 then self.ctrl=0x1F end
	if mRot==0 then id,gs,swp,hDrc,vDrc = 0,0,false,-1, 1 end
	if mRot==1 then id,gs,swp,hDrc,vDrc = 0,1,true,  1,-1 end
	if mRot==2 then id,gs,swp,hDrc,vDrc = 3,0,false, 1,-1 end
	if mRot==3 then id,gs,swp,hDrc,vDrc = 3,1,true, -1, 1 end

	self.id	 = id
	self.gs	 = gs
	self.swp = swp
	if swp then
		self.hSize = ySize
		self.vSize = xSize
	else
		self.hSize = xSize
		self.vSize = ySize
	end
	self.hDrc = hDrc
	self.vDrc = vDrc
	self.hOfs = (hDrc>0) and 0 or self.hSize-1
	self.vOfs = (vDrc>0) and offset or self.vSize+offset-1
	self.mRot = mRot
	self.xMax = xSize-1
	self.yMax = ySize-1
	self.rOfs = offset;

-- reset sequence
	fa.pio(self.ctrl,0x10) -- RST=1,CS=0,RS=0
	sleep(1)
	fa.pio(self.ctrl,0x00) -- RST=0,CS=0,RS=0
	sleep(10)
	fa.pio(self.ctrl,0x18) -- RST=1,CS=1,RS=0
	self:writeWord(0x28,0xCE) -- Software reset
	sleep(50)
end

function ILI9225:pTrans(x,y)
	if self.swp then x,y = y,x end
	return self.hDrc*x+self.hOfs,self.vDrc*y+self.vOfs
end

function ILI9225:bTrans(x1,y1,x2,y2)
	local hD,vD,hO,vO = self.hDrc,self.vDrc,self.hOfs,self.vOfs
	if self.swp then x1,y1,x2,y2 = y1,x1,y2,x2 end
	return hD*x1+hO,vD*y1+vO,hD*x2+hO,vD*y2+vO
end

function ILI9225:writeStart()
	if not self.enable then
		fa.spi("mode",0)
		fa.spi("init",1) -- 0x17,0x04
		fa.spi("bit",8)
		fa.pio(self.ctrl,0x18) -- CS=1,RS=0
		self.enable = true
	end
end

function ILI9225:writeString(cmd,str,...)
	local spi = fa.spi
	spi("cs",0)
	spi("write",cmd)
	spi("cs",1)
	spi("write",str,...)
end

function ILI9225:writeWord(cmd,data)
	local spi = fa.spi
	spi("cs",0)
	spi("write",cmd)
	spi("cs",1)
	spi("bit",16)
	spi("write",data)
	spi("bit",8)
end

function ILI9225:writeRam(h,v,str,...)
	self:writeWord(0x20,h)
	self:writeWord(0x21,v)
	self:writeString(0x22,str,...)
end

function ILI9225:writeRamCmd(h,v)
	local spi = fa.spi
	self:writeWord(0x20,h)
	self:writeWord(0x21,v)
	spi("cs",0)
	spi("write",0x22)
	spi("cs",1)
end

function ILI9225:writeRamData(str,...)
	fa.spi("write",str,...)
end

function ILI9225:writeEnd()
	if self.enable then
		self:writeWord(0x00,0x0000)
		fa.pio(self.ctrl,0x18) -- CS=1,RS=0
		self.enable = falce
	end
end

function ILI9225:readWord(cmd,num)
	local i,s,dt,ret
	local pio = fa.pio
	local ctrl= self.ctrl
	local bx  = bit32.extract
	local bb  = bit32.band

	self:writeWord(0x66,0x0001)

	for i=7,0,-1 do
		dt = bx(cmd,i,1)
		pio(ctrl,0x10+dt) -- CS=0,RS=0,CLK=0
		pio(ctrl,0x12+dt) -- CS=0,RS=0,CLK=1
	end
	ret = 0
	for i= 0,15 do
		pio(ctrl-0x01,0x14) -- CS=0,RS=1,CLK=0,
		s,dt = pio(ctrl-0x01,0x16) -- CS=0,RS=1,CLK=1
		ret = ret*2+bb(dt,0x01)
	end
	pio(ctrl,0x18) -- CS=1,RS=0
	self:writeWord(0x66,0x0000)

	return ret
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

function ILI9225:pset(x,y,color)
	if (x<0 or x>self.xMax) then return end
	if (y<0 or y>self.yMax) then return end
	local h,v = self:pTrans(x,y)
	self:writeWord(0x20,h)
	self:writeWord(0x21,v)
	self:writeWord(0x22,color)
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

function ILI9225:line(x1,y1,x2,y2,color)
	local i,swap
	local h1,h2,hn,ha,hb,hd,hv,hr,hs,h
	local v1,v2,vn,vd,v
	local xMax = self.xMax
	local yMax = self.yMax
	local bx = bit32.extract
	local mf = math.floor
	local col = string.char(bx(color,8,8),bx(color,0,8))
	local dat

	if	x1<0 or y1<0 or x2>xMax or y2>yMax or x2<0 or y2<0 or x1>xMax or y1>yMax then
		ret,x1,y1,x2,y2 = self:clip(x1,y1,x2,y2)
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
	self:line(x1,y1,x2,y1,color)
	self:line(x2,y1,x2,y2,color)
	self:line(x2,y2,x1,y2,color)
	self:line(x1,y2,x1,y1,color)
end

function ILI9225:boxFill(x1,y1,x2,y2,color)
	local i
	local xMax = self.xMax
	local yMax = self.yMax
	local bx = bit32.extract
	local mf = math.floor
	local len,dat,col,vd,hd

	if x1<0 and x2<0 or x1>xMax and x2>xMax then return end
	if y1<0 and y2<0 or y1>yMax and y2>yMax then return end

	col = string.char(bx(color,8,8),bx(color,0,8))

	x1 = mf(x1+0.5)
	x2 = mf(x2+0.5)
	y1 = mf(y1+0.5)
	y2 = mf(y2+0.5)
	if x1>x2 then x1,x2 = x2,x1 end
	if y1>y2 then y1,y2 = y2,y1 end
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
	local i,c
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
	local i,j,h1,v1,h2,v2
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

function ILI9225:put(bitmap,x,y)
	local i
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

function ILI9225:put2(bitmap,x,y)
	local x2 = x+bitmap.width-1
	local y2 = y+bitmap.height-1
	local h1,v1,h2,v2 = self:bTrans(x,y,x2,y2)
	self:setWindow(h1,v1,h2,v2)
	self:writeRam(h1,v2,bitmap.data)
	self:resetWindow()
	collectgarbage()
end

function ILI9225:locate(x,y,mag,color,bgcolor,font)
	local bx	= bit32.extract

	self.x	= x or self.x
	self.x0 = x or self.x0
	self.y	= y or self.y
	self.mag= mag or self.mag
	if color then
		self.ch = bx(color,8,8)
		self.cl = bx(color,0,8)
	end
	if bgcolor then
		self.gh = bx(bgcolor,8,8)
		self.gl = bx(bgcolor,0,8)
	end
	if font then
		self.font = font
	end
end

function ILI9225:print(str)
	local i,j,k,l
	local n,c,b,bk,bj,il
	local h1,v1,h2,v2
	local s = ""
	local p = {}
	local fw = self.font.width
	local fh = self.font.height
	local gh = self.gh
	local gl = self.gl
	local ch = self.ch-gh
	local cl = self.cl-gl
	local mg = self.mag
	local bx = bit32.extract
	local mf = math.floor

	self:setRamMode(0,0,1)

	is = 1
	slen = #str
	while slen>0 do
		sn = mf((self.xMax+1-self.x)/mg/fw)
		il = sn<slen and sn or slen
		slen = slen - il
		h1,v1,h2,v2 = self:bTrans(self.x,self.y,self.xMax,self.y+mg*fh-1)
		self:setWindow(h1,v1,h2,v2)
		if self.id==0 then self:writeRamCmd(h1,v2) else	self:writeRamCmd(h2,v1) end

		local ph,pl
		bk=1
		for i=is,is+il-1 do
			c = str.sub(str,i,i)
			b = self.font[c]
			for j=1,fw do
				bj = b[j]
				for k=fh-1,0,-1 do n=bx(bj,k,1) ph,pl=n*ch+gh,n*cl+gl for l=1,mg do p[bk],p[bk+1],bk=ph,pl,bk+2 end end
				if bk>1200 or mg>1 then
				   	s = string.char(table.unpack(p))
					for l=1,mg do
					   	self:writeRamData(s)
					end
					bk=1
					p={}
					collectgarbage()
				end
			end
		end
		if bk>1 and il>0 then
			s = string.char(table.unpack(p))
			for l=1,mg do
				 self:writeRamData(s)
			end
			p={}
			collectgarbage()
		end
		self.x = self.x+mg*fw*il
		if slen>0 or self.x>self.xMax then
			self.x,self.y = self.x0,self.y+mg*fh
			is = is+il
		end
		collectgarbage()
	end
	self:resetWindow()
	self:setRamMode(0,0,0)
	p = nil
	collectgarbage()

	return self.x,self.y
end

function ILI9225:println(str)
	self:print(str)
	self.x,self.y = self.x0,self.y+self.mag*self.font.height

	return self.x,self.y
end
collectgarbage()
return ILI9225
