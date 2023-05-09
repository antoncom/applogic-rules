require "os"
require "ubus"
local sys  = require "luci.sys"
local uloop = require "uloop"
local util = require "luci.util"
local log = require "applogic.util.log"
local flist = require "applogic.util.filelist"
local uci = require "luci.model.uci".cursor()
local bit = require "bit"
local checkubus = require "applogic.util.checkubus"
local debug_mode = require "applogic.debug_mode"


--local F = require "posix.fcntl"
--local U = require "posix.unistd"


local rules = {}
rules.ubus_object = {}
rules.conn = nil
rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
rules.state = 	{
					mode = "run",	-- "run", "stop" are only possible
				}					-- "stop" is needed when web-console of AT commands is activated
									-- "stop" stops ubus-requests from applogic to tsmodem.driver,
									-- as tsmodem.driver automation is in "stop" mode too.


local rules_setting = {
	title = "Группа правил CPE Agent",
	rules_list = {
		target = {},
	},
	tick_size_default = 1900
}

function rules:init()
	rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
end

function rules:clear_cache()
	rules.cache_ubus, rules.cache_uci, rules.cache_bash = nil, nil, nil
	rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
end

function rules:make_ubus()
	self.conn = ubus.connect()
	if not self.conn then
		error("rules:make_ubus() - Failed to connect to ubus")
	end

	--[[ Get name of Ubus object from /etc/config/applogic ]]
	local ubus_name = uci:get("applogic", "ubus", "object") or "applogic"

	local ubus_object = {
		[ubus_name] = {
			list = {
				function(req, msg)
					local rlist = {}
					for rule_file, rule_obj in util.kspairs(self.setting.rules_list.target) do
						rlist[rule_file] = rule_obj.setting.title.output
					end
					self.conn:reply(req, { rule_list = rlist })
				end, {id = ubus.INT32, msg = ubus.STRING }
			},

			vars = {
				function(req, msg)
					local vlist = {}
					local rules = self.setting.rules_list.target
					local rule_name = msg["rule"]
					if not rule_name then
						self.conn:reply(req, { ["error"] = "Rule name was not found. Try 'list' to see all names."})
						return
					end

					if rules[rule_name] and rules[rule_name].setting then
						for varname, varparams in pairs(rules[rule_name].setting) do
							if varname ~= "title" then -- Hide title variable in UBUS response
								vlist[varname] = (type(varparams["output"]) == "table") and util.serialize_json(varparams["output"]) or varparams["output"]
							end
						end
					else
						self.conn:reply(req, { ["error"] = string.format("Rule '%s' was not found.", tostring(rule_name)) })
					end

					self.conn:reply(req, vlist)

				end, {id = ubus.INT32, msg = ubus.STRING }
			},

			state = {
	            function(req, msg)
	                if msg["mode"] and msg["mode"] == "run" then
						rules.state = { mode = "run" }
						resp = rules.state
	                elseif msg["mode"] and msg["mode"] == "stop" then
	                    rules.state = {
							mode = "stop",
							run_after = 30,
							comment = [[
								After 30 sec. Applogic will check if http session is active.
								If the http session is expired or user logged off from UI,
								then Applogic go back to 'run' mode automatically.
							]]
						}
						rules.state.comment = rules.state.comment:gsub("\t", "")
						rules.state.comment = rules.state.comment:gsub("\n", " ")
						resp = rules.state
					else
						resp = rules.state
	                end

	                self.conn:reply(req, resp);
	            end, {id = ubus.INT32, msg = ubus.STRING }
	        },
		},
	}
	self.conn:add( ubus_object )
	self.ubus_object = ubus_object

end

function rules:make()
	local rules_path = "/usr/lib/lua/applogic/rule"
	local id, rules = '', self.setting.rules_list.target

	local files = flist({path = rules_path, grep = ".lua"})
	for i=1, #files do
		id = util.split(files[i], '.lua')[1]
		rules[id] = require("applogic.rule." .. id)
	end

	--util.dumptable(rules)
end


function rules:check_driver_automation()
	local driver_mode = ""
	local automation = { mode = "" }
	if checkubus(rules.conn, "tsmodem.driver", "automation") then
		automation = util.ubus("tsmodem.driver", "automation", {})
		driver_mode = automation and automation["mode"] or ""
	end
	return driver_mode
end


function rules:run_all()
	local user_session_alive = rules:check_driver_automation()
	if (rules:check_driver_automation() == "run") then
		local rules_list = self.setting.rules_list.target
		local state = ''

		for name, rule in util.kspairs(rules_list) do
			-- rule.debug = (rules.debug_type and (rules.debug_type == "VAR" or rules.debug_type == "RULE") or false
			-- rule.debug_var = (rules.debug_type and rules.debug_type == "VAR") or false
			-- rule.debug_rule = (rules.debug_type and rules.debug_type == "RULE") or false
			-- rule.iteration = self.iteration
			-- Initiate rule with link to the present (parent) module
			-- Then the rule can send notification on the ubus object of parent module

			state = rule(self)

			-- DEBUG: Print all vars table
			if rule.debug_mode.enabled then
				local rule_has_error = rule.debug_mode.type == "RULE" and rule.debug_mode.level == "ERROR" and rule.debug.noerror == false
				local report_anyway_mode = rule.debug_mode.type == "RULE" and rule.debug_mode.level == "INFO"
				if rule_has_error or report_anyway_mode then
					rule.debug.report(rule):print_rule(rule.debug_mode.level, rule.iteration)
					rule.debug.report(rule):clear()
				end

				rule.debug.noerror = true
			end
		end
		rules:clear_cache()

	end
end

local metatable = {
	__call = function(table)
		table.setting = rules_setting
		local tick = table.setting.tick_size_default

		table:make_ubus()
		table:make()

		-- looping
		uloop.init()

		local timer
		function t()
			table:run_all()
			timer:set(tick)
		end
		timer = uloop.timer(t)
		timer:set(tick)

		uloop.run()

		table.conn:close()
		return table
	end
}
setmetatable(rules, metatable)
rules()
