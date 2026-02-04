
local util = require "luci.util"


local subs = {}
subs.conn = nil

subs.ubus_subscribers = {
-- Храним линки на узлы, которые подписаны на указанные объекты шины UBUS
-- для того, чтобы при вознкновении события, брокер мог вызвать методы узла enqueue() 
--	["tsmstm"] = { nodelink1, nodelink2 },
--	["tsmodem"] = { nodelink2, nodelink4 },
--	["network.interface"] = { nodelink1 },
}

function subs:init(conn)
	subs.conn = conn
	return subs.ubus_subscribers
end

-- Если поступило новое обытие, то
-- вызываем метод enqueue() у всех тех узлов, которые подписаны на данный объект шины UBUS
function subs:broker(ubname, evname, evmsg)
	for key, nodes in util.kspairs(subs.ubus_subscribers) do
		if(key == ubname) then
			for _, node in ipairs(nodes) do
				node:enqueue(evname,evmsg)
			end
		end
	end
end

-- Подписываем узлы на события
function subs:make_subscription(rule)
	for nodename, nodelink in pairs(rule.setting) do
		for _, operator in ipairs(nodelink) do
			if(operator["subscribe"]) then

				local ubus_objname = operator["subscribe"]["ubus"]
				if not subs.ubus_subscribers[ubus_objname] then
					subs.ubus_subscribers[ubus_objname] = {}
				end
				table.insert(subs.ubus_subscribers[ubus_objname], rule.setting[nodename])
				break -- as only one [subscribe] operator is possible in one node
			end
		end
	end

	function do_subscribe(ubname, s)
		subs.conn:subscribe(ubname, s)
		return 0
	end

	-- Подписываемся на UBUS
	for ubusname,_ in util.kspairs(subs.ubus_subscribers) do
	    local callback = {
			notify = function(msg,name)
				subs:broker(ubusname, name, msg)
			end
		}
    	local success, err = pcall(do_subscribe, ubusname, callback)
    	if not success then
    		print("SKIP subscribing on [" .. ubusname .. "] as it's absent on the UBUS: " .. err)
    	end
	end
end

return subs

