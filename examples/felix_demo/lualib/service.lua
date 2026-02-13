local skynet = require "skynet"
local cluster = require "skynet.cluster"

-- 封装服务类
local M = {
    -- 服务名
    name = "",
    -- 服务id
    id = 0,
    -- 退出
    exit = nil,
    -- 初始化
    init = nil,
    -- 消息响应函数表
    resp = {},
}

-- 输出堆栈
local function tracback(err)
    skynet.error(tostring(err))
    skynet.error(debug.traceback())
end

-- 消息分发
local dispatch = function(session, address, cmd, ...)
    -- 从resp表中查找是否存在消息的响应函数
    local func = M.resp[cmd]
    if not func then
        skynet.error(M.name .. " " .. M.id .. " dispatch error, unknown cmd: " .. tostring(cmd))
        skynet.ret()
        return
    end
    -- 调用响应函数
    local ret = table.pack(xpcall(func, tracback, address, ...))
    local isok = ret[1]

    if not isok then
        skynet.error(M.name .. " " .. M.id .. " dispatch error, func call failed: " .. tostring(cmd))
        skynet.ret()
        return
    end

    skynet.retpack(table.unpack(ret, 2))
end

-- 初始化
local function init()
    skynet.error(M.name .. " " .. M.id .. " init")
    skynet.dispatch("lua", dispatch)
    if M.init then
        M.init()
    end
end

-- 启动服务
function M.start(name, id, ...)
    M.name = name
    M.id = tonumber(id)
    skynet.start(init)
end

function M.call(node, srv, ...)
    local mynode = skynet.getenv("node")
    if node == mynode then
        skynet.error(M.name .. " " .. M.id .. " local call: " .. node .. " - " .. srv)
        return skynet.call(srv, "lua", ...)
    else
        skynet.trace("cluster")
        skynet.error(M.name .. " " .. M.id .. " cluster call: " .. node .. " - " .. srv)
        return cluster.call(node, srv, ...)
    end
end

function M.send(node, srv, ...)
    local mynode = skynet.getenv("node")
    if node == mynode then
        skynet.error(M.name .. " " .. M.id .. " local send: " .. node .. " - " .. srv)
        return skynet.send(srv, "lua", ...)
    else
        skynet.error(M.name .. " " .. M.id .. " cluster send: " .. node .. " - " .. srv)
        return cluster.send(node, srv, ...)
    end
end

return M
