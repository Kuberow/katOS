local tui = require("touchui")
local container = require("touchui.containers")
local input = require("touchui.input")
local list = require("touchui.lists")
local draw = require("draw")
local popups = require("touchui.popups")
local window_manager = require("remos.window_manager")

-- Create window for home content
local termW, termH = term.getSize()
local dockHeight = 3

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

-- Enhanced shortcut menu with window controls
local function shortcutMenu(index, label, path, iconSmallFile, iconLargeFile)
    local title = index <= #shortcuts and "Edit Shortcut" or "New Shortcut"
    
    local function drawContent(contentWin)
        local w, h = contentWin.getSize()
        contentWin.setBackgroundColor(colors.white)
        contentWin.setTextColor(colors.black)
        contentWin.clear()
        
        local vbox = container.vBox()
        vbox:setWindow(contentWin)
        
        local labelInput = input.inputWidget("Label")
        vbox:addWidget(labelInput)
        labelInput:setValue(label or "")

        local pathPicker = input.fileWidget("Path", nil, nil, "lua")
        pathPicker.selected = path
        vbox:addWidget(pathPicker)

        local iconFilePicker = input.fileWidget("Icon", nil, nil, "icon", nil, "icons")
        iconFilePicker.selected = iconSmallFile
        vbox:addWidget(iconFilePicker)

        local buttonContainer = container.hBox()
        vbox:addWidget(buttonContainer)

        if index <= #shortcuts then
            local deleteButton = input.buttonWidget("Delete", function(self)
                table.remove(shortcuts, index)
                saveShortcuts(shortcuts)
                shortcuts = loadShortcuts()
                gridList:setTable(shortcuts)
                vbox.exit = true
            end)
            buttonContainer:addWidget(deleteButton)
        end

        local cancelButton = input.buttonWidget("Cancel", function(self)
            vbox.exit = true
        end)
        buttonContainer:addWidget(cancelButton)
        
        local saveButton = input.buttonWidget("Save", function(self)
            if type(labelInput.value) == "string" and type(pathPicker.selected) == "string" then
                shortcuts[index] = {
                    label = labelInput.value,
                    path = pathPicker.selected,
                    iconFile = iconFilePicker.selected
                }
                saveShortcuts(shortcuts)
                shortcuts = loadShortcuts()
                gridList:setTable(shortcuts)
            else
                remos.addAppFile("remos/popup.lua", "Error!",
                    "Label and Path are both required to be filled to save this shortcut!")
            end
            vbox.exit = true
        end)
        buttonContainer:addWidget(saveButton)
        
        -- Custom event handling for window controls
        local originalEvent = vbox.event
        vbox.event = function(self, event, ...)
            if event == "mouse_click" then
                local button, x, y = ...
                local controlAction = window_manager.handleControlClick(windowInfo, x, y)
                if controlAction == "close" then
                    vbox.exit = true
                    return
                elseif controlAction == "minimize" then
                    window_manager.minimizeWindow(windowInfo)
                    return
                elseif controlAction == "maximize" then
                    window_manager.toggleMaximize(windowInfo)
                    window_manager.redrawAll()
                    return
                end
            end
            return originalEvent(self, event, ...)
        end
        
        tui.run(vbox, true, nil, true)
    end
    
    local windowInfo = window_manager.createWindow(title, nil, nil, 40, 20, drawContent)
    window_manager.redrawAll()
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

