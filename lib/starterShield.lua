----------------------------------------------
-- Starter Shield Module
--
-- Provides a module for each resource on the starter shield
-- in a cord-based concurrency model
-- and mapping to lower level abstraction provided
-- by storm.io @ toolchains/storm_elua/src/platform/storm/libstorm.c
----------------------------------------------

require("storm") -- libraries for interfacing with the board and kernel
require("cord") -- scheduler / fiber library
----------------------------------------------
-- Shield module for starter shield
----------------------------------------------
local shield = {}

----------------------------------------------
-- LED module
-- provide basic LED functions
----------------------------------------------
local LED = {}

LED.pins = {["blue"]="D2",["green"]="D3",["red"]="D4",["red2"]="D5"}

LED.start = function()
-- configure LED pins for output
   storm.io.set_mode(storm.io.OUTPUT, storm.io.D2,
           storm.io.D3,
           storm.io.D4,
           storm.io.D5)
end

LED.stop = function()
-- configure pins to a low power state
end

-- LED color functions
-- These should rarely be used as an active LED burns a lot of power
LED.on = function(color)
   local pin = LED.pins[color] or LED.pins["red2"]
   storm.io.set(1, storm.io[pin])
end
LED.off = function(color)
   local pin = LED.pins[color] or LED.pins["red2"]
   storm.io.set(0, storm.io[pin])
end

-- Flash an LED pin for a period of time
--    unspecified duration is default of 10 ms
--    this is dull for green, but bright for read and blue
--    assumes cord.enter_loop() is in effect to schedule filaments
LED.flash = function(color, duration)
   local pin = LED.pins[color] or LED.pins["red2"]
   duration = duration or 10
   LED.on(color)
   storm.os.invokeLater(duration * storm.os.MILLISECOND, function()
      LED.off(color)
   end)
   -- ASYNC SOLUTION
   -- cord.new( function()
    --  cord.await(storm.os.invokeLater, duration * storm.os.MILLISECOND)
   --      -- LED.off(color)
   --    end)   
end


----------------------------------------------
-- Buzz module
-- provide basic buzzer functions
----------------------------------------------
local Buzz = {}
Buzz.init = function()
   storm.io.set_mode(storm.io.OUTPUT, storm.io.D6)
end

Buzz.go = function(delay)
   handle = cord.new(function()
      storm.io.set(1, storm.io.D6)
      cord.await(storm.os.invokeLater, delay * storm.os.MILLISECOND)
      storm.io.set(0, storm.io.D6)
      end
   )
end

Buzz.stop = function()
   storm.io.set(0, storm.io.D6)
end

----------------------------------------------
-- Button module
-- provide basic button functions
----------------------------------------------
local Button = {}

local button_map = { right = "D9",
            center = "D10",
            left = "D11"
         }

-- sets all the pins to be in the correct modes

Button.start = function() 
   for k, pin in pairs(button_map) do
     storm.io.set_mode(storm.io.INPUT, storm.io[pin])
     storm.io.set_pull(storm.io.PULL_UP, storm.io[pin])
   end
end

-- Get the current state of the button
-- can be used when poling buttons
-- returns true if the button is pressed

Button.pressed = function(button) 
   return storm.io.get(storm.io[button_map[button]]) == 0 
end

-------------------
-- Button events
-- each registers a call back on a particular transition of a button
-- valid transitions are:
--   FALLING - when a button is pressed
--   RISING - when it is released
--   CHANGE - either case
-- Only one transition can be in effect for a button
-- must be used with cord.enter_loop
-- none of these are debounced.
-------------------

Button.transitions = {
   falling = storm.io.FALLING,
   rising  = storm.io.RISING,
   change  = storm.io.CHANGE
}

-- case-insensitive transition validator
local valid_transition = function(transition)
   if not Button.transitions[string.lower(transition)] then
      error("invalid transition")
   end
   return true
end

-- runs the action function whenever the given transition occurs on that pin
Button.whenever = function(button, transition, action)
   if not valid_transition(transition) then return end

   behavior = Button.transitions[string.lower(transition)]
   storm.io.watch_all(behavior, storm.io[button_map[button]], action)
end

local button_handles = {
   left = nil,
   center = nil,
   right = nil
}

Button.deregister = function()
   for button, handle in pairs(button_handles) do
      if(handle) then 
         storm.io.cancel_watch(handle)
         button_handles[button] = nil 
      end
   end
end

-- like whenever() but only run it once, then deregister
Button.when = function(button, transition, action)
   if not valid_transition(transition) then return end

   local behavior = Button.transitions[string.lower(transition)]
   local resolved_button = storm.io[button_map[button]]
   
   local update_handles_and_act = function()
      action()
      button_handles[button] = nil
   end
   button_handles[button] = storm.io.watch_single(behavior, resolved_button, update_handles_and_act);
end

-- if called in a cord, wait until the button is pressed
Button.wait = function(button)
   return cord.new(function()
      cord.await(storm.io.watch_single, storm.io.FALLING, storm.io[button_map[button]])
   end)
end
--------------------------------------------------------------------------------
-- Display module
-- provides access to the 7-segment display
--------------------------------------------------------------------------------
require("bit")

-- ported from: https://github.com/Seeed-Studio/Starter_Shield/blob/master/libraries/TickTockShieldV2/TTSDisplay.cpp

local Display = {}

-- TODO: these pins probably need to be changed for the firestorm board
-- default pin values
local PINCLK = storm.io.D7 -- pin of clk
local PINDTA = storm.io.D8 -- pin of data

-- definitions for TM1636
local ADDR_AUTO  = 0x40
local ADDR_FIXED = 0x44
local STARTADDR  = 0xc0

