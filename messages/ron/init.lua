-- ron protocol

local M = {}

local log = require 'lumen.log'
local sched = require 'lumen.sched'
local messaging = require 'rong.lib.messaging'

local queue_set = require "rong.lib.queue_set"
local seen_notifs = queue_set.new()

local view_merge = function(rong, vi)
  local now = sched.get_time()
  
  local view = rong.view
  local conf = rong.conf
    
  for sid, si in pairs(vi) do
    log('RON', 'DEBUG', 'Merging subscription: %s', tostring(sid))
    local sl = view[sid]
    if sl then
      local metasl = sl.meta
      assert(si.p, "Malformed view, missing p")
			if metasl.p<si.p and not view.own[sid] then
				local p_old=metasl.p
				metasl.p = p_old + ( 1 - p_old ) * si.p * conf.p_encounter
			end
    else
      view:add(sid, si.filter, false)
      sl = view[sid]
      sl.meta.p = si.p --TODO how to initialize p from incomming?
      sl.meta.init_time = si.init_time
      sl.meta.store_time = now
      sl.meta.last_seen = now
    end
    sl.meta.last_seen = now
  end
end

local notifs_merge = function (rong, notifs)
  local inv = rong.inv
  local conf = rong.conf
  local pending = rong.pending
  local ranking_find_replaceable = rong.ranking_find_replaceable
  
  local now=sched.get_time()
  
  --messages maintenance 
	for nid, n in pairs(inv) do
    local meta = n.meta
		if inv.own[nid] then
			if now - meta.init_time > conf.max_owning_time then
        log('RON', 'DEBUG', 'Purging old own notif: %s', tostring(nid))
				inv:del(nid)
			elseif meta.emited >= conf.max_ownnotif_transmits then
        log('RON', 'DEBUG', 'Purging own notif on transmit count: %s', tostring(nid))
				inv:del(nid)
			end
		else
			if meta.emited >= conf.max_notif_transmits then
        log('RON', 'DEBUG', 'Purging notif on transmit count: %s', tostring(nid))
				inv:del(nid)
			end
		end
	end

  for nid, inn in pairs(notifs) do
      local data, path = inn.data, {}
	  local ni=inv[nid]
		if ni then
      local meta = ni.meta
			meta.last_seen = now
			meta.seen=meta.seen+1
			pending:del(nid) --if we were to emit this, don't.
		else	
      if not seen_notifs:contains(nid) then
        seen_notifs:pushright(nid)
        while seen_notifs:len()>conf.max_notifid_tracked do
	        seen_notifs:popleft()
        end
        
        inv:add(nid, data, false)
        local n=rong.messages.init_notification(nid) --FIXME refactor?
        n.meta.init_time = inn.init_time
        n.meta.store_time = now
        
        -- signal arrival of new notification to subscriptions
        local matches=n.matches
        for sid, s in pairs(rong.view.own) do
          if matches[s] then
            log('RON', 'DEBUG', 'Signalling arrived notification: %s to %s'
              , tostring(nid), tostring(sid))
            sched.signal(s, n)
          end
        end
        
        --make sure table doesn't grow beyond inventory_size
        while inv:len()>conf.inventory_size do
          local mid=ranking_find_replaceable(rong)
          inv:del(mid or nid)
          log('RON', 'DEBUG', 'Inventory shrinking: %s (between %s and %s), now %i long', 
            tostring(mid or nid), tostring(mid) or 'none',tostring(nid) or 'none', inv:len())
          
          if mid == nil then
            --[[
            if inv:len()>conf.inventory_size then 
              local s = ''
              local comma = ''
              for iid, _ in pairs(inv) do
                s=s..comma..iid
                comma = ', '
              end
              log('RON', 'WARN', 'Could nor shrink inventory: %s',s )
            end
            --]]
            break
          end
          
        end
      end
		end
	end

end

local apply_aging = function (rong)
  local now = sched.get_time()
  
  local view = rong.view
  local conf = rong.conf
  
  for sid, s in pairs(view) do
    local meta = s.meta
    if not view.own[sid] then
      meta.p=meta.p * conf.gamma^(now-meta.last_seen)
      meta.last_seen=now
    end
    --delete if p_encounter too small
    if meta.p < (conf.min_p or 0) then
      log('RON', 'Purging subscription %s with p=%s',
        tostring(sid), tostring(meta.p_encounter))
      view:del(sid)
    end
  end
end

local process_incoming_view = function (rong, view)
  local now = sched.get_time()
  local conf = rong.conf
  
  --routing
  view_merge( rong, view.subs )
  
  -- forwarding
  local skipnotif = {}
  for _, nid in ipairs(view.skip or {}) do
    skipnotif[nid]= true
  end
  
  local matching = messaging.select_matching( rong, view.subs )
  local pending, inv = rong.pending, rong.inv
  for _, mid in ipairs(matching) do
    local m = inv[mid]
    if now-m.meta.last_seen>conf.message_inhibition_window and not skipnotif[mid] then
      m.meta.emited = m.meta.emited + 1 --FIXME do inside pending?
      pending:add(mid, {data=m.data, path=path, init_time=m.meta.init_time})
    end
  end
end

local process_incoming_notifs = function (rong, notifs)
  notifs_merge(rong, notifs)
end

M.new = function(rong)  
  local msg = {}
  local encode_f, decode_f = rong.conf.encode_f, rong.conf.decode_f
  
  local ranking_method = rong.conf.ranking_find_replaceable or 'find_replaceable_fifo'
  rong.ranking_find_replaceable = assert(require 'rong.messages.ron.ranking'[ranking_method])
  
  msg.broadcast_view = function ()
    apply_aging(rong)
    local subs = {}
    for sid, s in pairs (rong.view) do
      local meta = s.meta
      local sr = {
        filter = s.filter,
        p = meta.p,
        init_time = meta.init_time,
      }
      subs[sid] = sr
    end
    
    --[[
    for k,v in pairs (view_emit['SUB1@rongnode'] or {}) do
      print('>', type(k),k,type(v),v)
    end
    --]]
    local ms = assert(encode_f({view={subs=subs}})) --FIXME tamaño!
    
    local ms_candidate
    local skip = {}
    for mid, _ in pairs(rong.inv) do
      skip[#skip+1] = mid
      ms_candidate = assert(encode_f({view={subs=subs, skip=skip}})) 
      if #ms_candidate>1472 then break end
      ms = ms_candidate
    end
    
    --log('RON', 'DEBUG', 'Broadcast view %s (%i bytes)', ms, #ms)
    log('RON', 'DEBUG', 'Broadcast view (%i bytes)', #ms)
    rong.net:broadcast( ms )
  end
  
  msg.incomming = {
    view = process_incoming_view,
    notifs = process_incoming_notifs
  }
  
  msg.init_subscription = function (sid)
    local now = sched.get_time()
    local s = assert(rong.view[sid])
    local meta = s.meta
    meta.init_time = now
    meta.store_time=now
    meta.last_seen = now
    meta.p = 1.0
  end
    
  msg.init_notification = function (nid)
    local now = sched.get_time()
    local n = assert(rong.inv[nid])
    local meta = n.meta
    meta.init_time=now
    meta.store_time=now
    meta.last_seen=now
    meta.emited=0
    meta.seen=1
    return n
  end

  return msg
end

return M