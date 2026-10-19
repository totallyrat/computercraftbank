-- ComputerCraft's window API, as far as the Pocket Desktop uses it: a window
-- keeps its own grid of characters and colours, draws through to its parent
-- while it is visible, and draws all of itself again when it is made visible,
-- moved or resized. What is drawn on a window that is not visible is kept
-- for later, which is the whole point.

local window = {}

function window.create(parent, x, y, width, height, visible)
    visible = visible ~= false
    local cells = {}
    local cursorX, cursorY, text, back, blink = 1, 1, colors.white, colors.black, false

    local function blankRow()
        local row = {}
        for column = 1, width do row[column] = { " ", text, back } end
        return row
    end
    for row = 1, height do cells[row] = blankRow() end

    local self = {}
    local function drawRow(row)
        if not visible or not cells[row] then return end
        for column = 1, width do
            local cell = cells[row][column]
            parent.setCursorPos(x + column - 1, y + row - 1)
            parent.setTextColor(cell[2])
            parent.setBackgroundColor(cell[3])
            parent.write(cell[1])
        end
    end

    function self.redraw()
        for row = 1, height do drawRow(row) end
    end

    function self.write(value)
        value = tostring(value)
        local row = cells[cursorY]
        for index = 1, #value do
            local column = cursorX + index - 1
            if row and column >= 1 and column <= width then
                row[column] = { value:sub(index, index), text, back }
            end
        end
        cursorX = cursorX + #value
        drawRow(cursorY)
    end
    function self.blit(value) self.write(value) end
    function self.clear()
        for row = 1, height do cells[row] = blankRow() end
        self.redraw()
    end
    function self.clearLine()
        if cells[cursorY] then cells[cursorY] = blankRow() end
        drawRow(cursorY)
    end
    function self.scroll(lines)
        for _ = 1, lines do
            table.remove(cells, 1)
            cells[#cells + 1] = blankRow()
        end
        self.redraw()
    end
    function self.getSize() return width, height end
    function self.getPosition() return x, y end
    function self.isColor() return true end
    self.isColour = self.isColor
    function self.setCursorPos(newX, newY) cursorX, cursorY = math.floor(newX), math.floor(newY) end
    function self.getCursorPos() return cursorX, cursorY end
    function self.setCursorBlink(on) blink = on == true end
    function self.getCursorBlink() return blink end
    function self.setTextColor(colour) text = colour end
    self.setTextColour = self.setTextColor
    function self.getTextColor() return text end
    self.getTextColour = self.getTextColor
    function self.setBackgroundColor(colour) back = colour end
    self.setBackgroundColour = self.setBackgroundColor
    function self.getBackgroundColor() return back end
    self.getBackgroundColour = self.getBackgroundColor
    function self.setVisible(on)
        on = on == true
        if on ~= visible then
            visible = on
            if visible then self.redraw() end
        end
    end
    function self.isVisible() return visible end
    function self.reposition(newX, newY, newWidth, newHeight)
        x, y = newX, newY
        if newWidth and newHeight then
            local resized = {}
            for row = 1, newHeight do
                resized[row] = {}
                for column = 1, newWidth do
                    resized[row][column] = cells[row] and cells[row][column] or { " ", text, back }
                end
            end
            cells, width, height = resized, newWidth, newHeight
        end
        self.redraw()
    end
    -- For the test: one row as text.
    function self.line(row)
        local out = {}
        for column = 1, width do out[column] = cells[row] and cells[row][column][1] or " " end
        return table.concat(out)
    end
    return self
end

return window