-- definitions for brightness
local BRIGHT_DARKEST = 0
local BRIGHT_TYPICAL = 2
local BRIGHTEST      = 7

--Special characters index of tube table
local INDEX_NEGATIVE_SIGH = 16
local INDEX_BLANK         = 17

--  0~9,A,b,C,d,E,F,"-"," "
TubeTab = {
   0x3f,0x06,0x5b,0x4f,
   0x66,0x6d,0x7d,0x07,
   0x7f,0x6f,0x77,0x7c,
   0x39,0x5e,0x79,0x71,
   0x40,0x00
}

local setpin = storm.io.set
local pinmode = storm.io.set_mode
local INPUT = storm.io.INPUT
local OUTPUT = storm.io.OUTPUT

function Display.init(pinclk, pindata)
   Display.dtaDisplay = {0,0,0,0}
   Display.Clkpin = pinclk or PINCLK
   Display.Datapin = pindata or PINDTA
   storm.io.set_mode(OUTPUT, Display.Clkpin)
   storm.io.set_mode(OUTPUT, Display.Datapin)

   Display:set()
   --clear()
end

-- displays a num in certain location
-- parameter loca - location: 3-2-1-0
function Display.display(self, loca, dta)

   if loca > 3 or loca < 0 then
      return
   end

   self.dtaDisplay[loca] = dta
   loca = 3 - loca
   local segData = coding(dta)
   self:start()          --start signal sent to TM1637 from MCU
   self:writeByte(ADDR_FIXED)
   self:stop()

   self:start()
   self:writeByte(bit.bor(loca, 0xc0))
   self:writeByte(segData)
   self:stop()

   self:start()
   self:writeByte(Cmd_Dispdisplay)
   self:stop()
end

--  display a number in range 0 - 9999
function Display.num(self, dta)

   if dta < 0 or dta > 9999 then
      return
   end

   --clear()
   self:pointOff()
   if dta < 10 then
      self:display(0, dta)
      self:display(1, 0x7f)
      self:display(2, 0x7f)
      self:display(3, 0x7f)
   elseif dta < 100 then
      self:display(1, dta / 10)
      self:display(0, dta % 10)
      self:display(2, 0x7f)
      self:display(3, 0x7f)
   elseif dta < 1000 then
      self:display(2, dta / 100)
      self:display(1, (dta / 10) % 10)
      self:display(0, dta % 10)
      self:display(3, 0x7f)
   else
      self:display(3, dta / 1000)
      self:display(2, (dta / 100) % 10)
      self:display(1, (dta / 10) % 10)
      self:display(0, dta % 10)
   end
end

function Display.time(self, hour, min)
   if hour > 24 or hour < 0 then
      return
   end
   if min > 60 or min < 0  then
      return
   end
   self:display(3, hour / 10)
   self:display(2, hour % 10)
   self:display(1, min / 10)
   self:display(0, min % 10)
end

function Display.clear(self)
   self:display(0x00, 0x7f)
   self:display(0x01, 0x7f)
   self:display(0x02, 0x7f)
   self:display(0x03, 0x7f)
end


--  write a byte to tm1636
function Display.writeByte(self, wr_data)
   local i, count1
   local dpin = self.Datapin
   local cpin = self.Clkpin

   for i=0,7 do     -- sent 8bit data
      setpin(LOW, cpin)
      if bit.band(wr_data, 0x01) then
         setpin(HIGH, dpin)  -- LSB first
      else
         setpin(LOW, dpin)
      end
      wr_data = bit.rshift(wr_data, 1)
      setpin(HIGH, cpin)
   end

   -- wait for the ACK
   setpin(LOW, cpin)
   setpin(HIGH, dpin)
   setpin(HIGH, cpin)
   pinmode(INPUT, dpin)

   while digitalRead(dpin) do
      count1 = count + 1
      if count1 == 200 then
         pinmode(OUTPUT, dpin)
         setpin(LOW, dpin)
         count1 = 0
      end
      pinmode(INPUT, dpin)
   end
   pinmode(OUTPUT, dpin)
end

--  send start signal to Display
function Display.start(self)
   setpin(HIGH, self.Clkpin)  --send start signal to TM1637
   setpin(HIGH, self.Datapin)
   setpin(LOW, self.Datapin)
   setpin(LOW, self.Clkpin)
end

 -- sends end signal
function Display.stop(self)
   setpin(LOW, self.Clkpin)
   setpin(LOW, self.Datapin)
   setpin(HIGH, self.Clkpin)
   setpin(HIGH, self.Datapin)
end

function Display.set(self, brightness, SetData, SetAddr)
   brightness = brightness or BRIGHT_TYPICAL
   self._brightness = brightness
   self.Cmd_SetData = SetData or 0x40
   self.Cmd_SetAddr = SetAddr or 0xc0
   self.Cmd_Dispdisplay = 0x88 + brightness
end

function Display.pointOn()
   local _PointFlag = 1
   local dtaDisplay = self.dtaDisplay
   for i=1,4 do
      self:display(i, dtaDisplay[i])
   end
end

function Display.pointOff()
   local _PointFlag = 0
   local dtaDisplay = self.dtaDisplay
   for i=1,4 do
      self:display(i, dtaDisplay[i])
   end
end

function coding(DispData)
   local PointData
   if _PointFlag then
      PointData = 0x80
   else
      PointData = 0x00
   end
   if 0x7f == DispData then
      DispData = PointData
   else
      DispData = TubeTab[DispData] + PointData
   end
   return DispData
end

----------------------------------------------
shield.LED = LED
shield.Buzz = Buzz
shield.Button = Button
shield.Display = Display
return shield


