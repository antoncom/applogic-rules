local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты, если баланс ниже минимума. Работает совместно с правилами 14_rule, 15_rule",
	},

    sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
            	method = "sim",
            	params = {},
        	}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.sim_id) or {}
				return lua_table.value or ""
			end
		}
    },


	uci_balance_min = {
		note = [[ Минимальный уровень баланса, руб. ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "balance_min",
				},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.uci_balance_min) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes)
				local ubm = tonumber(nodes.uci_balance_min) or 30
				return ubm
			end
		}
	},

	uci_timeout_bal = {
		note = [[ Таймаут перед переключеием при низком балансе, сек. ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "timeout_bal",
				}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.uci_timeout_bal) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes)
				local utb = tonumber(nodes.uci_timeout_bal) or 120
				return utb
			end
		}
	},

    balance_time = {
		note = [[ Актуальная дата получения баланса, UNIXTIME. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "balance",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.balance_time) or {}
				return lua_table.time or ""
			end,
		}
	},

	event_datetime = {
		note = [[ Дата актуального баланса в формате для Web-интерфейса. ]],

		{
			["func"] = function (nodes)
				local bt = tonumber(nodes.balance_time) or 0
				if (bt ~= 0) then return(os.date("%Y-%m-%d %H:%M:%S", bt)) else return "" end
			end
		}
	},

	sim_balance = {
		note = [[ Сумма баланса на текущей Сим-карте, руб. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "balance",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.sim_balance) or {}
				return lua_table.value or ""
			end,
		}
	},

	balance_message = {
		note = [[ Сообщение от GSM-провайдера ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "balance",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.balance_message) or {}
				return lua_table.comment or ""
			end,
		},
		{
			["bash"] = [[ sed s/\"//g ]],
		}
	},

	ussd_command = {
		note = [[ Хранит строку USSD-запроса на получение баланса.  ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "balance",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.ussd_command) or {}
				return lua_table.command or ""
			end
		}
	},

	r01_timer = {
		note = [[ Значение wait_timer из правила 01_rule ]],

		{
			["load-rule"] = {
				rulename = "01_rule",
				nodename = "wait_timer"
			},
		}
	},

	r02_lastreg_timer = {
		note = [[ Значение lastreg_timer из правила 01_rule ]],

		{
			["load-rule"] = {
				rulename = "02_rule",
				nodename = "lastreg_timer"
			}
		},
	},

    lowbalance_timer = {
		note = [[ Счётчик секунд при балансе ниже минимума, сек. ]],
		default = 0,

		{
			["skip"] = function (nodes)
				return not tonumber(nodes.os_time)
			end
		},
		{
			["func"] = function (nodes)
				local STEP = os.time() - (tonumber(nodes.os_time) or 0)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local lbt = tonumber(nodes.lowbalance_timer) or 0
				local sb = tonumber(nodes.sim_balance) or 0
				local ubmin = tonumber(nodes.uci_balance_min) or 0
				local r01t = tonumber(nodes.r01_timer) or 0
				local r02lt = tonumber(nodes.r02_lastreg_timer) or 0
				local TIMER = lbt + STEP
				local BALANCE_OK = (sb > ubmin) 
				local BALANCE_EMPTY = (sb == 0)
				local SIM_NOT_REGISTERED = (r02lt > 0)
				local SIM_ABSENT = (r01t > 0)
				if SIM_ABSENT then return 0
				elseif BALANCE_EMPTY then return 0
				elseif SIM_NOT_REGISTERED then return 0
				elseif BALANCE_OK then return 0
				else return TIMER or 0 end
			end
		},
		{
			["save"] = function (nodes)
				return nodes.lowbalance_timer
			end
        }
	},

	os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],

		{
			["func"] = function (nodes)
				return os.time()
			end
		},
		{
			["save"] = function (nodes)
				return nodes.os_time
			end
		}
	},

	event_is_new = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "balance",
				params = {}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.event_is_new) or {}
				return lua_table.unread or ""
			end,
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "switching",
				params = {},
				cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.switching) or {}
				return lua_table.value or ""
			end,
		}
	},

	r01_resetting = {
		note = [[ Значение resetting из правила 01_rule ]],

		{
			["load-rule"] = {
				rulename = "01_rule",
				nodename = "resetting"
			}
		}
	},

	do_switch = {
		note = [[ Переключает слот если баланс SIM ниже порогового. ]],
		default = "false",

		{
			["skip"] = function (nodes)
				local lt = tonumber(nodes.lowbalance_timer) or 0
				local utb = tonumber(nodes.uci_timeout_bal) or 0
				local READY = 	( nodes.switching == "" or nodes.switching == "false" or nodes.r01_resetting ~= "true" )
				local TIMEOUT = ((lt + 10) > utb)
				return ( not (READY and TIMEOUT) )
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_switch",
				params = { rule = "03_rule"},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.do_switch) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes)
				return tostring(nodes.do_switch)
			end
		},
		{
			["frozen"] = function (nodes)
				return 15
			end
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],

		{
			["ui-update"] = {
				param_list = {
					"sim_id",
					"do_switch",
					"sim_balance",
					"event_datetime",
					"lowbalance_timer",
				}
			}
		}
	},

	provider_id = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "provider_name",
				params = {}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.provider_id) or {}
				return lua_table.comment or ""
			end
		}
	},

	journal = {
		{
			["skip"] = function (nodes)
				if (nodes.event_is_new == "true" and (string.len(nodes.balance_message) > 0) )  then return false else return true end
			end
		},
		{
			["func"] = function (nodes)
				return({
						datetime = nodes.event_datetime,
						name = "Получено значение баланса SIM-карты",
						source = "Modem (03-rule)",
						command = nodes.ussd_command,
						["response"] = nodes.balance_message,
						ussd_command = nodes.ussd_command,
						provider_id = nodes.provider_id
					})
			end
		},
		{
			["store-db"] = {
				param_list = { "journal" }
			}
		},
		{
			["frozen"] = function (nodes)
				return 2
			end
		}
	},
}

