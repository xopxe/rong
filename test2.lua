--require "strict"
--look for packages one folder up.
package.path = package.path .. ";;;../?.lua;../?/init.lua"

local sched = require 'lumen.sched'
local log = require 'lumen.log'
--log.setlevel('ALL', 'RONG')
--log.setlevel('ALL', 'RON')
log.setlevel('ALL', 'RWALK')
local selector = require "lumen.tasks.selector"
selector.init({service='luasocket'})

local conf = {
  name = 'rongnode2', --must be unique
  protocol_port = 8888,
  listen_on_ip = '164.73.36.65', 
  broadcast_to_ip = '127.0.0.1', --adress used when broadcasting
  udp_opts = {
    broadcast	= 0,
    dontroute	= 0,
  },
  send_views_timeout =  6, --5
  
  protocol = 'rwalk',
  
  ---[[
  transfer_port = 8889,
  --]]
  
  --[[
  gamma = 0.99,
  P_encounter = 0.1,
  inventory_size	= 10,	--max number of messages carried
  reserved_owns	= 5,--guaranteed number of slots for own messages in inventory
  delay_message_emit = 1,
  max_owning_time = 60*60*24,	--max time own messages are kept
  max_notif_transmits = math.huge, --max number of transmissions for each notification
  max_ownnotif_transmits = math.huge, --max number of transmissions for each own notification,
  min_n_broadcasts = 0, --see find_replaceable_fifo in ranking.lua
  --]]
}


local rong = require 'rong'.new(conf)
local s = rong:subscribe(
  'SUB1@'..conf.name, 
  {
    {'q', '=', 'X'},
  }
)
sched.sigrun({s}, function(s, n) 
  print ('ARRIVED FOR', s.id, ':', n.id)
  for k, v in pairs (n.data) do
    print ('  >', k, '=', v) 
  end
end)

--[[
local udp_out = assert(selector.new_udp(nil, nil, conf.listen_on_ip))
for k, v in pairs(conf.udp_opts) do
  if udp_out.fd.setoption then
    assert(udp_out.fd:setoption(k,(v==true or v==1)))
  elseif udp_out.fd.setopt then
    assert(udp_out.fd:setopt('socket', k, v))
  else
    error()
  end  
end

if udp_out.fd.setpeername then
  assert(udp_out.fd:setpeername(
      '127.0.0.1',
      conf.protocol_port))
elseif udp_out.fd.connect then
  assert(udp_out.fd:connect(
      '127.0.0.1',
      conf.protocol_port))
else
  error()
end
--]]

--[[
sched.run(function()
  for i = 1, 10 do
    sched.sleep(5)
    --local s='{"view":{"sub1@test":{"1":["q","=","X"],"p":0.5,"visited":[],"seq":' .. i .. '}}}'
    local s='{"view":{"sub1@test":{"filter":[ ["q","=","X"] ],"p":0.5}}}'
    print('OUT',s)
    udp_out:send(s)
    sched.sleep(5)
  end
end)
--]]  

sched.loop()