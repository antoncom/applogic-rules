local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Cим-карты при отсутствии регистрации в сети",
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

	uci_section = {
		note = [[ Идентификатор секции вида "sim_0" или "sim_1". Источник: /etc/config/tsmodem ]],
		modifier = {
			-- ["1_func"] = [[ if ($sim_id == "0" or $sim_id == "1") then return ("sim_" .. $sim_id) else return "ERROR, no SIM_ID!" end ]],
			["1_lua-func"] = function (vars)
				if (vars.sim_id == "0" or vars.sim_id == "1") then
					return ("sim_" .. vars.sim_id)
				else
					return "ERROR, no SIM_ID!"
				end
			end,
		}
	},

	timeout = {
		note = [[ Таймаут отсутствия регистрации в сети. Источник: /etc/config/tsmodem  ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "$uci_section",
				option = "timeout_reg",
			}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "sim_ready",
		},
	},

	network_registration = {
		note = [[ Статус регистрации Сим-карты в сети -1..9. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],

			-- ["2_func"] = [[
			-- 	if ($sim_ready == "false") then return "-1"
			-- 	elseif ($iface_up == "UP") then return $network_registration
			-- 	elseif ($iface_up == "*") then return "9"
			-- 	elseif ($iface_up == "false") then return "8"
			-- 	else return $network_registration end
			-- ]]
			["2_lua-func"] = function (vars)
				if (vars.sim_ready == "false") then return "-1"
				elseif (vars.iface_up == "UP") then return vars.network_registration
				elseif (vars.iface_up == "*") then return "9"
				elseif (vars.iface_up == "false") then return "8"
				else return vars.network_registration end
			end
		}
	},

	lastreg_timer = {
		note = [[ Отсчёт секунд при отсутствии REG ]],
		input = 0, -- Set default value if you need "reset" variable before skipping
		modifier = {
			-- ["1_skip"] = [[ return (not tonumber($os_time)) ]],
			["1_skip-func"] = function (vars)
				return (not tonumber(vars.os_time))
			end,

			-- ["2_func"] = [[
			-- 	local STEP = os.time() - tonumber($os_time)
			-- 	if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

			-- 	local netreg = tonumber($network_registration) or 0
			-- 	local lastreg_t = tonumber($lastreg_timer) or 0
			-- 	local SIM_NOT_OK = ($sim_ready ~= "true")
			-- 	local SWITCHING = ($switching ~= "false")
			-- 	local REG_OK = netreg and (netreg == 1 or netreg == 7 or netreg == -1)
			-- 	if (REG_OK or SIM_NOT_OK or SWITCHING) then
			-- 		return 0
			-- 	else return ( lastreg_t + STEP ) end
			-- ]],
			["2_lua-func"] = function (vars)
				print(vars.os_time)
				local STEP = os.time() - tonumber(vars.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local netreg = tonumber(vars.network_registration) or 0
				local lastreg_t = tonumber(vars.lastreg_timer) or 0
				local SIM_NOT_OK = (vars.sim_ready ~= "true")
				local SWITCHING = (vars.switching ~= "false")
				local REG_OK = netreg and (netreg == 1 or netreg == 7 or netreg == -1)
				if (REG_OK or SIM_NOT_OK or SWITCHING) then
					return 0
				else return ( lastreg_t + STEP ) end
			end,

            -- ["3_save"] = [[ return $lastreg_timer ]],
            ["3_save-func"] = function (vars)
				return vars.lastreg_timer
			end,
		}
	},

    os_time = {
		note = [[ Время ОС на предыдущей итерации ]],
        modifier = {
            -- ["1_func"] = [[ return os.time() ]],
			["1_lua-func"] = function (vars)
				return os.time()
			end,

            -- ["2_save"] = [[ return $os_time ]],
            ["2_save-func"] = function (vars)
				return vars.os_time
			end,
        }
    },

	iface_up = {
		note = [[ Поднялся ли интерфейс TSMODEM - Link до интернет-провайдера ]],
        modifier = {
            -- ["1_skip"] = [[ return (not ($sim_ready == "true" and $switching ~= "true") ) ]],
			["1_skip-func"] = function (vars)
				return (not (vars.sim_ready == "true" and vars.switching ~= "true") )
			end,

            ["2_bash"] = [[ ifconfig 3g-modem 2>/dev/nul | grep 'UP POINTOPOINT RUNNING' | awk '{print $1}' ]], -- see http://srr.cherkessk.ru/owrt/help-owrt.html

			-- ["3_func"] = [[ local lastreg_t = tonumber($lastreg_timer) or 0
			-- 				if ($iface_up == "UP") then return "true"
			-- 				elseif lastreg_t < 30 then return "*"
			-- 				else return "false" end
			-- 			 ]]
			["3_lua-func"] = function (vars)
				local lastreg_t = tonumber(vars.lastreg_timer) or 0

				if (vars.iface_up == "UP") then
					return "true"
				elseif lastreg_t < 30 then
					return "*"
				else
					return "false"
				end
			end
        }
    },

    event_datetime = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],

			-- ["2_func"] = 'return(os.date("%Y-%m-%d %H:%M:%S", tonumber($event_datetime)))'
			["2_lua-func"] = function (vars)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(vars.event_datetime)))
			end
		}
	},
	event_is_new = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},
	event_reg = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},


	do_switch = {
		note = [[ Переключает слот, если SIM не зарегистрирована в GSM сети или нет соединения с интернет. ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "02_rule"},
		},
		modifier = {
			-- ["1_skip"] = [[
			-- 	local lastreg_t = tonumber($lastreg_timer) or 0
			-- 	local out = tonumber($timeout) or 0
			-- 	local READY = 	( $switching == "" or $switching == "false" )
			-- 	local TIMEOUT = ( lastreg_t > out )
			-- 	return ( not (READY and TIMEOUT) )
			-- ]],
			["1_skip-func"] = function (vars)
				local lastreg_t = tonumber(vars.lastreg_timer) or 0
				local out = tonumber(vars.timeout) or 0
				local READY = 	(vars.switching == "" or vars.switching == "false" )
				local TIMEOUT = ( lastreg_t > out )
				return ( not (READY and TIMEOUT) )
			end,

			["2_bash"] = [[ jsonfilter -e $.value ]],

			-- ["3_func"] = [[ return tostring($do_switch) ]],
			["3_lua-func"] = function (vars)
				return tostring(vars.do_switch)
			end,

			["4_frozen"] = [[ return 10 ]]
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"lastreg_timer",
					"network_registration",
					"lastreg_timer",
					"do_switch",
					"switching"
				}
			},
		}
	},
	journal = {
		modifier = {
			-- ["1_skip"] = [[ if ($event_is_new == "true") then return false else return true end ]],
			["1_skip-func"] = function (vars)
				if (vars.event_is_new == "true") then return false else return true end
			end,

			-- ["2_func"] = [[return({
			-- 		datetime = $event_datetime,
			-- 		name = "Изменился статус регистрации в GSM-сети",
			-- 		source = "Modem  (02-rule)",
			-- 		command = "AT+CREG?",
			-- 		response = $event_reg
			-- 	})]],
			["2_lua-func"] = function (vars)
				return({
					datetime = vars.event_datetime,
					name = "Изменился статус регистрации в GSM-сети",
					source = "Modem  (02-rule)",
					command = "AT+CREG?",
					response = vars.event_reg
				})
			end,

			["3_store-db"] = {
				param_list = { "journal" }
			}
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
		["lastreg_timer"] = { ["yellow"] = [[ return (tonumber($lastreg_timer) and tonumber($lastreg_timer) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then 
		--if rule.debug_mode.enabled then print("------ 02_rule SKIPPED as r01_wait_timer > 0 -----") end
		return 
	end


	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("uci_section"):modify():debug()
	self:load("timeout"):modify():debug()

	self:load("sim_ready"):modify():debug()
	self:load("network_registration"):modify():debug()
	self:load("lastreg_timer"):modify():debug()
	self:load("os_time"):modify():debug()
	self:load("iface_up"):modify():debug()
	self:load("event_datetime"):modify():debug()
	self:load("event_is_new"):modify():debug()
	self:load("event_reg"):modify():debug()
	self:load("do_switch"):modify():debug(overview)
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
