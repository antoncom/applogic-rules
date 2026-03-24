local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"
local uci = require "luci.model.uci".cursor()


local rule = {}
local rule_setting = {
	title = {
		input = "Правило для управления роутером по СМС.",
	},

    max_text_size = {
        note = [[ Максимальный размер текста для отправки по смс, иначе отправка через email ]],
        default = 201, -- 3 смс кусочка по 67 символов
    },

    received_sms = {
		note = [[ Подписка на чтение новой смс ]],
		default = "",

		{
			["subscribe"] = {
				ubus = "tsmodem.sms",
				evname = "NEW-SMS-RECEIVED",
				match = { status = "ok"},
			}
		},
		{
			["func"] = function (nodes)

                -- print(type(nodes.received_sms))
                -- print(nodes.received_sms)
                -- print(luci.jsonc.parse(nodes.received_sms))

                local lua_table = luci.jsonc.parse(nodes.received_sms) or {}
				return lua_table or ""
			end,
		}
	},

    call_tsmsmscomm_run = {
        note = [[ Вызывает метод выполнения команды полученной по смс ]],

        {
            ["skip"] = function (nodes)
                return #nodes.received_sms <= 2
            end
        },
        {
            ["load-ubus"] = function (nodes)
                local sms_data_table = luci.jsonc.parse(nodes.received_sms)

                return ({
                    object = "tsmsmscomm",
                    method = "run",
                    params = {
                        phone = sms_data_table.sender,
                        message = sms_data_table.message,
                    },
                })
            end
        }
    },

    tsmsmscomm_run_result = {
        note = [[ Подписка на получение результата выполненной команды ]],
        default = "",

        {
            ["subscribe"] = {
                ubus = "tsmsmscomm",
                evname = "result",
                match = {},
            },
        },
        {
            ["func"] = function (nodes)
                if type(nodes.tsmsmscomm_run_result) == "table" then
                    local file = io.open(nodes.tsmsmscomm_run_result.tmp_file, "r")
                    if file ~= nil then
                        nodes.tsmsmscomm_run_result.result = file:read("*a")
                        file:close()
                    end
                end

                return nodes.tsmsmscomm_run_result or ""
            end
        },
    },

    sms_answer = {
        title = [[ Отправляет результат по смс, если текст вмещается в max_text_size ]],

        {
            ["skip"] = function (nodes)
                if nodes.tsmsmscomm_run_result == nil or
                    type(nodes.tsmsmscomm_run_result) ~= "table" or
                    nodes.tsmsmscomm_run_result.run == nil or
                    nodes.tsmsmscomm_run_result.run == false
                then
                    return true
                end

                return (nodes.tsmsmscomm_run_result.result == nil or #nodes.tsmsmscomm_run_result.result == 0)
                    or #nodes.tsmsmscomm_run_result.result > tonumber(nodes.max_text_size)
            end
        },
        {
            ["send-sms"] = function (nodes)
                return ({
                    phone = nodes.tsmsmscomm_run_result.trusted_phone,
                    text = nodes.tsmsmscomm_run_result.result,
                })
            end
        },
        -- { -- send sms (load-ubus instead of send-sms)
        --     ["load-ubus"] = function (nodes)
        --         return ({
        --             object = "tsmodem.sms",
        --             method = "send_sms",
        --             params = {
        --                 phone = nodes.tsmsmscomm_run_result.trusted_phone,
        --                 text = nodes.tsmsmscomm_run_result.result,
        --             }
        --         })
        --     end
        -- },
    },

    email_answer = {
        title = [[ Отправляет результат по email, если текст более чем max_text_size ]],

        {
            ["skip"] = function (nodes)
                if nodes.tsmsmscomm_run_result == nil or
                    type(nodes.tsmsmscomm_run_result) ~= "table" or
                    nodes.tsmsmscomm_run_result.run == nil or
                    nodes.tsmsmscomm_run_result.run == false
                then
                    return true
                end

                return (nodes.tsmsmscomm_run_result.result == nil or #nodes.tsmsmscomm_run_result.result == 0)
                    or #nodes.tsmsmscomm_run_result.result <= tonumber(nodes.max_text_size)
            end
        },
        {
            ["load-ubus"] = function (nodes)
                local params = {
                    from = uci:get("tsmail", "general", "auth_user"),
                    to = nodes.tsmsmscomm_run_result.trusted_email,
                    subj = "Результат выполнения смс команды",
                    body = "Результат выполнения смс команды",
                    attach = nodes.tsmsmscomm_run_result.tmp_file,
                }

                return ({
                    object = "tsmail",
                    method = "send",
                    params = params,
                })
            end
        },
    },

    journal = {
        {
            ["skip"] = function (nodes)
                if nodes.tsmsmscomm_run_result == nil or
                    type(nodes.tsmsmscomm_run_result) ~= "table" or
                    nodes.tsmsmscomm_run_result.run == nil or
                    nodes.tsmsmscomm_run_result.run == false
                then
                    return true
                end

                return (nodes.tsmsmscomm_run_result.result == nil or #nodes.tsmsmscomm_run_result.result == 0)
            end
        },
		{
			["func"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = "Получена SMS-команда",
					source = nodes.tsmsmscomm_run_result.trusted_phone,
					command = nodes.tsmsmscomm_run_result.shell_command,
					response = nodes.tsmsmscomm_run_result.result,
				})
			end
		},
		{
			["store-db"] = {
				param_list = { "journal" }
			},
		}
	},
}

function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	local overview = {}

    self:follow("max_text_size"):debug()
    self:follow("received_sms"):debug()

    self:follow("call_tsmsmscomm_run"):debug()
    self:follow("tsmsmscomm_run_result"):debug()
    self:follow("sms_answer"):debug()
    self:follow("email_answer"):debug()
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
