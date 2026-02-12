local skynet = require "skynet"
local cluster = require "skynet.cluster"
local skynet_manager = require "skynet.manager"

skynet.start(function()
    skynet.error("[start main] hello world")

    -- 集群配置
    -- cluster.reload({
    --     node1 = "127.0.0.1:37001",
    --     node2 = "127.0.0.1:37002",
    -- })

    local myNode = skynet.getenv("node") or "node1"
    skynet.error("Current node is " .. myNode)

    if myNode == "node1" then
        skynet.fork(function()
            cluster.open("node1")
            -- 启动打工服务，其中第二个参数和第三个参数会透传给service/worker/init.lua脚本
            local worker1 = skynet.newservice("worker", "felix_worker", 1001)
            skynet.error("worker1 addr is " .. tostring(worker1))
            cluster.register("felix_worker", worker1)
            --skynet.name("felix_worker", worker1)

            -- 让打工者开始工作
            skynet.send(worker1, "lua", "start_work")
            skynet.sleep(200)
            skynet.send(worker1, "lua", "stop_work")

            skynet.exit()
        end)
    else
        skynet.fork(function()
            cluster.open("node2")
            local buyer1 = skynet.newservice("buyer", "felix_buyer", 1002)
            cluster.register("felix_buyer", buyer1)

            skynet.send(buyer1, "lua", "buy")
            skynet.sleep(200)
            skynet.send(buyer1, "lua", "buy")
            skynet.sleep(200)
            skynet.send(buyer1, "lua", "buy")

            skynet.exit()
        end)
    end
end)
