local skynet = require "skynet"
local cluster = require "skynet.cluster"

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
        cluster.open("node1")
        skynet.fork(function()
            -- 启动打工服务，其中第二个参数和第三个参数会透传给service/worker/init.lua脚本
            local worker1 = skynet.newservice("worker", "felix_worker", 1001)

            skynet.send(worker1, "lua", "start_work")
            skynet.sleep(200)
            skynet.send(worker1, "lua", "stop_work")

            skynet.exit()
        end)
    else
        cluster.open("node2")
        skynet.fork(function()
            local buyer1 = skynet.newservice("buyer", "felix_buyer", 1002)

            skynet.send(buyer1, "lua", "buy")
            skynet.sleep(200)
            skynet.send(buyer1, "lua", "buy")
            skynet.sleep(200)
            skynet.send(buyer1, "lua", "buy")

            skynet.exit()
        end)
    end
end)
