local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило открывания/закрывания шторки 'Переключение Сим' в веб-интерфейсе",
	},

	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "sim",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]]
		}
	},


	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	event_datetime = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_lua-func"] = function (vars)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(vars.event_datetime)))
			end,
		}
	},

	r01_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "do_switch",
		},
	},

	r02_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "02_rule",
			varname = "do_switch",
		},
	},

	r03_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "03_rule",
			varname = "do_switch",
		},
	},

	r04_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "04_rule",
			varname = "do_switch",
		},
	},

	r05_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "05_rule",
			varname = "do_switch",
		},
	},

	r15_do_switch = {
		note = [[ r15_do_switch  ]],
		source = {
			type = "rule",
			rulename = "15_rule",
			varname = "do_switch",
		},
	},

	do_switch = {
		note = [[ Статус do_switch  ]],
		modifier = {
			["1_lua-func"] = function (vars)
				local DO_SWITCH = (vars.r01_do_switch == "true"
								or vars.r02_do_switch == "true"
								or vars.r03_do_switch == "true"
								or vars.r04_do_switch == "true"
								or vars.r05_do_switch == "true"
								or vars.r15_do_switch == "true")
				if DO_SWITCH then return "true" else return "false" end
			end,
			["2_frozen"] = [[ if $do_switch == "true" then return 10 else return 0 end ]]

		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"switching",
                    "sim_id",
--					"do_switch"
				}
			},
		}
	},
	journal = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_skip-func"] = function (vars)
				if (vars.switching ~= "true") then return true else return false end 
			end,
			["2_lua-func"] = function (vars)
				local jsonc = require "luci.jsonc"
				local switching_data = string.sub(vars.journal,2,-2)

				switching_data, errmsg = jsonc.parse(switching_data)
				local info_source = switching_data.comment or ""
				local info_command = switching_data.command or ""
				return({ 
					datetime = vars.event_datetime,
					name = "Переключение СИМ-карты",
					source = info_source,
					command = info_command,
					response = "OK"
				})
			end,
			["3_store-db"] = {
				param_list = { "journal" }	
			},
			["4_frozen"] = [[ return 10 ]]
		}
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 01_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	local overview = {
		["sim_id"] = { ["red"] = [[ return($sim_id ~= "0" and $sim_id ~= "1") ]] },
		["switching"] = { ["yellow"] = [[ return($switching ~= "false") ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug(overview)
	self:load("switching"):modify():debug()
	self:load("event_datetime"):modify():debug()
	-- self:load("r01_do_switch"):modify():debug()
	-- self:load("r02_do_switch"):modify():debug()
	-- self:load("r03_do_switch"):modify():debug()
	-- self:load("r04_do_switch"):modify():debug()
	-- self:load("r05_do_switch"):modify():debug()
	-- self:load("r15_do_switch"):modify():debug()
	self:load("do_switch"):modify():debug()
	self:load("send_ui"):modify():debug()
	self:load("journal"):modify():debug()
end

---[[ Initializing. Don't edit the code below ]]---
local metatable = {
	__call = function(table, parent)
		local t = rule_init(table, rule_setting, parent)
		if not t.is_busy then
			t.is_busy = true
			t:make()
			t.is_busy = false
		end
		return t
	end
}
setmetatable(rule, metatable)
return rule
