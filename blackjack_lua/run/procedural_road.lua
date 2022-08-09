-- Copyright (C) 2022 setzer22 and contributors
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local P = require("params")
local PriorityQueue = require("priority_queue")
local V = require("vector_math")
local T = require("table_helpers")

local function load_function(code)
    local func, err = loadstring(code)
    if err ~= nil then
        error(err)
    end
    if typeof(func) ~= "function" then
        error("Code should be a single lua function")
    end
    return func
end

local function search_road_astar(noise_fn, scale, start, goal)
    --- The start and goal points are snapped to a grid, and represented as
    --- whole numbers. This prevents A* from treating two equal positions as
    --- different due to numerical precision issues.
    local start = V.floor(start / scale)
    start = vector(start.x, 0, start.z)
    local goal = V.floor(goal / scale)
    goal = vector(goal.x, 0, goal.z)

    --- Given a position, returns the list of grid-aligned neighbors
    --- in 8-directions.
    local function neighbors(current)
        return {
            current + vector(0, 0, 1),
            current + vector(1, 0, 1),
            current + vector(1, 0, 0),
            current + vector(1, 0, -1),
            current + vector(0, 0, -1),
            current + vector(-1, 0, -1),
            current + vector(-1, 0, 0),
            current + vector(-1, 0, 1),
        }
    end

    --- Returns the height of the noise function at a given position. Handles
    --- the scale transformation.
    local function height_at(position)
        return noise_fn(position * scale).y
    end

    --- The heuristic function. Since we need the distance function to be overly
    --- optimistic, we only take the distance factor into account, assuming
    --- there is no elevation difference between the two points.
    ---
    --- This is actually a pretty bad heuristic, but it's optimistic, so it
    --- guarantees optimality.
    local function heuristic(goal, n)
        local n_floor = vector(n.x, 0, n.z)
        local goal_floor = vector(goal.x, 0, goal.z)
        local dist = V.distance(n_floor * scale, goal_floor * scale)
        return dist
    end

    --- The cost of going from position prv to nxt in the graph. That is the
    --- distance, as seen from the top, plus the elevation difference squared.
    ---
    --- This cost function puts more weight into the elevation, which means
    --- results will tend to minimize elevation before distance, creating
    --- sinuous roads with lots of curves.
    local function cost(prv, nxt)
        local prv_floor = vector(prv.x, 0, prv.z)
        local nxt_floor = vector(nxt.x, 0, nxt.z)
        local dist = V.distance(prv_floor * scale, nxt_floor * scale)

        local elevation_delta = height_at(nxt) - height_at(prv)

        return dist + (elevation_delta * elevation_delta) / (0.05 * scale)
    end

    local frontier = PriorityQueue()
    frontier:put(start, 0)

    local came_from = {}
    came_from[start] = "__end__" -- special sigil to mark end of path

    local cost_so_far = {}
    cost_so_far[start] = 0

    while not frontier:empty() do
        local current = frontier:pop()
        if current == goal then
            break
        end

        for _, n in neighbors(current) do
            local new_cost = cost_so_far[current] + cost(current, n)

            if came_from[n] == nil or cost_so_far[n] == nil or new_cost < cost_so_far[n] then
                cost_so_far[n] = new_cost
                local priority = new_cost + heuristic(goal, n)
                frontier:put(n, priority)
                came_from[n] = current
            end
        end
    end

    local path = {}
    local path_marker = goal
    while path_marker ~= "__end__" do
        table.insert(path, path_marker * scale)
        path_marker = came_from[path_marker]
    end

    return T.reverse(path)
end

local test_channel_nodes = {
    ProceduralRoad = {
        label = "Procedural road",
        op = function(inputs)
            local scale = 0.05 -- TODO @Hardcoded @Heightmap
            local noise = load_function(inputs.noise_fn)
            local noise_fn = function(pos)
                local j = pos.x / scale
                local i = pos.z / scale
                return vector(pos.x, noise(i, j), pos.z)
            end
            local mesh = Primitives.cube(noise_fn(inputs.src), vector(0.1, 0.1, 0.1))
            Ops.merge(mesh, Primitives.cube(noise_fn(inputs.dst), vector(0.1, 0.1, 0.1)))

            local src = inputs.src
            local dst = inputs.dst

            local path = search_road_astar(noise_fn, 0.125, src, dst)
            for i = 1,#path-1 do
                local p = noise_fn(path[i])
                local p2 = noise_fn(path[i+1])
                mesh:add_edge(p, p2)
            end

            return { out_mesh = mesh }
        end,
        inputs = {
            P.lua_str("noise_fn"),
            P.v3("src", vector(0.1, 0.1, 0.1)),
            P.v3("dst", vector(0.9, 0.9, 0.9)),
        },
        outputs = {
            P.mesh("out_mesh"),
        },
        returns = "out_mesh",
    },
}

NodeLibrary:addNodes(test_channel_nodes)
