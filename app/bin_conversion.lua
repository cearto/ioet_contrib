-- displays decimal and binary representations of whole numbers in range [0,8]

require("storm")
require("cord")

local shield = require("starter") -- interfaces for resources on starter shield

local display = shield.Display
local n = 0
local led_list = {storm.io.D2, storm.io.D3, storm.io.D4, storm.io.D5}

for i=1,3 do
   storm.io.set_mode(storm.io.OUTPUT, led_list[i])
end

display.init()

function display_bin(n)
   --display the binary representation of n with the LEDs
   local i = 0;
   while n > 0 do
      storm.io.set(n % 2, led_list[i])
      n = n / 2
   end
   local len = #led_list
   while i < len do
      storm.io.set(0, led_list[i])
   end
end

n = 5

--TODO: change 'n' in response to button press or time
display:num(n)
display_bin(n)

cord.enter_loop() -- start event/sleep loop
