local skynet = require "skynet"

skynet.start(function()
    skynet.error("[start main] hello world")

    -- 启动打工服务，其中第二个参数和第三个参数会透传给service/worker/init.lua脚本
    local worker1 = skynet.newservice("worker", "felix_worker", 1001)
    local buyer1 = skynet.newservice("buyer", "felix_buyer", 1002)

    skynet.fork(function()
        
        skynet.send(worker1, "lua", "start_work")
        skynet.sleep(200)

        skynet.send(buyer1, "lua", "buy")
        skynet.sleep(200)

        skynet.send(worker1, "lua", "stop_work")
        skynet.send(buyer1, "lua", "buy")

        skynet.exit()
    end)

end)