-- Main home window content
local function drawHomeContent(homeWin)
    gridList = list.gridListWidget(shortcuts, homeSize, homeSize, function(win, x, y, w, h, item, theme)
        local icon = item.icon or defaultIcon
        local iconx = math.floor((w - 5) / 2)
        local wrapped = strings.wrap(item.label, w - 1)
        local totalh = 3 + #wrapped
        local icony = math.max(math.floor((h - totalh) / 2), 1)
        draw.draw_blit(x + iconx, icony + y, icon, win)
        for i, t in ipairs(wrapped) do
            local toy = icony + i + 2
            if toy > h then
                break
            end
            local ty = toy + y
            local tx = x + math.floor((w - #t) / 2)
            draw.text(tx, ty, t, win)
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
        window_manager.redrawAll()
    end, true)
end

-- Create home window
local homeWindowInfo = window_manager.createWindow("Home", 1, 1, termW, termH - dockHeight, drawHomeContent)

-- Enhanced dock drawing function
local function drawDock()
    local dockWin = window.create(term.current(), 1, termH - dockHeight + 1, termW, dockHeight)
    
    -- Clear dock area
    dockWin.setBackgroundColor(colors.black)
    dockWin.clear()
    
    -- Draw dock background
    for y = 1, dockHeight do
        dockWin.setCursorPos(1, y)
        if y == 1 then
            dockWin.setBackgroundColor(colors.gray)
        else
            dockWin.setBackgroundColor(colors.lightGray)
        end
        for x = 1, termW do
            dockWin.write(" ")
        end
    end
    
    -- Draw separator line
    dockWin.setCursorPos(1, 1)
    dockWin.setBackgroundColor(colors.black)
    dockWin.setTextColor(colors.gray)
    for x = 1, termW do
        dockWin.write("▀")
    end
    
    -- Draw app icons in dock
    local dockApps = math.min(#shortcuts, 6)
    local totalWidth = dockApps * 6 + (dockApps - 1) * 2
    local startX = math.floor((termW - totalWidth) / 2)
    
    for i = 1, dockApps do
        local item = shortcuts[i]
        local x = startX + (i - 1) * 8
        
        -- Draw icon background
        dockWin.setBackgroundColor(colors.lightGray)
        for dy = 2, dockHeight do
            dockWin.setCursorPos(x, dy)
            dockWin.write("  ")
            dockWin.setCursorPos(x + 3, dy)
            dockWin.write("  ")
        end
        
        -- Draw icon
        dockWin.setCursorPos(x + 1, 3)
        dockWin.setBackgroundColor(colors.lightGray)
        dockWin.setTextColor(colors.blue)
        dockWin.write("[")
        dockWin.setTextColor(colors.black)
        dockWin.write(string.sub(item.label, 1, 1))
        dockWin.setTextColor(colors.blue)
        dockWin.write("]")
        
        -- Draw app label
        if #item.label > 0 then
            dockWin.setCursorPos(x, dockHeight)
            dockWin.setBackgroundColor(colors.lightGray)
            dockWin.setTextColor(colors.black)
            local displayLabel = string.sub(item.label, 1, 4)
            dockWin.write(" " .. displayLabel .. " ")
        end
    end
    
    -- System info
    local timeText = textutils.formatTime(os.time("local"), false)
    dockWin.setCursorPos(termW - #timeText - 1, 2)
    dockWin.setTextColor(colors.black)
    dockWin.setBackgroundColor(colors.lightGray)
    dockWin.write(timeText)
end

-- Global event handler for window management
local function globalEventHandler()
    while true do
        local event, param1, param2, param3, param4 = os.pullEvent()
        
        if event == "mouse_click" then
            local button, x, y = param1, param2, param3
            
            -- Check for dock clicks
            if y >= termH - dockHeight + 2 and y <= termH then
                local dockApps = math.min(#shortcuts, 6)
                local totalWidth = dockApps * 6 + (dockApps - 1) * 2
                local startX = math.floor((termW - totalWidth) / 2)
                
                for i = 1, dockApps do
                    local appX = startX + (i - 1) * 8
                    if x >= appX and x <= appX + 5 and y >= termH - 1 then
                        remos.addAppFile(shortcuts[i].path)
                        break
                    end
                end
            else
                -- Check for window control clicks
                local clickedWindow = window_manager.getWindowAt(x, y)
                if clickedWindow then
                    window_manager.bringToFront(clickedWindow)
                    local winX, winY = clickedWindow.win.getPosition()
                    local relX, relY = x - winX + 1, y - winY + 1
                    
                    local controlAction = window_manager.handleControlClick(clickedWindow, relX, relY)
                    if controlAction == "close" then
                        window_manager.closeWindow(clickedWindow)
                    elseif controlAction == "minimize" then
                        window_manager.minimizeWindow(clickedWindow)
                    elseif controlAction == "maximize" then
                        window_manager.toggleMaximize(clickedWindow)
                    end
                    window_manager.redrawAll()
                end
            end
        end
        
        drawDock()
    end
end

-- Main application loop
drawDock()
window_manager.redrawAll()

parallel.waitForAny(
    function() 
        -- Home screen event loop
        while true do
            os.sleep(0.1)
        end
    end,
    globalEventHandler
)
