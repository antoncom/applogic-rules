
local util = require "luci.util"
local log = require "applogic.util.log"
local uci = require "luci.model.uci".cursor()
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua

local loadvar_uci = {}

function loadvar_uci:load(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug".init(rule) end

	local setting = rule.setting
	local varlink = rule.setting[varname]
	local cache_key = ""
	local result = ""
	local noerror = true

	--[[ LOAD FROM UCI ]]
	local config = varlink.source.config
	local section = varlink.source.section
	local option = varlink.source.option or ""

	noerror = config and section

	if noerror then
		cache_key = config..section..option
		if not rule.cache_uci[cache_key] then
			if noerror then
				if option ~= "" then
					rule.cache_uci[cache_key] = uci:get(config, section, option)
				else
					local allsects = uci:get_all(config)
					log("ALL", allsects)
					--rule.cache_uci[cache_key] = uci:get_all(config, section)
				end
			end
		end
	end
	--result = noerror and rule.cache_uci[cache_key] or ""
	--debug(varname):source_uci((config or ""), (section or ""), (option or ""), rule.cache_uci[cache_key] or "", noerror)

	--return result
end

return loadvar_uci
