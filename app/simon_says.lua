-- Implementation of the Simon Says Game
-- Storm generates a pattern, then prompts the user to repeat
-- Who will run out of memory first!!?!?


require("storm") -- libraries for interfacing with the board and kernel
require("cord") -- scheduler / fiber library
shield = require("starter") -- interfaces for resources on starter shield

print ("Welcome to SimonSays")

shield.Button.start()      -- enable LEDs
shield.LED.start()

led_mapping = {"blue","green","red"}

function buzzer()
   shield.Buzz.go(1000)
end

function simonSays(sequence)
   local n = 0
   for _ in pairs(sequence) do n = n + 1 end

   print("Simon says!")
   for i, color in pairs(sequence) do
      storm.os.invokeLater(i * 1000 * storm.os.MILLISECOND, function()
         shield.LED.flash(color, 800)
      end)
      if n == i then 
         storm.os.invokeLater((i+1) * 1000 * storm.os.MILLISECOND, function()
            print("Your turn!")
            buzzer()
         end)
      end
   end
end


led_to_button = {red = "left", green = "center", blue="right"}
current_sequence = {"red", "green"}

function youSay(i)
   shield.Button.deregister()
   local n = 0
   for _ in pairs(current_sequence) do n = n + 1 end

   -- win case
   if i > n then 
      next_color = led_mapping[math.random(1, 3)]
      print("You survived another round", next_color) 
      table.insert(current_sequence, next_color)
      i = 1
      simonSays(current_sequence)
   end 

   local next_light = current_sequence[i]
   next(next_light, i)
end

function next(next_light, i)
   print("YES", next_light, i)
   button = led_to_button[next_light]
   shield.Button.deregister()

   -- configure win
   shield.Button.when(button, "FALLING", function()
      -- blink light
      shield.LED.on(next_light)
            storm.os.invokeLater(600 * storm.os.MILLISECOND, function()
            shield.LED.off(next_light)
         youSay(i + 1)
         end)
   end)
   -- configure error
   for l, b in pairs(led_to_button) do
      if(l ~= next_light) then
         shield.Button.when(b, "FALLING", function()
               buzzer()
               print("You lost :( when you pressed", b)
               shield.Button.deregister()
               youSay(1)
            end)
      end
   end
end

shield.Buzz.init()      -- enable buzzer
math.randomseed(storm.os.now(storm.os.SHIFT_0) )
simonSays(current_sequence)
youSay(1)

cord.enter_loop() -- start event/sleep loop



