-- PUMPE GAME: Brick Breaker

























local game = {}

local BRICK_COLORS = { colors.red, colors.orange, colors.yellow, colors.lime,
colors.cyan }
local BRICK_WIDTH = 3

function game.wall(state)
state.bricks = {}
local rows = math.min(#BRICK_COLORS, math.max(2, math.floor(state.height / 4)))
for row = 1, rows do
for x = 1, state.width - BRICK_WIDTH + 1, BRICK_WIDTH + 1 do
state.bricks[#state.bricks + 1] = { x = x, y = row + 1,
color = BRICK_COLORS[row] }
end
end
end


function game.serve(state)
state.ball = { x = state.paddleX + math.floor(state.paddle / 2),
y = state.height - 1, dx = 1, dy = -1 }
state.held = true
end

function game.new(width, height, random)
local state = { width = width, height = height, random = random, score = 0,
lives = 3, paddle = math.max(3, math.floor(width / 5)),
status = "A to launch" }
state.paddleX = math.floor((width - state.paddle) / 2) + 1
game.wall(state)
game.serve(state)
return state
end

function game.input(state, key)
if key == "left" then
state.paddleX = math.max(1, state.paddleX - 2)
elseif key == "right" then
state.paddleX = math.min(state.width - state.paddle + 1, state.paddleX + 2)
elseif key == "a" and state.held then
state.held, state.status = false, nil
end
if state.held then
state.ball.x = state.paddleX + math.floor(state.paddle / 2)
end
end

local function brickAt(state, x, y)
for index, brick in ipairs(state.bricks) do
if y == brick.y and x >= brick.x and x < brick.x + BRICK_WIDTH then
return index
end
end
end

function game.tick(state)
if state.held or state.over then return end
local ball = state.ball
local nextX, nextY = ball.x + ball.dx, ball.y + ball.dy
if nextX < 1 or nextX > state.width then
ball.dx = -ball.dx
nextX = ball.x + ball.dx
end
if nextY < 1 then
ball.dy = -ball.dy
nextY = ball.y + ball.dy
end
local hit = brickAt(state, nextX, nextY)
if hit then
table.remove(state.bricks, hit)
state.score = state.score + 1
ball.dy = -ball.dy
nextY = ball.y + ball.dy
end
if nextY == state.height and nextX >= state.paddleX
and nextX < state.paddleX + state.paddle then

local along = (nextX - state.paddleX) / state.paddle
ball.dx = along < 0.34 and -1 or along > 0.66 and 1 or ball.dx
ball.dy = -1
nextY = ball.y - 1
elseif nextY > state.height then
state.lives = state.lives - 1
if state.lives <= 0 then
state.over, state.status = true, "Out of balls"
return
end
game.serve(state)
state.status = state.lives .. (state.lives == 1 and " ball" or " balls")
.. " left. A to launch"
return
end
ball.x, ball.y = nextX, nextY
if #state.bricks == 0 then
game.wall(state)
game.serve(state)
state.status = "A new wall. A to launch"
end
end

function game.speed(state)
return math.max(0.06, 0.14 - state.score * 0.001)
end

function game.draw(state, screen)
screen.fill(1, 1, screen.width, screen.height, colors.black)
for _, brick in ipairs(state.bricks) do
screen.fill(brick.x, brick.y, BRICK_WIDTH, 1, brick.color)
end
screen.fill(state.paddleX, state.height, state.paddle, 1, colors.white)
screen.fill(state.ball.x, state.ball.y, 1, 1, colors.lightGray)
screen.text(1, 1, "BALLS " .. state.lives, colors.gray, colors.black)
end

return game
