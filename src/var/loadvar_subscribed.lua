
local util = require "luci.util"
local log = require "applogic.util.log"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"
local cjson = require "cjson"


local loadvar_subscribed = {}

function evuuid(name, match)
	return md5.sumhexa(name..util.serialize_json(match))
end

function loadvar_subscribed:load(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

	local varlink = rule.setting[varname]
	local subscription = rule.parent.subscription

	local result = {}
	local noerror = true
	local err = ""

	local ubusobj = string.format("%s", (varlink.source.ubus or ""))
	local evname = string.format("%s", (varlink.source.evname or ""))
	local evmatch = varlink.source.match or {}

	noerror, err = checkubus(rule.conn, ubusobj)
	if noerror then
		-- загружаем первое значение из очереди
		local evmatch_md5 = evuuid(evname, evmatch)
		if (subscription.queu[ubusobj] and subscription.queu[ubusobj][evmatch_md5]) then
			if (#subscription.queu[ubusobj][evmatch_md5].events > 0) then
				varlink.subtotal = util.serialize_json(subscription.queu[ubusobj][evmatch_md5].events[1].msg)
				-- удаляем переменную из спика vars_to_load
				subscription.removeEvent(ubusobj, evmatch_md5, varlink)
			else
				varlink.subtotal = ""
			end
		end
	end

	
	if rule.debug_mode.enabled then
		if (noerror) then
			debug(varname, rule):source_subscribe(ubusobj, evname, varlink.subtotal, noerror, varlink.source)
		else
			debug(varname, rule):source_subscribe(ubusobj, evname, err, noerror, varlink.source)
		end
	end
end

return loadvar_subscribed
