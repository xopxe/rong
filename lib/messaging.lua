local M = {}

local log = require 'lumen.log'
local sched = require 'lumen.sched'

--selects messages to be sent out in response to views received
--parameters should be set of subscription ids.
M.select_matching = function (rong, vs)
  local inv = rong.inv
  local inv_meta = rong.inv_meta
  local view = rong.view
  local view_meta = rong.view_meta
  local conf = rong.conf
  local pending = rong.pending

  local ret = {}

	local now=sched.get_time()
	for mid, m in pairs(inv) do
		local matches=inv_meta[m].matches
		for sid, _ in pairs(vs) do
			local s=view[sid]
			if s and matches[s] then
				view_meta[s].last_success=now
				local own=view_meta[s].own
        if now-inv_meta[m].last_seen > conf.delay_message_emit then
          print ('!!!!+', mid, m)
          pending:add(mid, m)
				end
			end
		end
	end
end

--whether a given message satisfies a filter
M.satisfies = function (m, filter)
	local is_match=true
  for i=1, #filter do
    local expr = filter[i]
		local ev_value, filt_op, filt_value = m[expr[1]], expr[2], expr[3]
    if ev_value == nil
    or (filt_op == '=' and (ev_value~=filt_value))
    or (filt_op == '!=' and (ev_value==filt_value))
    or (filt_op == '>' and (ev_value<=filt_value))
    or (filt_op == '<' and (ev_value>=filt_value)) then
      is_match=false
      break
    end
	end
	return is_match
end


return M
