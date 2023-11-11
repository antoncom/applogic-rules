local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения если нет Cим-карты в слоте",
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

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		--input = "true",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "cpin",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[ if $sim_ready == "" then return "*" else return tostring($sim_ready) end ]],
		}
	},

	sim_comment = {
		note = [[ Статус сим-карты (SIM READY, SIM not inserted, etc.) ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "cpin",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.comment ]],
		}
	},


	timeout = {
		note = [[ Таймаут отсутствия Сим карты. Источник: /etc/config/tsmodem  ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "sim_$sim_id",
				option = "timeout_sim_absent",
			}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	wait_timer = {
		note = [[ Таймер ожидания на попытки найти Сим-карту в слоте ]],
		input = 0,
		modifier = {
			["1_skip"] = [[ return (not tonumber($os_time)) ]],
			["2_func"] = [[
				local wt = tonumber($wait_timer) or 0

				local STEP = os.time() - tonumber($os_time)
				if STEP > 50 then STEP = 2 end -- it uses when ntpd synced system time

				if ($sim_ready == "true" or $do_switch == "true") then
					return 0
				else
					return (wt + STEP)
				end
			]],
			["3_save"] = [[ return $wait_timer ]]

		}
	},

	do_switch = {
		note = [[ Переключает слот, если SIM-карта на найдена в текущем слоте  ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "01_rule"},
		},
		modifier = {
			["1_skip"] = [[
				local SIMID_OK = ($sim_id == "0" or $sim_id == "1")
				local wt = tonumber($wait_timer) or 0
				local t = tonumber($timeout) or 0
				local TIMEOUT = (wt >= t)
				local SIM_NOT_READY = ($sim_ready == "false")
				return ( not (SIMID_OK and TIMEOUT and SIM_NOT_READY) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_func"] = [[ return tostring($do_switch) ]],
			["4_frozen"] = [[ return 10 ]]
		}
	},


	os_time = {
		note = [[ Время ОС на предыдущей итерации ]],
		modifier = {
			["1_func"] = [[ return os.time() ]],
			["2_save"] = [[ return $os_time ]]
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"wait_timer",
					"reset_timer",
					"sim_ready",
					"sim_comment",
					"timeout",
					"do_switch",
				}
			},
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

	-- These variables are included into debug overview (run "applogic debug" to get all rules overview)
	-- Green, Yellow and Red are measure of importance for Application logic
	-- Green is for timers and some passive variables,
	-- Yellow is for that vars which switches logic - affects to normal application behavior
	-- Red is for some extraordinal application ehavior, like watchdog, etc.
	local overview = {
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
		["sim_ready"] = { ["yellow"] = [[ return ($sim_ready == "false" or $sim_ready == "*") ]] },
		["wait_timer"] = { ["yellow"] = [[ return (tonumber($wait_timer) and tonumber($wait_timer) > 0) ]] }
	}

	self:load("title"):modify():debug() 	-- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()	-- Use "overview" to include the variable to the all rules overview report in debug mode
	self:load("sim_ready"):modify():debug(overview)
	self:load("sim_comment"):modify():debug(overview)

	self:load("timeout"):modify():debug()
	self:load("wait_timer"):modify():debug(overview)
	self:load("do_switch"):modify():debug(overview)
	self:load("os_time"):modify():debug()
	self:load("send_ui"):modify():debug()
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
