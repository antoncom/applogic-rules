
--[[ Use /etc/config/applogic to set debug mode, like this

config debug_mode 'debug_mode'
    option enable '1'
    option type 'VAR'
    option level 'INFO'

    enable  =   0/1 - to enable / disable debug globally
    type    =   RULE or VAR are possible
    level   =   ERROR, INFO are possible:

                        ERROR    - show only if error occures
                        INFO     - show anyway

                        EXAMPLES

                        ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━┯━━━━┓
VAR type                ┃ [ SWITH_CPE ] VARIABLE ATTRIBUTES VALUE                                         │ RESULTS ON THE ITERATION │ #6 ┃
INFO level              ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┿━━━━━━━━━━━━━━━━━━━━━━━━━━┿━━━━┫
                        ┃ input                                                                           │ empty                    │ ✔  ┃
                        ┠──────────┬──────────┬───────────────────────────────────────────────────────────┼──────────────────────────┼────┨
                        ┃ modifier │ [1_skip] │ local is_current_ok = ("0" == "1")                        │ true                     │ ✔  ┃
                        ┃          │          │ local is_reserved_fail = ("mcn.com" == "")                │                          │    ┃
                        ┃          │          │ local not_ready_to_switch =                               │                          │    ┃
                        ┃          │          │ (is_current_ok or is_reserved_fail or tonumber("7") < 15) │                          │    ┃
                        ┃          │          │ return not_ready_to_switch                                │                          │    ┃
                        ┃          │          │                                                           │                          │    ┃
                        ┠──────────┴──────────┴───────────────────────────────────────────────────────────┼──────────────────────────┼────┨
                        ┃ output                                                                          │ empty                    │ ✔  ┃
                        ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━┛
]]

local uci = require "luci.model.uci".cursor()
local debug_mode = {
    enabled = (uci:get("applogic", "debug_mode", "enable") == "1"),
    type = uci:get("applogic", "debug_mode", "type"),
    level = uci:get("applogic", "debug_mode", "level"),
}

return debug_mode
