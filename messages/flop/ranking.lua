local M = {}

local sched = require("lumen.sched")

local function not_on_path(rong)
  local inv = rong.inv
  local own = inv.own
  local nop = {}
	for mid, m in pairs(inv) do
		if not own[m] then
      local meta = m.meta
			if not meta.path[meta.conf.name] then
        nop[mid] = true
			end
		end
	end
	return nop
end

function M.find_fifo_not_on_path (rong)
  local inv = rong.inv
  local conf = rong.conf

	if inv.own:len() < conf.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns
    
		local nop = not_on_path(rong)
		--conf.log('looking for a replacement', #worsts, worst_q)
    
		--between the worst, find the oldest
		local min_ts, min_ts_mid
		for mid, m in ipairs(nop) do
      local meta = m.meta
			local em=meta.init_time - meta.message._in_transit --estimated emission time
			if not inv.own[m]
			and (not min_ts_mid or min_ts > em) 
			and m.emited > conf.min_n_broadcasts then
				min_ts_mid, min_ts = mid, em
			end
		end
    
		return min_ts_mid
	else --messages.own:len() >= conf.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(inv.own) do
			if not min_ts_mid or min_ts > m.init_time then
				min_ts_mid, min_ts = mid, m.init_time
			end
		end
    
		return min_ts_mid
	end
end

return M