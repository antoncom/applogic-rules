local util = require "luci.util"
local log = require "applogic.util.log"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"
local substitute = require "applogic.util.substitute"
local find_leaf_in_table = require "applogic.util.find_leaf_in_table"



local loadvar_uci = {}

function loadvar_uci:load(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

	local setting = rule.setting
	local varlink = rule.setting[varname]
	local cache_key = ""
	local result
	local noerror = true

	--[[ LOAD FROM UCI USING UBUS REQUEST ]]
	local config = varlink.source.config
	local section = varlink.source.section
	local option = varlink.source.option or ""
	--local filter = (varlink.source.filter and varlink.source.filter:split(".")) or {}


	-- Substitute names of config, section, option if variables were used as its' values
	config = substitute(varname, rule, config, false, false)
	section = substitute(varname, rule, section, false, false)
	option = substitute(varname, rule, option, false, false)

	--[[ PREPARE UBUS REQUEST ]]
	local obj = "uci"
	local method = "get"
	local params = {
		["config"] = config,
		["section"] = section,
		["option"] = option
	}

	-- Substitute params values from matched variables
	for par_name, par_value in util.vspairs(params) do
		params[par_name] = substitute(varname, rule, par_value, false)
	end

	cache_key = md5.sumhexa(varname..obj..method..util.serialize_json(params))
	if not rule.cache_uci[cache_key] then
		-- Cache result only if ubus object/method is valid
		noerror, err = checkubus(rule.conn, obj, method)
		if noerror then
			local ubus_result = rule.conn:call(obj, method, params)
			rule.cache_uci[cache_key] = ubus_result and ubus_result.value or ""
		end
	end

	result = rule.cache_uci[cache_key] or ""
	if rule.debug_mode.enabled then
		if (noerror) then
			debug(varname, rule):source_uci(config, section, option, result, noerror, varlink.source)
		else
			debug(varname, rule):source_uci(config, section, option, err, noerror, varlink.source)
		end
	end

	return rule.cache_uci[cache_key] or ""
end
return loadvar_uci
