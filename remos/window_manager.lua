local window_manager = {}

-- Window states and tracking
window_manager.windows = {}
window_manager.activeWindow = nil
window_manager.zIndex = 1

---@class WindowInfo
---@field id integer
---@field win window
---@field title string
---@field x integer
---@field y integer
---@field width integer
---@field height integer
---@field maximized boolean
---@field minimized boolean
---@field originalSize table
---@field originalPos table
---@field zIndex integer
---@field controls any

function window_manager.createWindow(title, x, y, width, height, contentFunc)
    local termW, termH = term.getSize()
    local dockHeight = 3
    
    -- Default position and size
    x = x or math.floor((termW - width) / 2)
    y = y or math.floor((termH - height - dockHeight) / 2)
    width = width or math.floor(termW * 0.8)
    height = height or math.floor((termH - dockHeight) * 0.8)
    
    local win = window.create(term.current(), x, y, width, height)
    local id = #window_manager.windows + 1
    
    local windowInfo = {
        id = id,
        win = win,
        title = title or "App",
        x = x,
        y = y,
        width = width,
        height = height,
        maximized = false,
        minimized = false,
        originalSize = {w = width, h = height},
        originalPos = {x = x, y = y},
        zIndex = window_manager.zIndex,
        controls = {},
        contentFunc = contentFunc
    }
    
    window_manager.zIndex = window_manager.zIndex + 1
    table.insert(window_manager.windows, windowInfo)
    window_manager.activeWindow = id
    
    return windowInfo
end

function window_manager.drawWindowControls(win, title, width)
    local controlHeight = 1
    
    -- Title bar background
    win.setBackgroundColor(colors.gray)
    win.setTextColor(colors.white)
    for x = 1, width do
        win.setCursorPos(x, 1)
        win.write(" ")
    end
    
    -- Control buttons (left side)
    win.setCursorPos(2, 1)
    win.setBackgroundColor(colors.red)
    win.write(" × ") -- Close
    
    win.setCursorPos(6, 1)
    win.setBackgroundColor(colors.yellow)
    win.write(" - ") -- Minimize
    
    win.setCursorPos(10, 1)
    win.setBackgroundColor(colors.lime)
    win.write(" + ") -- Maximize
    
    -- Window title (centered)
    win.setBackgroundColor(colors.gray)
    local titleX = math.floor((width - #title) / 2)
    win.setCursorPos(math.max(titleX, 14), 1)
    win.write(title)
    
    return controlHeight
end

function window_manager.handleControlClick(windowInfo, x, y)
    if y == 1 then
        if x >= 2 and x <= 4 then -- Close button
            return "close"
        elseif x >= 6 and x <= 8 then -- Minimize button
            return "minimize"
        elseif x >= 10 and x <= 12 then -- Maximize button
            return "maximize"
        end
    end
    return nil
end

function window_manager.toggleMaximize(windowInfo)
    local termW, termH = term.getSize()
    local dockHeight = 3
    
    if windowInfo.maximized then
        -- Restore original size
        windowInfo.win.reposition(
            windowInfo.originalPos.x, 
            windowInfo.originalPos.y, 
            windowInfo.originalSize.w, 
            windowInfo.originalSize.h
        )
        windowInfo.width = windowInfo.originalSize.w
        windowInfo.height = windowInfo.originalSize.h
        windowInfo.maximized = false
    else
        -- Save current state and maximize
        windowInfo.originalSize.w = windowInfo.width
        windowInfo.originalSize.h = windowInfo.height
        windowInfo.originalPos.x, windowInfo.originalPos.y = windowInfo.win.getPosition()
        windowInfo.win.reposition(1, 1, termW, termH - dockHeight)
        windowInfo.width = termW
        windowInfo.height = termH - dockHeight
        windowInfo.maximized = true
    end
end

function window_manager.minimizeWindow(windowInfo)
    windowInfo.minimized = true
    windowInfo.win.setVisible(false)
end

function window_manager.restoreWindow(windowInfo)
    windowInfo.minimized = false
    windowInfo.win.setVisible(true)
    window_manager.activeWindow = windowInfo.id
end

function window_manager.closeWindow(windowInfo)
    windowInfo.win.setVisible(false)
    for i, win in ipairs(window_manager.windows) do
        if win.id == windowInfo.id then
            table.remove(window_manager.windows, i)
            break
        end
    end
    if window_manager.activeWindow == windowInfo.id then
        window_manager.activeWindow = #window_manager.windows > 0 and window_manager.windows[#window_manager.windows].id or nil
    end
end

function window_manager.bringToFront(windowInfo)
    windowInfo.zIndex = window_manager.zIndex
    window_manager.zIndex = window_manager.zIndex + 1
    window_manager.activeWindow = windowInfo.id
end

function window_manager.getWindowAt(x, y)
    -- Find topmost window at coordinates
    local topWindow = nil
    local topZ = -1
    
    for _, winInfo in ipairs(window_manager.windows) do
        if not winInfo.minimized then
            local winX, winY = winInfo.win.getPosition()
            local winW, winH = winInfo.win.getSize()
            
            if x >= winX and x < winX + winW and y >= winY and y < winY + winH then
                if winInfo.zIndex > topZ then
                    topZ = winInfo.zIndex
                    topWindow = winInfo
                end
            end
        end
    end
    
    return topWindow
end

function window_manager.redrawAll()
    local termW, termH = term.getSize()
    
    -- Clear entire screen
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Redraw all windows in z-order
    local windowsByZ = {}
    for _, winInfo in ipairs(window_manager.windows) do
        table.insert(windowsByZ, winInfo)
    end
    
    table.sort(windowsByZ, function(a, b) return a.zIndex < b.zIndex end)
    
    for _, winInfo in ipairs(windowsByZ) do
        if not winInfo.minimized then
            -- Draw window frame and controls
            local win = winInfo.win
            local w, h = win.getSize()
            
            -- Draw window background
            win.setBackgroundColor(colors.white)
            win.clear()
            
            -- Draw controls
            window_manager.drawWindowControls(win, winInfo.title, w)
            
            -- Notify window to redraw content
            if winInfo.contentFunc then
                local contentWin = window.create(win, 1, 2, w, h - 1)
                winInfo.contentFunc(contentWin)
            end
        end
    end
end

return window_manager
