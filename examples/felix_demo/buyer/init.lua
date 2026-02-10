local skynet = require "skynet"
local buyer = require "service"

buyer.cat_food_price = 5
buyer.cat_food_cnt = 0

buyer.resp.buy = function(source)
    skynet.error(buyer.name .. " " .. tostring(buyer.id) .. " buy start")

    local ok, result_or_err = pcall(skynet.call, "felix_worker", "lua", "change_money", -buyer.cat_food_price)
    if not ok then
        -- skynet.call 调用本身失败（服务不存在、消息发送失败等）
        skynet.error(buyer.name .. " " .. tostring(buyer.id) .. " buy error: ", result_or_err)
        return false
    else
        skynet.error(buyer.name .. " " .. tostring(buyer.id) .. " buy ok: ", result_or_err)
        -- 调用成功, 但还需看业务层结果, 先扣费
        local left_money = result_or_err
        if left_money >= 0 then
            buyer.cat_food_cnt = buyer.cat_food_cnt + 1
            skynet.error("buy cat food ok, current cnt: " .. tostring(buyer.cat_food_cnt))
            return true
        end
        -- 购买失败，把钱加回去
        skynet.error("buy failed, money not enough")
        skynet.call("felix_worker", "lua", "change_money", buyer.cat_food_price)
        return false
    end
end

buyer.start(...)
