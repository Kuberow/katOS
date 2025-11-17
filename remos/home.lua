local tui = require("touchui")
local container = require("touchui.containers")
local input = require("touchui.input")
local list = require("touchui.lists")
local draw = require("draw")
local popups = require("touchui.popups")
local homeWin = window.create(term.current(), 1, 1, term.getSize())

---@class Shortcut
---@field icon BLIT?
---@field iconFile string?
---@field label string
---@field path string

local function saveShortcuts(shortcuts)
    for i, v in ipairs(shortcuts) do
        v.icon = nil
    end
    assert(remos.saveTable("config/home_apps.table", shortcuts, false))
end

local defaultIcon = assert(remos.loadTransparentBlit("icons/default.icon"))
local unknownIcon = assert(remos.loadTransparentBlit("icons/missing.icon"))

local function loadShortcuts()
    ---@type Shortcut[]
    local shortcuts = assert(remos.loadTable("config/home_apps.table"))
    for i, v in ipairs(shortcuts) do
        if v.iconFile then
            v.icon = remos.loadTransparentBlit(v.iconFile) or unknownIcon
        end
    end
    return shortcuts
end

local shortcuts = loadShortcuts()
local gridList

---Update/create/delete a shortcut
---@param index integer
---@param label string?
---@param path string?
---@param iconSmallFile string?
---@param iconLargeFile string?
local function shortcutMenu(index, label, path, iconSmallFile, iconLargeFile)
    local rootWin = window.create(term.current(), 1, 1, term.getSize())
    local rootVbox = container.vBox()
    rootVbox:setWindow(rootWin)

    local labelInput = input.inputWidget("Label")
    rootVbox:addWidget(labelInput)
    labelInput:setValue(label or "")

    local pathPicker = input.fileWidget("Path", nil, nil, "lua")
    pathPicker.selected = path
    rootVbox:addWidget(pathPicker)

    local iconFilePicker = input.fileWidget("Icon", nil, nil, "icon", nil, "icons")
    iconFilePicker.selected = iconSmallFile
    rootVbox:addWidget(iconFilePicker)

    local deleteButton = input.buttonWidget("Delete", function(self)
        table.remove(shortcuts, index)
        saveShortcuts(shortcuts)
        shortcuts = loadShortcuts()
        gridList:setTable(shortcuts)
        rootVbox.exit = true
    end)
    rootVbox:addWidget(deleteButton, 3)
    local cancelButton = input.buttonWidget("Cancel", function(self)
        rootVbox.exit = true
    end)
    rootVbox:addWidget(cancelButton, 3)
    local saveButton = input.buttonWidget("Save", function(self)
        if type(labelInput.value) == "string" and type(pathPicker.selected) == "string" then
            shortcuts[index] = {
                label = labelInput.value,
                path = pathPicker.selected,
                iconFile = iconFilePicker.selected
            }
        else
            remos.addAppFile("remos/popup.lua", "Error!",
                "Label and Path are both required to be filled to save this shortcut!")
        end
        saveShortcuts(shortcuts)
        shortcuts = loadShortcuts()
        gridList:setTable(shortcuts)
        rootVbox.exit = true
    end)
    rootVbox:addWidget(saveButton, 3)

    tui.run(rootVbox, true, nil, true)
end

settings.define("remos.home.large_icons", {
    description = "Use large icons for home screen (3x3 instead of 4x4)",
    type = "boolean",
    default = false
})

local homeSize = 4
if settings.get("remos.home.large_icons") then
    homeSize = 3
end

local strings = require "cc.strings"

-- macOS-style rendering with dock-like appearance
gridList = list.gridListWidget(shortcuts, homeSize, homeSize, function(win, x, y, w, h, item, theme)
    local icon = item.icon or defaultIcon
    
    -- Draw subtle background for icon area (macOS-style frosted glass effect)
    local bgColor = colors.lightGray
    local textColor = colors.black
    
    -- Calculate icon position (centered)
    local iconx = math.floor((w - 5) / 2)
    local icony = math.floor((h - 3) / 2) - 1
    
    -- Draw rounded background for icon
    if theme and theme.background then
        bgColor = theme.background
    end
    
    -- Create subtle card effect
    for dy = 0, 2 do
        win.setCursorPos(x + iconx, y + icony + dy)
        win.setBackgroundColor(bgColor)
        win.write("     ")
    end
    
    -- Draw the icon
    draw.draw_blit(x + iconx, y + icony, icon, win)
    
    -- Draw label below icon (macOS uses centered, single-line labels)
    local wrapped = strings.wrap(item.label, w - 2)
    local labelText = wrapped[1] or item.label
    
    -- Truncate with ellipsis if too long
    if #labelText > w - 2 then
        labelText = string.sub(labelText, 1, w - 4) .. ".."
    end
    
    local labelY = y + icony + 4
    local labelX = x + math.floor((w - #labelText) / 2)
    
    -- Draw label with slight shadow effect
    if labelY <= y + h - 1 then
        win.setCursorPos(labelX, labelY)
        win.setBackgroundColor(theme and theme.background or colors.gray)
        win.setTextColor(theme and theme.text or colors.white)
        win.write(labelText)
    end
end, function(index, item)
    remos.addAppFile(item.path)
end, function(index, item)
    shortcutMenu(index, item.label, item.path, item.iconSmallFile, item.iconLargeFile)
end)

gridList:setWindow(homeWin)

tui.run(gridList, nil, function(event)
    if event == "settings_update" then
        homeSize = 4
        if settings.get("remos.home.large_icons") then
            homeSize = 3
        end
        gridList:updateGridSize(homeSize, homeSize)
        shortcuts = loadShortcuts()
        gridList:setTable(shortcuts)
        defaultIcon = assert(remos.loadTransparentBlit("icons/default.icon"))
    elseif event == "add_home_shortcut" then
        shortcutMenu(#shortcuts + 1)
    end
end, true)
