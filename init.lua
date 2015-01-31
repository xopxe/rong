local M = {}

local selector = require 'lumen.tasks.selector'
local sched = require 'lumen.sched'
local log = require 'lumen.log'

local encoder_lib = require 'lumen.lib.dkjson' --'lumen.lib.bencode'
local encode_f, decode_f = encoder_lib.encode, encoder_lib.decode


M.new = function(conf)  
  local ivs = assert(loadfile 'lib/inventory_view_sets.lua')()

  --M.conf = conf
  local rong = setmetatable({
    conf = conf,
    signals = loadfile 'lib/signals.lua'(),
    inv = ivs.inv,
    inv_meta = ivs.inv_meta,
    view = ivs.view,
    view_meta = ivs.view_meta,
  }, {
    __index = M,
  })
  local messages = assert(require ('messages.'..conf.protocol)).new(rong)
  rong.messages = messages
  
  local incomming_handler = function (data, err)
    if data then 
      log('RONG', 'DEBUG', 'Incomming data: %s', tostring(data))
      local m = decode_f(data)
      for k, v in pairs(m) do
        if messages.incomming[k] then 
          log('RONG', 'DEBUG', ' Incomming found: %s', tostring(k))
          messages.incomming[k] (rong, v)
        else
          log('RONG', 'DEBUG', ' Incomming unknown: %s', tostring(k))
        end
      end
      --[[
      if m.view then
        process_incoming_view(rong, m)
      elseif m.messages then
      elseif m.subscribe then
      elseif m.subrequest then
      end
      --]]
    else
      log('RONG', 'DEBUG', 'Incomming error: %s', tostring(err))
    end
    return true
  end
  rong.net = require 'lib.networking'.new(rong, incomming_handler)
  rong.pending = require 'lib.pending'.new(rong)
    
 
  -- start tasks
  --rong.broadcast_listener_task = sched.sigrun(
  --  { rong.signals.broadcast_view }, 
  --  function() messages:broadcast_view() end
  --)
  
  rong.broadcast_view_task = sched.run( 
    function ()
      while true do
        --sched.signal( rong.signals.broadcast_view )
        messages:broadcast_view()
        sched.sleep( conf.send_views_timeout )
      end
    end
  )

  M.subscribe = function (rong, sid, filter)
    sid = sid or 'sid:'..math.random(2^31)
    --subscriptions:add(sid,{subscription_id=sid, filter=s.filter, p_encounter=p_encounter, 
    --last_seen=t, ts=t, cached_template=parser.build_subscription_template(s),own=skt})
    log('RONG', 'INFO', 'Publishing subscription: "%s"',
      tostring(sid))
    rong.view:add(sid, filter, true)
    messages.init_subscription(sid)
    log('RONG', 'INFO', '  subscriptions: %i', rong.view:len())
    return rong.view[sid]
  end
  
  M.notificate = function (rong, nid, n)
    nid = nid or 'nid:'..math.random(2^31)
    log('RONG', 'INFO', 'Publishing notification: "%s"',
      tostring(nid))
    rong.inv:add(nid, n, true)
    messages.init_notification(nid)
    log('RONG', 'INFO', '  notifications: %i', rong.inv:len())
  end

 
  log('RONG', 'INFO', 'Library instance initialized: %s', tostring(rong))
  return rong
end

return M