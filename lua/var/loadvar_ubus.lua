
local util = require "luci.util"
local log = require "applogic.util.log"
local uci = require "luci.model.uci".cursor()
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local nixio = require "nixio"
local checkubus = require "applogic.util.checkubus"

local loadvar_ubus = {}

function loadvar_ubus:load(varname, rule)
	local debug = require "applogic.var.debug".init(rule)
	local setting = rule.setting
	local varlink = rule.setting[varname]
	local cache_key = ""
	local result = ""
	local noerror = true

	--[[ LOAD FROM UBUS ]]
	local obj = varlink.source.object or ""
	local method = varlink.source.method or ""
	local params = varlink.source.params or {}

	cache_key = md5.sumhexa(varname..obj..method..util.serialize_json(params))
	if not rule.cache_ubus[cache_key] then
		-- Cache result only if ubus object/method is valid
		noerror = checkubus(rule.conn, obj, method)
		if noerror then
			local variable = rule.conn:call(obj, method, params)
			rule.cache_ubus[cache_key] = variable or ""
		end
	end
	result = rule.cache_ubus[cache_key] or ""
	debug(varname):source_ubus(obj, method, params, result, noerror, varlink.source)

	varlink.subtotal = util.serialize_json(rule.cache_ubus[cache_key]) or ""
end

return loadvar_ubus
