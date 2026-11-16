local _, ns = ...

local L = setmetatable({}, { __index = function(t, k)
    local v = tostring(k)
    rawset(t, k, v)
    return v
end })

-- Use existing localization strings provided by Blizzard for some things.
-- Source: https://www.townlong-yak.com/framexml/live/GlobalStrings.lua

L["OK"] = OKAY
L["Cancel"] = CANCEL
L["Close"] = CLOSE
L["Save"] = SAVE
L["Delete"] = DELETE
L["Edit"] = EDIT
L["Search"] = SEARCH
L["Settings"] = SETTINGS

ns.Localization = L