--ussd = $ussd_command
-- balance = $balance_message

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 02_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- These variables are included into debug overview (run "applogic debug" to get all rules overview)
	-- Green, Yellow and Red are measure of importance for Application logic
	-- Green is for timers and some passive variables,
	-- Yellow is for that nodes which switches logic - affects to normal application behavior
	-- Red is for some extraordinal application ehavior, like watchdog, etc.
	local overview = {
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
		["lowbalance_timer"] = { ["yellow"] = [[ return (tonumber($lowbalance_timer) and tonumber($lowbalance_timer) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then
		--if rule.debug_mode.enabled then print("------ 03_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end


	self:follow("title"):debug() -- Use debug(ONLY) to check the var only
	self:follow("sim_id"):debug()
	self:follow("uci_balance_min"):debug()
	self:follow("uci_timeout_bal"):debug()

	self:follow("balance_time"):debug()
	self:follow("event_datetime"):debug()
	self:follow("sim_balance"):debug()
	self:follow("balance_message"):debug()
	self:follow("ussd_command"):debug()
	self:follow("r01_timer"):debug()
	self:follow("r02_lastreg_timer"):debug()
	self:follow("lowbalance_timer"):debug(overview)
	self:follow("os_time"):debug()
	self:follow("event_is_new"):debug()
	self:follow("switching"):debug()
	self:follow("r01_resetting"):debug()
	self:follow("do_switch"):debug(overview)
	self:follow("send_ui"):debug()
	self:follow("provider_id"):debug()
	self:follow("journal"):debug()
end


local metatable = {
    __call = function(table, parent)
        local rule_init_table = rule_init(table, rule_setting, parent)
        rule_init_table:make()
        return rule_init_table
    end
}
setmetatable(rule, metatable)
return rule
